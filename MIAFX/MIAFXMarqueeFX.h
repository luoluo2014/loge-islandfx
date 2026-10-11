//
//  MIAFXMarqueeFX.h
//  MIAFX
//
//  双层胶囊流光（跑马灯边框光），不是文字跑马灯。
//  结构：CAShapeLayer(capsule) 作为 mask + CAGradientLayer 作为流光条，
//        外加一层描边 outline。主副两层相位不同。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 5 套调色板
typedef NS_ENUM(NSUInteger, MIAFXMarqueePalette) {
    MIAFXMarqueePaletteAurora = 0,
    MIAFXMarqueePaletteSunset,
    MIAFXMarqueePaletteIce,
    MIAFXMarqueePaletteNeon,
    MIAFXMarqueePaletteMono,
    MIAFXMarqueePaletteCount
};

/// 4 种混合模式
typedef NS_ENUM(NSUInteger, MIAFXMarqueeBlendMode) {
    MIAFXMarqueeBlendModeNormal = 0,
    MIAFXMarqueeBlendModeAdd,
    MIAFXMarqueeBlendModeScreen,
    MIAFXMarqueeBlendModeOverlay,
    MIAFXMarqueeBlendModeCount
};

@interface MIAFXMarqueeFX : NSObject

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Marquee.Enabled / Palette / BlendMode / Angle / Strength / ShiftSpeed /
/// ShiftAmplitude / LineWidth / SecondaryEnabled / SecondaryPhase /
/// CornerMode / CornerRadius
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)layoutInBounds:(CGRect)bounds;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

@end

NS_ASSUME_NONNULL_END
