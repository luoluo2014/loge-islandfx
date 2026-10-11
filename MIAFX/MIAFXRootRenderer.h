//
//  MIAFXRootRenderer.h
//  MIAFX
//
//  根渲染器：管理 compact / expanded 两套完整特效（视频 / 呼吸 / 流光 /
//  轨道 / 元球 / 频谱 / 节奏），接收宿主 bounds 与 expanded 状态，
//  并在配置 reload 后热更新。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Global.LayerMode
typedef NS_ENUM(NSUInteger, MIAFXLayerMode) {
    MIAFXLayerModeBackground = 0, // 全部挂在背景层（index 0）
    MIAFXLayerModeOverlay = 1,    // 全部挂在覆盖层（最上方）
    MIAFXLayerModeBoth = 2,       // 视频在背景、特效在覆盖
};

@interface MIAFXRootRenderer : NSObject

- (instancetype)initWithHostView:(UIView *)hostView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, readonly) UIView *hostView;

/// 需要插到宿主 subviews 的 index 0
@property (nonatomic, strong, readonly) UIView *backgroundView;
/// 需要插到宿主最上方
@property (nonatomic, strong, readonly) UIView *overlayView;

@property (nonatomic, readonly, getter=isAttached) BOOL attached;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// 是否因为息屏 / AOD / 岛隐藏而被挂起
@property (nonatomic, readonly, getter=isSuspended) BOOL suspended;
@property (nonatomic, readonly, getter=isExpanded) BOOL expanded;
@property (nonatomic, readonly) CGRect hostBounds;

/// 把 backgroundView / overlayView 挂到宿主上（背景 index 0、覆盖最上方）。
/// 返回 NO 表示挂载失败。
- (BOOL)attachToHost;

/// fallback 场景：两个容器分属上下两个 UIWindow。
- (BOOL)attachWithBackgroundContainer:(UIView *)backgroundContainer
                    overlayContainer:(UIView *)overlayContainer;

- (void)detach;

/// 宿主几何 / 展开状态变化
- (void)updateHostBounds:(CGRect)bounds expanded:(BOOL)expanded;

/// 配置热更新
- (void)reloadConfiguration;

- (void)start;
- (void)stop;

/// AOD / 息屏 / 岛隐藏
- (void)suspendForDisplayOff;
- (void)resumeFromDisplayOff;

/// 诊断信息
@property (nonatomic, copy, readonly) NSString *runtimeDescription;

@end

NS_ASSUME_NONNULL_END
