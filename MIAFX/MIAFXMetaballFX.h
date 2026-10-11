//
//  MIAFXMetaballFX.h
//  MIAFX
//
//  元球：CAShapeLayer 画圆 + 两个球之间用二次贝塞尔近似颈部融合，
//  O(n^2) 配对。球体数量越多帧率越低（60 / 45 / 30 降级）。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MIAFXMetaballFX : NSObject

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Metaball.Enabled / Count / Speed / Size / Deformation / Fusion / Rainbow / Highlight
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)layoutInBounds:(CGRect)bounds;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

/// 当前实际帧率（诊断 / 降级用）
@property (nonatomic, readonly) double activeFPS;
@property (nonatomic, readonly) NSInteger ballCount;

@end

NS_ASSUME_NONNULL_END
