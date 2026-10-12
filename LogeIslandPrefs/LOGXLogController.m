//
//  LOGXLogController.m
//  诊断日志页：展示插件心跳信息 + 日志尾部（Logs.Tail，插件每 5 秒发布），
//  支持分享与清空。出问题时可直接把日志发给落格反馈。
//

#import "LOGXBrand.h"
#import "LOGXLogController.h"

#import <notify.h>

static NSString *const kInfoCellID = @"LOGXInfoCell";
static NSString *const kLogCellID = @"LOGXLogCell";

@interface LOGXLogController ()
@property (nonatomic) int reloadToken;
@property (nonatomic, copy) NSString *logText;
@property (nonatomic, copy) NSDictionary *heartbeat;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation LOGXLogController

- (void)dealloc {
    if (_reloadToken >= 0) notify_cancel(_reloadToken);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"诊断日志";
    self.navigationController.navigationBar.tintColor = kLOGXColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44.0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kInfoCellID];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kLogCellID];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                           target:self
                                                                                           action:@selector(shareTapped)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(clearTapped)];
    notify_register_dispatch(LOGX_NOTIFY_RELOAD, &_reloadToken, dispatch_get_main_queue(), ^(__unused int token) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshData]; });
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshData];
}

- (void)refreshData {
    _heartbeat = LOGXPrefsObject(LOGX_KEY_HEARTBEAT);
    if (![_heartbeat isKindOfClass:NSDictionary.class]) _heartbeat = nil;
    NSString *tail = LOGXPrefsObject(LOGX_KEY_LOG_TAIL);
    _logText = [tail isKindOfClass:NSString.class] ? tail : @"";
    [self.tableView reloadData];
}

#pragma mark - 操作

- (void)shareTapped {
    NSString *content = [NSString stringWithFormat:@"落格Loge·灵动岛 诊断日志\n\n引擎：%@\n\n%@\n\n%@",
                         _heartbeat ? _heartbeat.description : @"未检测到", _logText, @""];
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"loge-island-diag.txt"]];
    [content writeToURL:tempURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[tempURL]
                                                                           applicationActivities:nil];
    if (UIUserInterfaceIdiomPad == UIDevice.currentDevice.userInterfaceIdiom) {
        activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)clearTapped {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                    message:@"将同时清空插件端的诊断日志文件。继续吗？"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        LOGXPrefsSetObject(@YES, LOGX_KEY_LOG_CLEAR_REQ);
        LOGXPrefsSynchronize();
        notify_post(LOGX_NOTIFY_RELOAD);
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return (section == 0) ? @"引擎状态" : @"日志";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"日志实时同步自插件（最近 64KB）。有问题时点右上角分享给落格即可。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kInfoCellID forIndexPath:indexPath];
    cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        NSString *version = _heartbeat ? [NSString stringWithFormat:@"v%@", _heartbeat[@"version"] ?: @"?"] : @"未检测到";
        NSString *pid = _heartbeat ? [NSString stringWithFormat:@"%@", _heartbeat[@"pid"] ?: @"?"] : @"—";
        NSString *at = _heartbeat ? (_heartbeat[@"atText"] ?: @"—") : @"—";
        NSString *suspended = _heartbeat && [_heartbeat[@"suspended"] boolValue] ? @"（已暂停）" : @"";
        if (indexPath.row == 0) {
            cell.textLabel.text = @"插件版本";
            cell.detailTextLabel.text = [version stringByAppendingString:suspended];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"SpringBoard PID";
            cell.detailTextLabel.text = pid;
        } else {
            cell.textLabel.text = @"最近心跳";
            cell.detailTextLabel.text = at;
        }
        return cell;
    }

    // 日志正文：可选中复制
    UITableViewCell *logCell = [tableView dequeueReusableCellWithIdentifier:kLogCellID forIndexPath:indexPath];
    if (_textView == nil) {
        _textView = [[UITextView alloc] initWithFrame:CGRectZero textContainer:nil];
        _textView.editable = NO;
        _textView.selectable = YES;
        _textView.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
        _textView.textColor = UIColor.labelColor;
        _textView.translatesAutoresizingMaskIntoConstraints = NO;
        _textView.scrollEnabled = NO;
        [logCell.contentView addSubview:_textView];
        [NSLayoutConstraint activateConstraints:@[
            [NSLayoutConstraint constraintWithItem:_textView attribute:NSLayoutAttributeTop
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:logCell.contentView attribute:NSLayoutAttributeTop
                                        multiplier:1.0 constant:10.0],
            [NSLayoutConstraint constraintWithItem:_textView attribute:NSLayoutAttributeLeading
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:logCell.contentView attribute:NSLayoutAttributeLeading
                                        multiplier:1.0 constant:12.0],
            [NSLayoutConstraint constraintWithItem:_textView attribute:NSLayoutAttributeTrailing
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:logCell.contentView attribute:NSLayoutAttributeTrailing
                                        multiplier:1.0 constant:-12.0],
            [NSLayoutConstraint constraintWithItem:_textView attribute:NSLayoutAttributeBottom
                                         relatedBy:NSLayoutRelationEqual
                                            toItem:logCell.contentView attribute:NSLayoutAttributeBottom
                                        multiplier:1.0 constant:-10.0],
            [NSLayoutConstraint constraintWithItem:_textView attribute:NSLayoutAttributeHeight
                                         relatedBy:NSLayoutRelationGreaterThanOrEqual
                                            toItem:nil attribute:NSLayoutAttributeNotAnAttribute
                                        multiplier:1.0 constant:120.0],
        ]];
    }
    _textView.text = _logText.length > 0 ? _logText : @"（暂无日志——插件尚未发布日志尾部，请先注销重启后再试）";
    return logCell;
}

@end
