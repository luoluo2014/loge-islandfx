//
//  LOGXRootListController.m
//  清爽设置主页（MagmaEvo 式 plist 驱动 + insetGrouped + 无分割线 + 品牌色）。
//

#import "LOGXBrand.h"
#import "LOGXRootListController.h"
#import "LOGXVideoPickerController.h"
#import "LOGXLogController.h"
#import "LOGXStage.h"

#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>

@interface LOGXRootListController ()
@end

@implementation LOGXRootListController

- (NSArray *)specifiers {
    LOGXStage("prefs-specifiers-enter");
    // 标准做法：直接用 PSListController 公开的 _specifiers（其内部 viewWillAppear 等
    // 直接访问这个 ivar，绕开会拿到 nil 崩溃）。_specifiers 符号在 Preferences.tbd
    // 里导出（PSListController._specifiers）。
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        char buf[64];
        snprintf(buf, sizeof(buf), "prefs-spec-count=%lu", (unsigned long)_specifiers.count);
        LOGXStage(buf);
    }
    LOGXStage("prefs-specifiers-done");
    return _specifiers;
}

- (UITableViewStyle)tableViewStyle {
    return 2;   // insetGrouped，与 MagmaEvo 一致的清爽分组卡片
}

- (void)viewDidLoad {
    LOGXStage("prefs-viewDidLoad-enter");
    LOGXStage("prefs-build-2019");   // 确认设备上跑的是哪一版
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = kLOGXColor;
    LOGXStage("prefs-viewDidLoad-done");
}

- (void)viewWillAppear:(BOOL)animated {
    LOGXStage("prefs-viewWillAppear-enter");
    // 2.0.18 诊断：@try/@catch 包住 super。若崩溃是 ObjC 异常（如 unrecognized
    // selector），这里能兜住并记录；若是 EXC_BAD_ACCESS 则打点链继续定位。
    @try {
        [super viewWillAppear:animated];
        LOGXStage("prefs-vwa-super-ok");
    } @catch (NSException *exception) {
        LOGXStage("prefs-vwa-super-catch");
    }
    // MagmaEvo 同款：无分割线，靠分组卡片区分层次
    UITableView *table = self.tableView ?: self.view;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    LOGXStage("prefs-viewWillAppear-done");
}

#pragma mark - 2.0.18 诊断探针：表格填充链路打点
// PSListController 自身实现这些数据源方法；加 enter/exit 打点后，stage.log 能
// 精确指出崩溃发生在：取行数 → cellForRow → 某个自定义 cell 的 init 哪一步。

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    LOGXStage("ds-rows-enter");
    NSInteger rows = [super tableView:tableView numberOfRowsInSection:section];
    LOGXStage("ds-rows-exit");
    return rows;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LOGXStage("ds-cell-enter");
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    LOGXStage("ds-cell-exit");
    return cell;
}

#pragma mark - 标准写入通道（开关/分段走这里）

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    // 通知插件端立即重评（5 秒轮询之外的加速通道）
    notify_post(LOGX_NOTIFY_RELOAD);
}

#pragma mark - 行点击

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *identifier = specifier.identifier;
    if ([identifier isEqualToString:@"compactVideo"] || [identifier isEqualToString:@"expandedVideo"]) {
        NSString *modeKey = [identifier isEqualToString:@"compactVideo"] ? @"Compact.Path" : @"Expanded.Path";
        LOGXVideoPickerController *picker = [[LOGXVideoPickerController alloc] initWithModeKey:modeKey];
        [self.navigationController pushViewController:picker animated:YES];
    } else if ([identifier isEqualToString:@"logPage"]) {
        // 自己 push 而不是走 isController+detail：LOGXLogController 是
        // UITableViewController，不是 PSViewController 子类，走 detail 会被
        // PSListController 调 setSpecifier: 等私有方法而崩（2.0.19 修复）。
        LOGXLogController *logPage = [[LOGXLogController alloc] init];
        [self.navigationController pushViewController:logPage animated:YES];
    } else if (specifier.target != nil && specifier.action != NULL) {
        // 本方法覆盖了 PSListController 的 didSelectRow，不手动转发的话
        // PSButtonCell 的 action（如「注销重启」）不会触发。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [specifier.target performSelector:specifier.action withObject:specifier];
#pragma clang diagnostic pop
    }
}

#pragma mark - 注销重启

- (void)respringTapped:(PSSpecifier *)specifier {
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"注销重启"
                                                                    message:@"将重载 SpringBoard 使改动完全生效。继续吗？"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf performRespring];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performRespring {
    [self.view endEditing:YES];

    // 1) 立刻让插件停止全部渲染：黑屏恢复期间不残留任何视频帧
    notify_post(LOGX_NOTIFY_SUSPEND);

    // 2) 告知插件端「这是用户主动注销」：崩溃循环保护计数清零，
    //    避免把正常重启误判成异常循环而暂停（2.0.0 的误判源）
    LOGXPrefsSetObject(@YES, LOGX_KEY_INTENTIONAL_RESPRING);
    LOGXPrefsSynchronize();

    // 3) 稍等 0.3 秒让 cfprefsd 完成代写，再执行重启；
    //    用 dispatch_after 而不是 usleep，避免阻塞 UI 线程
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        pid_t pid;
        // 主路径：killall -9 SpringBoard。launchd 立即重拉，1~2 秒恢复。
        // 不用 sbreload 打头——它在 Preferences 沙盒视图下未必存在，且其内部
        // 恢复流程在部分环境会挂起，正是「先黑屏再卡死」的成因（postinst 以
        // root 运行时无此问题，1.4.x 安装 respring 一直正常）。
        const char *killArgs[] = {"-9", "SpringBoard", NULL};
        int status = posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)killArgs, NULL);
        if (status == 0) {
            int waitStatus = 0;
            waitpid(pid, &waitStatus, 0);   // killall 毫秒级返回，不会拖住 UI
            if (WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0) return;
        }
        // 备选：sbreload（RootHide 官方重启，root 环境验证可用）
        const char *args[] = {"sbreload", NULL};
        posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args, NULL);
    });
}

@end
