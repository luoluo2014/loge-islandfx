//
//  MIAFXNativeElementBridge.h
//  MIAFX
//
//  原生元素桥：在宿主视图树里按“明确类名”匹配 UIView（Artwork / Cover /
//  Recording / Waveform / Track / Accessory …），找到就施加旋转 / 缩放 / 偏移，
//  找不到就不做任何改动；卸载时恢复原始 transform。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXNativeSlot) {
    MIAFXNativeSlotCompactLeft = 0,
    MIAFXNativeSlotCompactRight,
    MIAFXNativeSlotExpandedTrack,
    MIAFXNativeSlotExpandedSide,
    MIAFXNativeSlotCount
};

@interface MIAFXNativeElementBridge : NSObject

- (instancetype)initWithSlot:(MIAFXNativeSlot)slot NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) MIAFXNativeSlot slot;
@property (nonatomic, copy, readonly) NSString *configurationPrefix;

/// 最近一次匹配结果
@property (nonatomic, readonly) BOOL matched;
@property (nonatomic, copy, readonly, nullable) NSString *matchedClassName;
@property (nonatomic, readonly) NSUInteger matchCount;

/// 在 rootView 里重新匹配（找不到会清理上一次的绑定）
- (void)updateWithRootView:(UIView * _Nullable)rootView;

/// <prefix>.Enabled / Direction / Speed / Scale / FPS / OffsetX / OffsetY
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

/// 恢复所有被改过的 view 的原始 transform
- (void)restore;

@end

NS_ASSUME_NONNULL_END
