//
//  MIAFXFilzaLauncher.h
//  MIAFXPrefs
//
//  负责把 MIAFX 的真实数据路径交给 Filza 打开，以及请求 Respring。
//  · 真实路径一律由 Shared/MIAFXPath API 解析（roothide jbroot）
//  · 先尝试 filza://view/<percent encoded>，再尝试 filza://<percent encoded>
//  · 全程不使用 canOpenURL 做前置拦截，只用 openURL 的完成回调判断是否成功
//  · 失败弹窗提供「复制路径」按钮
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXFilzaLocation) {
    MIAFXFilzaLocationVideos = 0,
    MIAFXFilzaLocationMasks,
    MIAFXFilzaLocationCustomOrbits,
    MIAFXFilzaLocationPresets,
    MIAFXFilzaLocationLogs,
    MIAFXFilzaLocationConfiguration
};

@interface MIAFXFilzaLauncher : NSObject

+ (instancetype)sharedLauncher;

#pragma mark 路径

- (NSString *)dataDirectory;
/// 真实 Videos 目录（/var/jb 前缀，Filza / root 视角）——插件端唯一可读的位置
- (NSString *)videosDirectory;
/// 设置 App 沙盒容器内的旧版 Videos 目录（仅用于迁移历史导入，不再作为投放目标）
- (NSString *)legacyContainerVideosDirectory;
- (NSString *)masksDirectory;
- (NSString *)customOrbitsDirectory;
- (NSString *)presetsDirectory;
- (NSString *)logsDirectory;
- (NSString *)configurationFilePath;
- (NSString *)settingsFilePath;
- (NSString *)diagnosticsFilePath;
- (NSString *)panicFilePath;
- (NSString *)logFilePath;
/// 保证上面这些目录存在（首次进入 App 时调用）
- (BOOL)ensureDirectories;
- (NSString *)pathForLocation:(MIAFXFilzaLocation)location;
- (NSString *)displayNameForLocation:(MIAFXFilzaLocation)location;

#pragma mark 打开

/// 在 Filza 中打开指定路径
- (void)openPath:(NSString *)path title:(NSString *)title fromViewController:(UIViewController *)presenter;
/// 在 Filza 中打开预定义位置
- (void)openLocation:(MIAFXFilzaLocation)location fromViewController:(UIViewController *)presenter;
/// 复制文本到系统剪贴板
- (void)copyToPasteboard:(NSString *)text hint:(nullable NSString *)hint fromViewController:(UIViewController *)presenter;
/// 依次尝试多个 respring URL，全部失败则提示用户手动执行
- (void)requestRespringFromViewController:(UIViewController *)presenter;
/// 打开系统「设置」中 MIAFX 的 PreferenceLoader 入口
- (void)openSystemSettingsFromViewController:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
