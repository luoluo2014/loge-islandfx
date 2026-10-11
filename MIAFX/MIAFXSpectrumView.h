//
//  MIAFXSpectrumView.h
//  MIAFX
//
//  频谱：注册 4 路 notify state（FFT_A / FFT_B / FFT_M / FFT_T）+ 1 路 tick，
//  把 16 个真实频段插值到 8-64 根，支持 5 种形态与彩虹 / 泛光。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, MIAFXSpectrumForm) {
    MIAFXSpectrumFormBars = 0,
    MIAFXSpectrumFormRingWave,
    MIAFXSpectrumFormDoubleRing,
    MIAFXSpectrumFormPulseRing,
    MIAFXSpectrumFormRadialRays,
    MIAFXSpectrumFormCount
};

@interface MIAFXSpectrumView : UIView

@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// 整体音量（rms，0-1）与峰值（0-1），供 rhythm 使用
@property (nonatomic, readonly) float level;
@property (nonatomic, readonly) float peakLevel;

/// 最近一帧是否有效（音频链路是否在工作）
@property (nonatomic, readonly) BOOL receivingFrames;

/// Spectrum.Enabled / Form / Bars / Scale / Radius / Length / Thickness /
/// Sensitivity / Smoothing / BPMLink / Rotation / Rainbow / Bloom
- (void)reloadConfiguration;
- (void)setRunning:(BOOL)running;
- (void)layoutInBounds:(CGRect)bounds;
- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta;

/// 诊断用
@property (nonatomic, readonly) NSInteger form;
@property (nonatomic, readonly) NSInteger barCount;

@end

NS_ASSUME_NONNULL_END
