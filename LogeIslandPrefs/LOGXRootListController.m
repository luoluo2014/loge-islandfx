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
    LOGXStage("prefs-build-2021");   // 确认设备上跑的是哪一版
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = kLOGXColor;
    // 无分割线：insetGrouped 靠分组卡片区分层次。
    //
    // 2.0.20 起从 viewWillAppear 移到这里。原先放在 viewWillAppear 里 super 返回
    // 之后，反汇编证实窗口内只有三次 msgSend：self.tableView → self.view →
    // setSeparatorStyle:。iOS 17 上 PSListController 的 view 不保证是 UITableView，
    // 一旦 tableView 返回 nil 就回退到 view，对非 UITableView 发 setSeparatorStyle:
    // 即 unrecognized selector，未捕获异常直接闪退——stage.log 永远停在
    // prefs-vwa-super-ok 正是这个原因（此前版本先崩在 super 内的 header 创建，
    // 被 2.0.19 的 initWithSpecifier: 修掉后才第一次走到这两行）。
    //
    // viewDidLoad 的执行路径已被连续多版 stage.log 验证必然可达；且此处加
    // 类型守卫，任何异常只损失装饰效果，绝不影响页面加载。
    @try {
        UITableView *table = self.tableView;
        if (table == nil) {
            table = (UITableView *)self.view;
            LOGXStage("prefs-vdl-table-nil-useview");
        } else {
            LOGXStage("prefs-vdl-table-ok");
        }
        if ([table isKindOfClass:[UITableView class]]) {
            table.separatorStyle = UITableViewCellSeparatorStyleNone;
            LOGXStage("prefs-vdl-sep-set");
        } else {
            LOGXStage("prefs-vdl-sep-skip");
        }
    } @catch (NSException *exception) {
        LOGXStage("prefs-vdl-sep-catch");
    }
    LOGXStage("prefs-viewDidLoad-done");
}

- (void)viewWillAppear:(BOOL)animated {
    LOGXStage("prefs-viewWillAppear-enter");
    // 2.0.20：本方法只保留 super 调用，不再有任何自定义代码。
    // 自定义逻辑一律放 viewDidLoad（必然可达）或用 @try/isKindOfClass 包住。
    @try {
        [super viewWillAppear:animated];
    } @catch (NSException *exception) {
        LOGXStage("prefs-vwa-super-catch");
    }
    LOGXStage("prefs-vwa-super-ok");
    LOGXStage("prefs-viewWillAppear-done");
}

#pragma mark - 2.0.18 诊断探针：表格填充链路打点
// PSListController 自身实现这些数据源方法；加 enter/exit 打点后，stage.log 能
// 精确指出崩溃发生在：取行数 → cellForRow → 某个自定义 cell 的 init 哪一步。

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    LOGXStage("ds-rows-enter");
    NSInteger rows = [super tableView:tableView numberOfRowsInSection:section];
    // 打出行数：若 6 个 section 全返回 0，说明 PSListController 内部的 _specifiers
    // 是 nil（ivor 偏移异常），表格空白；非 0 才说明 cell 链路真的会被走到。
    char buf[64];
    snprintf(buf, sizeof(buf), "ds-rows-sec=%ld-n=%ld", (long)section, (long)rows);
    LOGXStage(buf);
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
    // 2.0.21：写入通道打点。开关/分段的 control 事件最终都汇到这里，
    // 若反馈「调不动」，这一行在不在 stage.log 里直接区分是 control 没触发，
    // 还是写入了但没生效。
    char buf[96];
    snprintf(buf, sizeof(buf), "prefs-set-enter id=%s", specifier.identifier ? specifier.identifier.UTF8String : "?");
    LOGXStage(buf);
    [super setPreferenceValue:value specifier:specifier];
    // 通知插件端立即重评（5 秒轮询之外的加速通道）
    notify_post(LOGX_NOTIFY_RELOAD);
    LOGXStage("prefs-set-exit");
}

#pragma mark - 行点击

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    LOGXStage("prefs-didSelect-enter");
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *identifier = specifier.identifier;
    if ([identifier isEqualToString:@"compactVideo"] || [identifier isEqualToString:@"expandedVideo"]) {
        LOGXStage("prefs-didSelect-video");
        NSString *modeKey = [identifier isEqualToString:@"compactVideo"] ? @"Compact.Path" : @"Expanded.Path";
        LOGXVideoPickerController *picker = [[LOGXVideoPickerController alloc] initWithModeKey:modeKey];
        [self.navigationController pushViewController:picker animated:YES];
    } else if ([identifier isEqualToString:@"logPage"]) {
        LOGXStage("prefs-didSelect-log");
        // 自己 push 而不是走 isController+detail：LOGXLogController 是
        // UITableViewController，不是 PSViewController 子类，走 detail 会被
        // PSListController 调 setSpecifier: 等私有方法而崩（2.0.19 修复）。
        LOGXLogController *logPage = [[LOGXLogController alloc] init];
        [self.navigationController pushViewController:logPage animated:YES];
    } else if (specifier->action != NULL) {
        // 覆盖了父类 didSelectRow，不转发则 PSButtonCell 的 action（注销重启）不触发。
        // 2.0.21：target 为 nil 时回退 self——Root.plist 的注销按钮没写 target，
        // 依赖 loadSpecifiersFromPlistName:target: 隐式填充；一旦没填上，旧写法的
        // specifier.target != nil 判断会直接跳过转发，表现为「注销没效果」。
        // PSSpecifier.action 是 @public ivar 不是 property，必须 -> 访问。
        id target = specifier.target ?: self;
        LOGXStage("prefs-didSelect-forward");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [target performSelector:specifier->action withObject:specifier];
#pragma clang diagnostic pop
        LOGXStage("prefs-didSelect-forward-ok");
    } else {
        LOGXStage("prefs-didSelect-noaction");
    }
}

#pragma mark - 注销重启

- (void)respringTapped:(PSSpecifier *)specifier {
    LOGXStage("prefs-respring-enter");
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"注销重启"
                                                                    message:@"将重载 SpringBoard 使改动完全生效。继续吗？"
                                                             preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        LOGXStage("prefs-respring-confirmed");
        [weakSelf performRespring];
    }]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)performRespring {
    LOGXStage("prefs-performRespring-enter");
    [self.view endEditing:YES];

    // 1) 立刻让插件停止全部渲染：黑屏恢复期间不残留任何视频帧
    notify_post(LOGX_NOTIFY_SUSPEND);

    // 2) 告知插件端「这是用户主动注销」：崩溃循环保护计数清零，
    //    避免把正常重启误判成异常循环而暂停（2.0.0 的误判源）
    LOGXPrefsSetObject(@YES, LOGX_KEY_INTENTIONAL_RESPRING);
    LOGXPrefsSynchronize();
    LOGXStage("prefs-performRespring-prefs-ok");

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
        LOGXStage(status == 0 ? "prefs-respring-killall-spawned" : "prefs-respring-killall-FAILED");
        if (status == 0) {
            int waitStatus = 0;
            waitpid(pid, &waitStatus, 0);   // killall 毫秒级返回，不会拖住 UI
            if (WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0) {
                LOGXStage("prefs-respring-killall-ok");
                return;
            }
            LOGXStage("prefs-respring-killall-nonzero");
        }
        // 备选：sbreload（RootHide 官方重启，root 环境验证可用）
        const char *args[] = {"sbreload", NULL};
        int st2 = posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args, NULL);
        LOGXStage(st2 == 0 ? "prefs-respring-sbreload-spawned" : "prefs-respring-sbreload-FAILED");
    });
}

@end
