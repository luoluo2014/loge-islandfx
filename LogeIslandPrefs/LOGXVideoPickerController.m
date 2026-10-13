//
//  LOGXVideoPickerController.m
//  背景视频选择页：
//   - 从相册直接添加（PHPicker，无需给相册授权）
//   - 在 Filza 中打开素材目录（手动管理）
//   - 从插件已收到的素材里选取（点选即用，滑动删除）
//  导入走 CFPreferences blob 投递：设置端暂存 → 插件 5 秒内落地真实目录。
//

#import "LOGXBrand.h"
#import "LOGXVideoPickerController.h"

#import <notify.h>
#import <PhotosUI/PhotosUI.h>

static NSString *const kCellIdentifier = @"LOGXAssetCell";
static NSString *const kActionCellIdentifier = @"LOGXActionCell";

@interface LOGXVideoPickerController () <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *modeKey;          // Compact.Path / Expanded.Path
@property (nonatomic, copy) NSArray<NSDictionary *> *assets;
@property (nonatomic) int reloadToken;
@property (nonatomic, copy, nullable) NSString *verifyingName;
@property (nonatomic, strong) dispatch_source_t verifyTimer;
@property (nonatomic) NSInteger verifyAttempts;
@end

@implementation LOGXVideoPickerController

- (instancetype)initWithModeKey:(NSString *)modeKey {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (!self) return nil;
    _modeKey = modeKey;
    _assets = @[];
    BOOL compact = [modeKey hasPrefix:@"Compact"];
    self.title = compact ? @"紧凑背景视频" : @"展开背景视频";
    return self;
}

- (void)dealloc {
    if (_reloadToken >= 0) notify_cancel(_reloadToken);
    if (_verifyTimer) { dispatch_source_cancel(_verifyTimer); _verifyTimer = NULL; }
}

#pragma mark - 数据

- (NSString *)currentSelection {
    return LOGXConfigString(_modeKey);
}

- (void)reloadAssets {
    NSArray *assets = LOGXPrefsObject(LOGX_KEY_ASSETS_VIDEOS);
    _assets = [assets isKindOfClass:NSArray.class] ? assets : @[];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = kLOGXColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kCellIdentifier];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kActionCellIdentifier];
    // 插件每 5 秒发布一次素材清单，保持列表最新（导入落地后自动出现）
    notify_register_dispatch(LOGX_NOTIFY_RELOAD, &_reloadToken, dispatch_get_main_queue(), ^(__unused int token) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadAssets]; });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadAssets];
}

