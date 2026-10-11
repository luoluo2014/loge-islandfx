//
//  MIAFXOrbitFX.h
//  MIAFX
//
//  环绕轨道特效：1-12 个元素沿椭圆 / 圆 / 扩散轨道运动，
//  内置 19 个程序化矢量图形（不依赖任何图片资源）。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 轨迹形态
typedef NS_ENUM(NSUInteger, MIAFXOrbitShape) {
    MIAFXOrbitShapeEllipse = 0,
    MIAFXOrbitShapeCircle,
    MIAFXOrbitShapeExpand,
    MIAFXOrbitShapeCount
};

/// 19 个程序化矢量图形
typedef NS_ENUM(NSUInteger, MIAFXOrbitAsset) {
    MIAFXOrbitAssetStar = 0,
    MIAFXOrbitAssetHeart,
    MIAFXOrbitAssetDiamond,
    MIAFXOrbitAssetTriangle,
    MIAFXOrbitAssetSquare,
    MIAFXOrbitAssetPentagon,
    MIAFXOrbitAssetHexagon,
    MIAFXOrbitAssetRing,
    MIAFXOrbitAssetCross,
    MIAFXOrbitAssetSparkle,
    MIAFXOrbitAssetDroplet,
    MIAFXOrbitAssetMoon,
    MIAFXOrbitAssetCloud,
    MIAFXOrbitAssetBolt,
    MIAFXOrbitAssetNote,
    MIAFXOrbitAssetDot,
    MIAFXOrbitAssetArrow,
    MIAFXOrbitAssetFlower,
    MIAFXOrbitAssetGear,
    MIAFXOrbitAssetCount // 19
};

@interface MIAFXOrbitFX : NSObject

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Orbit.Enabled / Asset / Count / Shape / Reverse / Speed / RadiusX / RadiusY /
/// ExpandRatio / Glow / Swing / Scale / Alpha
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)layoutInBounds:(CGRect)bounds;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

/// 当前生效的配置（诊断用）
@property (nonatomic, readonly) NSInteger assetCount;
@property (nonatomic, readonly) NSInteger orbitCount;

@end

NS_ASSUME_NONNULL_END
