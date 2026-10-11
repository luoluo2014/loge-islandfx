//
//  MIAFXRootViewController.h
//  MIAFXPrefs
//
//  设置 App 主页面：顶部实时小岛预览 + 运行状态徽章，下方按「分组页面」或「搜索结果」
//  渲染设置项。所有写操作统一走 MIAFXSettingsCatalog -> MIAFXConfig(save:)。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MIAFXRootViewController : UIViewController

/// 处理 loge:// 深链（例如 loge://settings?page=orbit）
- (BOOL)handleOpenURL:(NSURL *)url;
/// 外部配置发生变化后刷新（App 回到前台 / 收到 reload 通知）
- (void)reloadAllData;

@end

NS_ASSUME_NONNULL_END
