//
//  MIAFXBreathing.m
//  MIAFX
//

#import "MIAFXBreathing.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

static double MIAFXBreathingClamp(double value, double low, double high) {
    if (!isfinite(value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

/// 标准 easeOutElastic，用于“弹性弹跳”
static double MIAFXElasticOut(double p) {
    if (p <= 0.0) {
        return 0.0;
    }
    if (p >= 1.0) {
        return 1.0;
    }
    double c4 = (2.0 * M_PI) / 3.0;
    return pow(2.0, -10.0 * p) * sin((p * 10.0 - 0.75) * c4) + 1.0;
}

/// 高斯脉冲，用于“心跳双脉冲”
static double MIAFXGaussianPulse(double p, double center, double width) {
    double d = p - center;
    return exp(-(d * d) / (2.0 * width * width));
}

@interface MIAFXBreathing ()
@property (nonatomic, weak, readwrite) UIView *targetView;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) NSInteger currentType;
@property (nonatomic, readwrite) double currentScale;
@property (nonatomic, readwrite) double currentBrightness;

@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger type;
@property (nonatomic) double amplitude;
@property (nonatomic) double period;
@property (nonatomic) double phase;
@property (nonatomic) double rate;
@property (nonatomic) BOOL muted;
@property (nonatomic) double fadeIn;
@property (nonatomic) NSTimeInterval startStamp;

@property (nonatomic, strong, nullable) CAGradientLayer *sweepLayer;
@property (nonatomic, strong, nullable) CAShapeLayer *pulseLayer;
@end

@implementation MIAFXBreathing

- (instancetype)initWithTargetView:(UIView *)targetView {
    self = [super init];
    if (!self) {
        return nil;
    }
    _targetView = targetView;
    _enabled = YES;
    _type = MIAFXBreathingTypeScale;
    _amplitude = 0.08;
    _period = 2.4;
    _phase = 0.0;
    _rate = 1.0;
    _muted = NO;
    _fadeIn = 0.35;
    _startStamp = CACurrentMediaTime();
    _currentScale = 1.0;
    _currentBrightness = 1.0;
    [self reloadConfiguration];
    return self;
}

- (void)dealloc {
    [self teardownAuxiliaryLayers];
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"Breathing", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        self.enabled = [config boolForKey:@"Breathing.Enabled"];
        self.type = MIAFXBreathingClamp((double)[config integerForKey:@"Breathing.Type"], 0.0, (double)(MIAFXBreathingTypeCount - 1));
        self.amplitude = MIAFXBreathingClamp([config doubleForKey:@"Breathing.Amplitude"], 0.0, 1.0);
        self.period = MIAFXBreathingClamp([config doubleForKey:@"Breathing.Period"], 0.05, 60.0);
        self.phase = MIAFXBreathingClamp([config doubleForKey:@"Breathing.Phase"], 0.0, 3600.0);
        self.rate = MIAFXBreathingClamp([config doubleForKey:@"Breathing.Rate"], 0.0, 20.0);
        self.muted = [config boolForKey:@"Breathing.Muted"];
        self.fadeIn = MIAFXBreathingClamp([config doubleForKey:@"Breathing.FadeIn"], 0.0, 10.0);
        self.currentType = self.type;
        [self ensureAuxiliaryLayers];
    });
}

#pragma mark - Running

- (void)setRunning:(BOOL)running {
    if (self.running == running) {
        return;
    }
    _running = running;
    if (running) {
        self.startStamp = CACurrentMediaTime();
    } else {
        [self restoreTarget];
    }
}

