//
//  MIAFXBreathing.h
//  MIAFX
//
//  10 种呼吸效果，作用在传入的 targetView 上（只改 transform / alpha，
//  不改动 frame，避免和系统布局打架）。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXBreathingType) {
    MIAFXBreathingTypeScale = 0,           // 缩放
    MIAFXBreathingTypeBrightness,          // 明暗
    MIAFXBreathingTypeScaleBrightness,     // 缩放 + 明暗
    MIAFXBreathingTypeHeartbeat,           // 心跳双脉冲
    MIAFXBreathingTypeWaveInverse,         // 波浪反相
    MIAFXBreathingTypeElastic,             // 弹性弹跳
    MIAFXBreathingTypeSwing,               // 摇摆
    MIAFXBreathingTypePulseDiffusion,      // 脉冲扩散
    MIAFXBreathingTypeDrift,               // 漂移
    MIAFXBreathingTypeSweep,               // 扫光呼吸
    MIAFXBreathingTypeCount
};

@interface MIAFXBreathing : NSObject

- (instancetype)initWithTargetView:(UIView *)targetView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, readonly) UIView *targetView;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// 从配置重新读取：Breathing.Enabled / Type / Amplitude / Period / Phase / Rate / Muted / FadeIn
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

/// 诊断信息
@property (nonatomic, readonly) NSInteger currentType;
@property (nonatomic, readonly) double currentScale;
@property (nonatomic, readonly) double currentBrightness;

@end

NS_ASSUME_NONNULL_END
