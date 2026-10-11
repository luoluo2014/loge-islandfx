//
//  MIAFXIslandHostBridge.h
//  MIAFX
//
//  宿主桥：延迟探测 MRUActivityNowPlayingViewController /
//  MRUActivityNowPlayingView / SAUIElementView，确认方法存在后用
//  MSHookMessageEx 安装 hook；识别宿主几何与 expanded 状态；
//  挂载失败时退回上下两个 pass-through UIWindow。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "MIAFXConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXHostKind) {
    MIAFXHostKindNone = 0,
    MIAFXHostKindMRUViewController,
    MIAFXHostKindMRUView,
    MIAFXHostKindSAUIElementView,
    MIAFXHostKindFallbackWindow
};

typedef NS_ENUM(NSUInteger, MIAFXHostEvent) {
    MIAFXHostEventViewDidLoad = 0,
    MIAFXHostEventViewWillAppear,
    MIAFXHostEventViewDidDisappear,
    MIAFXHostEventDidLayout,
    MIAFXHostEventPreferredHeight
};

@interface MIAFXIslandHostBridge : NSObject

+ (instancetype)sharedBridge;

/// 注册 _dyld_register_func_for_add_image 回调，等私有类加载后再装 hook
- (void)registerDelayedDetection;

/// dyld 每次加载镜像时调用（由 MIAFXMain.xm 的 C 回调转进来）
- (void)handleImageAdded;

/// 由各个 hook 转进来的事件
- (void)noteHostEvent:(MIAFXHostEvent)event object:(id)object;

/// 由 StateCoordinator 转进来的运行时状态
- (void)handleRuntimeState:(MIAFXRuntimeState)state;

/// 配置 reload 后的热更新
- (void)handleConfigurationReload;

/// SpringBoard 启动完成回调（由 SpringBoard hook 转入）
- (void)noteSpringBoardReady;

/// 岛是否可见（viewDidDisappear 后置 NO）
@property (nonatomic, readonly) BOOL islandVisible;

/// 诊断
@property (nonatomic, readonly) MIAFXHostKind hostKind;
@property (nonatomic, readonly, getter=isHooked) BOOL hooked;
@property (nonatomic, readonly) BOOL mountSucceeded;
@property (nonatomic, readonly) BOOL usingFallbackWindows;
@property (nonatomic, readonly) CGRect hostBounds;
@property (nonatomic, readonly, getter=isExpanded) BOOL expanded;
@property (nonatomic, copy, readonly) NSString *diagnosticsDescription;

/// 主动拆掉当前挂载（状态变化 / 卸载时调用）
- (void)unmount;

@end

NS_ASSUME_NONNULL_END
