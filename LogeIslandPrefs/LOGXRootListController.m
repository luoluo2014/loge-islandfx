//
//  LOGXRootListController.m
//  清爽设置主页（MagmaEvo 式 plist 驱动 + insetGrouped + 无分割线 + 品牌色）。
//

#import "LOGXBrand.h"
#import "LOGXRootListController.h"
#import "LOGXVideoPickerController.h"
#import "LOGXLogController.h"

#import <notify.h>
#import <spawn.h>

@implementation LOGXRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (UITableViewStyle)tableViewStyle {
    return 2;   // insetGrouped，与 MagmaEvo 一致的清爽分组卡片
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.tintColor = kLOGXColor;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // MagmaEvo 同款：无分割线，靠分组卡片区分层次
    UITableView *table = self.tableView ?: self.view;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    // 视频行的「当前选择」可能在子页被改过，回来时刷新
    [self reloadSpecifierID:@"compactVideo" animated:NO];
    [self reloadSpecifierID:@"expandedVideo" animated:NO];
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
    pid_t pid;
    const char *args[] = {"sbreload", NULL};
    int status = posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, (char *const *)args, NULL);
    if (status != 0) {
        // 兜底：直接强杀 SpringBoard（RootHide 环境同样有效）
        const char *killArgs[] = {"-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)killArgs, NULL);
    }
}

@end