#pragma mark - TableView 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? 2 : _assets.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return (section == 0) ? @"添加" : [NSString stringWithFormat:@"素材目录（%lu）", (unsigned long)_assets.count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return [NSString stringWithFormat:@"目录：%@\n也可用 Filza 手动管理后回到本页选取。", LOGXRealVideosDirectory()];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kActionCellIdentifier forIndexPath:indexPath];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"从相册添加视频";
            cell.textLabel.textColor = kLOGXColor;
        } else {
            cell.textLabel.text = @"在 Filza 中打开";
            cell.textLabel.textColor = kLOGXColor;
        }
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier forIndexPath:indexPath];
    NSDictionary *asset = _assets[indexPath.row];
    NSString *name = [asset[@"name"] isKindOfClass:NSString.class] ? asset[@"name"] : @"?";
    NSUInteger sizeKB = [asset[@"size"] unsignedIntegerValue];
    NSString *sizeText = (sizeKB >= 1024)
        ? [NSString stringWithFormat:@"%.1f MB", sizeKB / 1024.0]
        : [NSString stringWithFormat:@"%lu KB", (unsigned long)sizeKB];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = sizeText;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    BOOL selected = [name isEqualToString:self.currentSelection];
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    if (selected) cell.textLabel.textColor = kLOGXColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            [self presentPhotoPicker];
        } else {
            [self openFilza];
        }
        return;
    }
    NSDictionary *asset = _assets[indexPath.row];
    NSString *name = [asset[@"name"] isKindOfClass:NSString.class] ? asset[@"name"] : nil;
    if (name.length == 0) return;
    LOGXPrefsSetObject(name, _modeKey);
    LOGXPrefsSynchronize();
    notify_post(LOGX_NOTIFY_RELOAD);
    [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                            forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSDictionary *asset = _assets[indexPath.row];
    NSString *name = [asset[@"name"] isKindOfClass:NSString.class] ? asset[@"name"] : nil;
    if (name.length == 0) return;
    // 删除请求交给插件落地（设置端够不着真实目录）。
    // 2.0.14：写入删除队列数组（插件端不能用 CFPreferencesCopyKeyList 遍历，会崩，改读队列）。
    NSArray *existingQueue = LOGXPrefsObject(LOGX_KEY_DELETE_QUEUE);
    NSMutableArray *queue = [existingQueue isKindOfClass:NSArray.class] ? [existingQueue mutableCopy] : [NSMutableArray array];
    if (![queue containsObject:name]) [queue addObject:name];
    LOGXPrefsSetObject(queue, LOGX_KEY_DELETE_QUEUE);
    LOGXPrefsSynchronize();
    notify_post(LOGX_NOTIFY_RELOAD);
    // 若删的正是当前选择，顺带清空路径
    if ([name isEqualToString:self.currentSelection]) {
        LOGXPrefsSetObject(@"", _modeKey);
        LOGXPrefsSynchronize();
        notify_post(LOGX_NOTIFY_RELOAD);
    }
    NSMutableArray *remaining = [_assets mutableCopy];
    [remaining removeObjectAtIndex:indexPath.row];
    _assets = remaining;
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - 相册导入

- (void)presentPhotoPicker {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.filter = PHPickerFilter.videosFilter;
        configuration.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    NSString *movieType = @"public.movie";
    if (![result.itemProvider hasItemConformingToTypeIdentifier:movieType]) {
        [self showAlert:@"无法导入" message:@"所选内容不是视频。"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [result.itemProvider loadFileRepresentationForTypeIdentifier:movieType completionHandler:^(NSURL *url, NSError *error) {
        if (!url || error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showAlert:@"无法导入" message:error.localizedDescription ?: @"读取所选视频失败。"];
            });
            return;
        }
        // 该 URL 只在回调内有效：必须在这里读成数据并暂存
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        if (data == nil) data = [NSData dataWithContentsOfURL:url];
        if (data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showAlert:@"无法导入" message:@"视频数据为空。"]; });
            return;
        }
        NSString *name = [weakSelf stageVideoData:data suggestedName:url.lastPathComponent];
        if (name.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            // 乐观选中：插件落地后立即生效
            LOGXPrefsSetObject(name, weakSelf.modeKey);
            LOGXPrefsSynchronize();
            notify_post(LOGX_NOTIFY_RELOAD);
            [weakSelf reloadAssets];
            [weakSelf verifyDeliveryOfName:name];
        });
    }];
}

/// 暂存为投递 blob；返回最终文件名（重名自动加序号）
- (nullable NSString *)stageVideoData:(NSData *)data suggestedName:(nullable NSString *)suggested {
    static const NSUInteger kMaxBlobBytes = 64ULL * 1024ULL * 1024ULL;
    if (data.length > kMaxBlobBytes) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:@"视频过大"
                    message:[NSString stringWithFormat:@"体积 %lu MB 超过投递上限（64 MB）。\n请改用 Filza 把文件放进：\n%@",
                             (unsigned long)(data.length / 1024 / 1024), LOGXRealVideosDirectory()]];
        });
        return nil;
    }

    NSString *extension = suggested.pathExtension.length > 0 ? suggested.pathExtension : @"mp4";
    NSString *base = [suggested stringByDeletingPathExtension];
    if (base.length == 0) base = @"video";
    NSString *name = [base stringByAppendingPathExtension:extension].lastPathComponent;

    NSMutableSet<NSString *> *existing = [NSMutableSet set];
    for (NSDictionary *asset in _assets) {
        if ([asset[@"name"] isKindOfClass:NSString.class]) [existing addObject:asset[@"name"]];
    }
    if ([existing containsObject:name]) {
        NSString *stem = name.stringByDeletingPathExtension;
        NSUInteger index = 2;
        NSString *candidate = name;
        while ([existing containsObject:candidate]) {
            candidate = [stem stringByAppendingFormat:@"_%lu", (unsigned long)index++];
        }
        name = [candidate stringByAppendingPathExtension:extension] ?: candidate;
    }

    NSString *blobKey = [NSString stringWithFormat:LOGX_KEY_IMPORT_BLOB_FMT, name];
    LOGXPrefsSetObject(data, blobKey);
    NSMutableArray *pending = [LOGXPrefsObject(LOGX_KEY_PENDING_IMPORTS) mutableCopy];
    if (![pending isKindOfClass:NSMutableArray.class]) pending = [NSMutableArray array];
    if (![pending containsObject:name]) [pending addObject:name];
    LOGXPrefsSetObject(pending, LOGX_KEY_PENDING_IMPORTS);
    LOGXPrefsSynchronize();

    // 写后立刻读回校验：确认 blob 真的落进了跨进程共享域
    NSData *readBack = LOGXPrefsObject(blobKey);
    BOOL ok = [readBack isKindOfClass:NSData.class] && readBack.length == data.length;
    LOGXDiag(@"设置端暂存视频 %@（%lu KB），读回校验%@", name, (unsigned long)(data.length / 1024), ok ? @"通过" : @"失败");
    if (!ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlert:@"投递通道异常"
                    message:[NSString stringWithFormat:@"配置域写入校验失败，插件可能收不到「%@」。\n\n可改用 Filza 把文件放进：\n%@", name, LOGXRealVideosDirectory()]];
        });
    }
    return name;
}

