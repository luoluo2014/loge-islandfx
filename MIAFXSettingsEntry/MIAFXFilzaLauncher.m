//
//  MIAFXFilzaLauncher.m
//  MIAFXPrefs
//

#import "MIAFXFilzaLauncher.h"

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXPath.h"

#import <notify.h>

@interface MIAFXFilzaLauncher ()
@property (nonatomic, strong) NSMutableArray<NSURL *> *openQueue;
@end

@implementation MIAFXFilzaLauncher

+ (instancetype)sharedLauncher {
    static MIAFXFilzaLauncher *launcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ launcher = [[MIAFXFilzaLauncher alloc] init]; });
    return launcher;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _openQueue = [NSMutableArray array];
    return self;
}

#pragma mark 路径

- (NSString *)dataDirectory { return MIAFXDataDirectory(); }
- (NSString *)videosDirectory { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Videos"]; }
- (NSString *)masksDirectory { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Masks"]; }
- (NSString *)customOrbitsDirectory { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"CustomOrbits"]; }
- (NSString *)presetsDirectory { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Presets"]; }
- (NSString *)logsDirectory { return [MIAFXDataDirectory() stringByAppendingPathComponent:@"Logs"]; }
- (NSString *)configurationFilePath { return MIAFXSettingsPath(); }
- (NSString *)settingsFilePath { return MIAFXSettingsPath(); }
- (NSString *)diagnosticsFilePath { return MIAFXDiagnosticsPath(); }
- (NSString *)panicFilePath { return MIAFXPanicPath(); }
- (NSString *)logFilePath { return MIAFXLogPath(); }

- (BOOL)ensureDirectories {
    NSError *error = nil;
    BOOL ok = MIAFXEnsureDataDirectories(&error);
    if (!ok) {
        NSLog(@"[MIAFX] 创建数据目录失败: %@", error.localizedDescription);
    }
    return ok;
}

- (NSString *)pathForLocation:(MIAFXFilzaLocation)location {
    switch (location) {
        case MIAFXFilzaLocationVideos: return [self videosDirectory];
        case MIAFXFilzaLocationMasks: return [self masksDirectory];
        case MIAFXFilzaLocationCustomOrbits: return [self customOrbitsDirectory];
        case MIAFXFilzaLocationPresets: return [self presetsDirectory];
        case MIAFXFilzaLocationLogs: return [self logsDirectory];
        case MIAFXFilzaLocationConfiguration: return [self configurationFilePath];
    }
    return [self dataDirectory];
}

- (NSString *)displayNameForLocation:(MIAFXFilzaLocation)location {
    switch (location) {
        case MIAFXFilzaLocationVideos: return @"视频素材";
        case MIAFXFilzaLocationMasks: return @"遮罩素材";
        case MIAFXFilzaLocationCustomOrbits: return @"自定义轨迹";
        case MIAFXFilzaLocationPresets: return @"预设";
        case MIAFXFilzaLocationLogs: return @"日志";
        case MIAFXFilzaLocationConfiguration: return @"配置文件";
    }
    return @"数据目录";
}

#pragma mark URL 构造

/// 除 unreserved 字符外的全部进行百分号编码（需求：filza://view/<percent encoded>）
- (NSString *)percentEncodedPath:(NSString *)path {
    if (path.length == 0) return @"";
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    NSString *encoded = [path stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return encoded ?: path;
}

- (NSArray<NSURL *> *)filzaURLsForPath:(NSString *)path {
    NSString *encoded = [self percentEncodedPath:path];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSURL *viewURL = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view/%@", encoded]];
    if (viewURL) [urls addObject:viewURL];
    NSURL *directURL = [NSURL URLWithString:[NSString stringWithFormat:@"filza://%@", encoded]];
    if (directURL) [urls addObject:directURL];
    return urls;
}

#pragma mark 打开

- (void)openLocation:(MIAFXFilzaLocation)location fromViewController:(UIViewController *)presenter {
    [self ensureDirectories];
    NSString *path = [self pathForLocation:location];
    NSString *title = [self displayNameForLocation:location];
    [self openPath:path title:title fromViewController:presenter];
}

- (void)openPath:(NSString *)path title:(NSString *)title fromViewController:(UIViewController *)presenter {
    NSArray<NSURL *> *urls = [self filzaURLsForPath:path];
    if (urls.count == 0) {
        [self showFailureForPath:path title:title fromViewController:presenter reason:@"路径格式无法转换为 URL"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self tryOpenURLs:urls index:0 path:path title:title presenter:presenter completion:^{
        [weakSelf showFailureForPath:path title:title fromViewController:presenter reason:@"设备上未安装 Filza，或 Filza 未注册 URL scheme"];
    }];
}

/// 依次尝试，不用 canOpenURL 预判，只依赖 completionHandler 返回值
- (void)tryOpenURLs:(NSArray<NSURL *> *)urls
              index:(NSUInteger)index
               path:(NSString *)path
              title:(NSString *)title
          presenter:(UIViewController *)presenter
         completion:(void (^)(void))completion {
    if (index >= urls.count) {
        if (completion) completion();
        return;
    }
    UIApplication *application = UIApplication.sharedApplication;
    NSDictionary<NSString *, id> *options = @{};
    __weak typeof(self) weakSelf = self;
    [application openURL:urls[index] options:options completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) return;
            [weakSelf tryOpenURLs:urls index:index + 1 path:path title:title presenter:presenter completion:completion];
        });
    }];
}

