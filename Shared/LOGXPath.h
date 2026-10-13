//
//  LOGXPath.h
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  数据目录路径。插件端（SpringBoard）jbroot() 指向真实 /var/jb；
//  设置端（沙盒）jbroot() 指向容器，不可直接读文件，只能经 CFPreferences。
//  Filza 跳转等场景需要的是「真实路径」常量。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// 插件端数据根目录（jbroot 解析后的 /var/mobile/Library/LogeIsland）
NSString *LOGXDataDirectory(void);
/// 背景视频落地目录
NSString *LOGXVideosDirectory(void);
/// 诊断日志
NSString *LOGXLogPath(void);
/// 阶段打点日志（stage.log：tweak 与设置端共用，靠最后一行定位崩溃点）
NSString *LOGXStageLogPath(void);
/// 崩溃循环保护状态文件
NSString *LOGXBootStatePath(void);
/// 真实 /var/jb 视频目录（供 Filza 打开/展示，插件端与 Filza 视角一致）
NSString *LOGXRealVideosDirectory(void);

BOOL LOGXEnsureDataDirectories(NSError **error);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
