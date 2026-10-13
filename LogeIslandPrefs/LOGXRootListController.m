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
// 不用 PSListController 的 _specifiers ivar（arm64e 下该 ivar 符号不导出，
// 正常链接时 dyld 找不到会导致 bundle dlopen 失败），改用自有缓存属性。
@property (nonatomic, strong) NSArray *cachedSpecifiers;
@end

@implementation LOGXRootListController

- (NSArray *)specifiers {
    LOGXStage("prefs-specifiers-enter");
    if (!self.cachedSpecifiers) {
        self.cachedSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    LOGXStage("prefs-specifiers-done");
    return self.cachedSpecifiers;
}

- (UITableViewStyle)tableViewStyle {
    return 2;   // insetGrouped，与 MagmaEvo 一致的清爽分组卡片
}

- (void)viewDidLoad {
    LOGXStage("prefs-viewDidLoad-enter");
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = kLOGXColor;
    LOGXStage("prefs-viewDidLoad-done");
}

- (void)viewWillAppear:(BOOL)animated {
    LOGXStage("prefs-viewWillAppear-enter");
    [super viewWillAppear:animated];
    // MagmaEvo 同款：无分割线，靠分组卡片区分层次
    UITableView *table = self.tableView ?: self.view;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    // 注意：不调用 reloadSpecifierID:（它在 iOS 17.1 上会崩，stage.log 定位到
    // viewWillAppear 内崩溃）。视频行的「当前选择」刷新改由重进页面时重新加载。
    LOGXStage("prefs-viewWillAppear-done");
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