- (void)showFailureForPath:(NSString *)path
                     title:(NSString *)title
         fromViewController:(UIViewController *)presenter
                    reason:(NSString *)reason {
    NSString *message = [NSString stringWithFormat:@"无法打开 %@。\n\n原因：%@\n\n路径：\n%@\n\n你可以手动复制路径后到 Filza 中粘贴跳转。",
                         title, reason, path];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开文件管理器"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"复制路径"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = path;
    }];
    UIAlertAction *dismiss = [UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:copyAction];
    [alert addAction:dismiss];
    [self presentAlert:alert fromViewController:presenter];
}

- (void)copyToPasteboard:(NSString *)text hint:(NSString *)hint fromViewController:(UIViewController *)presenter {
    UIPasteboard.generalPasteboard.string = text ?: @"";
    NSString *message = hint.length > 0 ? hint : @"路径已复制到剪贴板";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已复制"
                                                                  message:[NSString stringWithFormat:@"%@\n%@", message, text]
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:alert fromViewController:presenter];
}

- (void)presentAlert:(UIAlertController *)alert fromViewController:(UIViewController *)presenter {
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = presenter.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1.0, 1.0);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark Respring

- (void)requestRespringFromViewController:(UIViewController *)presenter {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"重新载入主屏幕"
                                                                     message:@"部分改动需要重载 SpringBoard 才会生效。继续吗？"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf performRespringFromViewController:presenter];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:confirm fromViewController:presenter];
}

/// 依次尝试常见 respring URL；全部失败则只发通知并提示手动执行 sbreload
- (void)performRespringFromViewController:(UIViewController *)presenter {
    NSArray<NSString *> *candidates = @[@"sbreload://", @"sbreload://respring", @"respring://"];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *candidate in candidates) {
        NSURL *url = [NSURL URLWithString:candidate];
        if (url) [urls addObject:url];
    }
    [self tryOpenURLs:urls index:0 path:@"sbreload" title:@"Respring" presenter:presenter completion:^{
        // 兜底：只能通过 notify 通知正在运行的实例重新加载配置，真正的 respring 交给用户
        notify_post(MIAFX_NOTIFY_RELOAD);
        [[MIAFXConfig sharedConfig] publishLiveState];
        NSString *message = @"设备上没有可用的 Respring URL scheme。\n\n配置已保存并通知后台重载；若仍不生效，请在终端执行：\n\nsbreload\n\n或使用 NewTerm / SSH 手动重载 SpringBoard。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要手动 Respring"
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *copy = [UIAlertAction actionWithTitle:@"复制命令" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = @"sbreload";
        }];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:copy];
        [alert addAction:ok];
        [self presentAlert:alert fromViewController:presenter];
    }];
}

#pragma mark 系统设置

- (void)openSystemSettingsFromViewController:(UIViewController *)presenter {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    if (url) [urls addObject:url];
    [self tryOpenURLs:urls index:0 path:UIApplicationOpenSettingsURLString title:@"系统设置" presenter:presenter completion:^{
        NSString *message = @"无法打开系统设置。请手动前往「设置 → 下滑找到 MIAFX」进入。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开系统设置"
                                                                      message:message
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentAlert:alert fromViewController:presenter];
    }];
}

@end
