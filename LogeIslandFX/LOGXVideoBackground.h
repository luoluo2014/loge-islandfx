//
//  LOGXVideoBackground.h
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  灵动岛背景视频控制器（每个 _SPIslandRenderSurface 一个实例，关联对象挂载）。
//  紧凑（待机）/ 展开（长按）两个状态各自独立配置，跨状态切换时自动换片。
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LOGXVideoBackground : NSObject

/// 对所有已知 surface 触发一次重评（配置变更/hook 事件时调用）
+ (void)triggerAll:(NSString *)reason;

/// 作废配置快照缓存（设置端变更后立即生效）
+ (void)invalidateConfigCache;

/// 停止全部播放（插件暂停时调用）
+ (void)stopAll;

@end

NS_ASSUME_NONNULL_END