#pragma mark - 投递验证（导入后确认插件已落地）

- (void)verifyDeliveryOfName:(NSString *)name {
    _verifyingName = name;
    _verifyAttempts = 0;
    if (_verifyTimer) { dispatch_source_cancel(_verifyTimer); _verifyTimer = NULL; }
    _verifyTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_verifyTimer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_verifyTimer, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.verifyAttempts += 1;
        NSArray *assets = LOGXPrefsObject(LOGX_KEY_ASSETS_VIDEOS);
        BOOL delivered = NO;
        if ([assets isKindOfClass:NSArray.class]) {
            for (NSDictionary *asset in assets) {
                if ([asset[@"name"] isKindOfClass:NSString.class] && [asset[@"name"] isEqualToString:name]) {
                    delivered = YES;
                    break;
                }
            }
        }
        if (delivered) {
            [self finishVerification:YES name:name];
        } else if (self.verifyAttempts >= 20) {   // 10 秒
            [self finishVerification:NO name:name];
        }
    });
    dispatch_resume(_verifyTimer);
}

- (void)finishVerification:(BOOL)delivered name:(NSString *)name {
    if (_verifyTimer) { dispatch_source_cancel(_verifyTimer); _verifyTimer = NULL; }
    _verifyingName = nil;
    if (delivered) {
        [self showAlert:@"已导入" message:[NSString stringWithFormat:@"「%@」已存入素材目录并选中。", name]];
    } else {
        [self showAlert:@"等待插件落地"
                message:[NSString stringWithFormat:@"「%@」已暂存，但插件尚未确认收到。\n\n请依次尝试：\n1. 稍等 10 秒（插件每 5 秒检查一次投递队列）；\n2. 若头部显示未检测到引擎，先注销重启；\n3. 仍不行就用 Filza 把文件放进：\n%@\n\n详细过程见「诊断日志」。", name, LOGXRealVideosDirectory()]];
    }
}

#pragma mark - Filza

- (void)openFilza {
    NSString *path = LOGXRealVideosDirectory();
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: path;
    NSArray<NSString *> *candidates = @[
        [NSString stringWithFormat:@"filza://view/%@", encoded],
        [NSString stringWithFormat:@"filza://%@", encoded],
    ];
    __weak typeof(self) weakSelf = self;
    [self tryOpenURLs:candidates index:0 completion:^{
        [weakSelf showAlert:@"无法打开文件管理器"
                    message:[NSString stringWithFormat:@"设备上可能没有 Filza。\n\n素材目录路径：\n%@\n\n可复制后手动前往。", path]];
    }];
}

- (void)tryOpenURLs:(NSArray<NSString *> *)candidates index:(NSUInteger)index completion:(void (^)(void))completion {
    if (index >= candidates.count) {
        if (completion) completion();
        return;
    }
    NSURL *url = [NSURL URLWithString:candidates[index]];
    if (!url) {
        [self tryOpenURLs:candidates index:index + 1 completion:completion];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:url options:@{}
        completionHandler:^(BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) return;
                [weakSelf tryOpenURLs:candidates index:index + 1 completion:completion];
            });
        }];
}

#pragma mark - 提示

- (void)showAlert:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