- (void)restoreTarget {
    UIView *target = self.targetView;
    if (!target) {
        return;
    }
    target.transform = CGAffineTransformIdentity;
    target.alpha = 1.0;
    self.currentScale = 1.0;
    self.currentBrightness = 1.0;
    self.sweepLayer.opacity = 0.0;
    self.pulseLayer.opacity = 0.0;
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    (void)delta;
    if (!self.enabled) {
        return;
    }
    UIView *target = self.targetView;
    if (!target || !self.running) {
        return;
    }

    double period = MAX(self.period, 0.05);
    double elapsed = (timestamp - self.startStamp) * self.rate + self.phase;
    double p = fmod(elapsed, period) / period;
    if (p < 0.0) {
        p += 1.0;
    }
    double theta = p * 2.0 * M_PI;
    double amplitude = self.amplitude;

    double scale = 1.0;
    double brightness = 1.0;
    double translateX = 0.0;
    double translateY = 0.0;
    double rotation = 0.0;
    double sweepOpacity = 0.0;
    double sweepCenter = 0.5;
    double pulseScale = 1.0;
    double pulseOpacity = 0.0;

    NSInteger type = self.type;
    switch (type) {
        case MIAFXBreathingTypeScale:
            // 缩放
            scale = 1.0 + amplitude * sin(theta);
            break;
        case MIAFXBreathingTypeBrightness:
            // 明暗
            brightness = 1.0 - amplitude * (0.5 - 0.5 * cos(theta));
            break;
        case MIAFXBreathingTypeScaleBrightness:
            // 缩放 + 明暗
            scale = 1.0 + amplitude * 0.6 * sin(theta);
            brightness = 1.0 - amplitude * (0.5 - 0.5 * cos(theta));
            break;
        case MIAFXBreathingTypeHeartbeat: {
            // 心跳双脉冲
            double first = MIAFXGaussianPulse(p, 0.12, 0.045);
            double second = MIAFXGaussianPulse(p, 0.32, 0.060) * 0.62;
            double pulse = first + second;
            scale = 1.0 + amplitude * 1.6 * pulse;
            brightness = 1.0 - amplitude * 0.35 * pulse;
            break;
        }
        case MIAFXBreathingTypeWaveInverse:
            // 波浪反相：缩放与明暗相位相反
            scale = 1.0 + amplitude * sin(theta);
            brightness = 1.0 - amplitude * sin(theta);
            break;
        case MIAFXBreathingTypeElastic:
            // 弹性弹跳
            scale = 1.0 + amplitude * (MIAFXElasticOut(p) - 1.0);
            break;
        case MIAFXBreathingTypeSwing:
            // 摇摆
            rotation = amplitude * 0.9 * sin(theta);
            translateX = amplitude * 18.0 * sin(theta);
            scale = 1.0 + amplitude * 0.15 * cos(theta);
            break;
        case MIAFXBreathingTypePulseDiffusion: {
            // 脉冲扩散
            pulseScale = 1.0 + p * (0.6 + amplitude * 3.0);
            pulseOpacity = (1.0 - p) * (0.25 + amplitude);
            brightness = 1.0 - amplitude * 0.12 * (1.0 - p);
            break;
        }
        case MIAFXBreathingTypeDrift:
            // 漂移
            translateX = amplitude * 26.0 * sin(theta);
            translateY = amplitude * 12.0 * sin(theta * 2.0 + M_PI_4);
            scale = 1.0 + amplitude * 0.08 * sin(theta * 1.5);
            break;
        case MIAFXBreathingTypeSweep:
            // 扫光呼吸
            sweepOpacity = 0.25 + amplitude * 1.2 * (0.5 - 0.5 * cos(theta));
            sweepCenter = 0.18 + 0.64 * (0.5 - 0.5 * cos(theta));
            brightness = 1.0 - amplitude * 0.18 * (0.5 - 0.5 * cos(theta));
            scale = 1.0 + amplitude * 0.05 * sin(theta);
            break;
        default:
            scale = 1.0 + amplitude * sin(theta);
            break;
    }

    double fade = 1.0;
    if (self.fadeIn > 0.0) {
        double sinceStart = timestamp - self.startStamp;
        fade = MIAFXBreathingClamp(sinceStart / self.fadeIn, 0.0, 1.0);
    }

    if (self.muted) {
        brightness = 1.0;
    }

    self.currentScale = scale;
    self.currentBrightness = brightness;

    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformTranslate(transform, translateX, translateY);
    transform = CGAffineTransformScale(transform, scale, scale);
    transform = CGAffineTransformRotate(transform, rotation);
    target.transform = transform;
    target.alpha = MIAFXBreathingClamp(brightness * fade, 0.0, 1.0);

    if (self.sweepLayer) {
        self.sweepLayer.opacity = (float)MIAFXBreathingClamp(sweepOpacity * fade, 0.0, 1.0);
        CGFloat band = 0.32;
        CGFloat low = MIAFXBreathingClamp(sweepCenter - band, 0.0, 1.0);
        CGFloat mid = MIAFXBreathingClamp(sweepCenter, low, 1.0);
        CGFloat high = MIAFXBreathingClamp(sweepCenter + band, mid, 1.0);
        self.sweepLayer.locations = @[@(low), @(mid), @(high)];
        self.sweepLayer.frame = target.bounds;
        self.sweepLayer.hidden = (type != MIAFXBreathingTypeSweep);
    }

    if (self.pulseLayer) {
        self.pulseLayer.hidden = (type != MIAFXBreathingTypePulseDiffusion);
        if (!self.pulseLayer.hidden) {
            CGRect bounds = target.bounds;
            self.pulseLayer.frame = bounds;
            self.pulseLayer.opacity = (float)MIAFXBreathingClamp(pulseOpacity * fade, 0.0, 1.0);
            self.pulseLayer.transform = CATransform3DMakeScale((CGFloat)pulseScale, (CGFloat)pulseScale, 1.0);
            CGFloat radius = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * 0.5;
            CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
            UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                               radius:MAX(radius, 1.0)
                                                           startAngle:0.0
                                                             endAngle:(CGFloat)(2.0 * M_PI)
                                                            clockwise:YES];
            self.pulseLayer.path = path.CGPath;
        }
    }
}

#pragma mark - Auxiliary layers

- (void)ensureAuxiliaryLayers {
    UIView *target = self.targetView;
    if (!target || self.sweepLayer) {
        return;
    }

    CAGradientLayer *sweep = [CAGradientLayer layer];
    sweep.colors = @[
        (id)[UIColor clearColor].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.85].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    sweep.startPoint = CGPointMake(0.0, 0.5);
    sweep.endPoint = CGPointMake(1.0, 0.5);
    sweep.locations = @[@0.18, @0.5, @0.82];
    sweep.opacity = 0.0;
    sweep.frame = target.bounds;
    sweep.hidden = YES;
    [target.layer addSublayer:sweep];
    self.sweepLayer = sweep;

    CAShapeLayer *pulse = [CAShapeLayer layer];
    pulse.fillColor = [UIColor clearColor].CGColor;
    pulse.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.7].CGColor;
    pulse.lineWidth = 1.5;
    pulse.opacity = 0.0;
    pulse.frame = target.bounds;
    pulse.hidden = YES;
    [target.layer addSublayer:pulse];
    self.pulseLayer = pulse;
}

- (void)teardownAuxiliaryLayers {
    [self.sweepLayer removeFromSuperlayer];
    self.sweepLayer = nil;
    [self.pulseLayer removeFromSuperlayer];
    self.pulseLayer = nil;
}

@end
