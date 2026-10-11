//
//  MIAFXSpectrumView.m
//  MIAFX
//
//  注册 4 路 notify state（FFT_A / FFT_B / FFT_M / FFT_T）+ 1 路 tick，
//  解包成 16 个真实频段后插值到 8-64 根，再按 5 种形态绘制。
//

#import "MIAFXSpectrumView.h"

#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <stdlib.h>

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXIPC.h"
#import "MIAFXLog.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"
#import "MIAFXSpectrumResample.h"

/* 用枚举而不是 static const：后者在 C 里不是常量表达式，会让数组退化成 VLA。 */
enum { kMIAFXSpectrumRealBands = 16 };
static const NSUInteger kMIAFXSpectrumMaxBars = 64;

static CGFloat MIAFXSpectrumClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

@interface MIAFXSpectrumView ()
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) float level;
@property (nonatomic, readwrite) float peakLevel;
@property (nonatomic, readwrite) BOOL receivingFrames;
@property (nonatomic, readwrite) NSInteger form;
@property (nonatomic, readwrite) NSInteger barCount;

@property (nonatomic, strong) CAShapeLayer *mainLayer;
@property (nonatomic, strong) CAShapeLayer *bloomLayer;

@property (nonatomic) int tokenA;
@property (nonatomic) int tokenB;
@property (nonatomic) int tokenM;
@property (nonatomic) int tokenT;
@property (nonatomic) int tokenTick;

@property (nonatomic) BOOL enabled;
@property (nonatomic) CGFloat scaleValue;
@property (nonatomic) CGFloat radius;
@property (nonatomic) CGFloat length;
@property (nonatomic) CGFloat thickness;
@property (nonatomic) CGFloat sensitivity;
@property (nonatomic) CGFloat smoothing;
@property (nonatomic) CGFloat bpmLink;
@property (nonatomic) CGFloat rotation;
@property (nonatomic) BOOL rainbow;
@property (nonatomic) CGFloat bloom;

@property (nonatomic, assign) float *samples;
@property (nonatomic, assign) float *history;
@property (nonatomic) NSUInteger sampleCapacity;
@property (nonatomic) NSTimeInterval lastFrameStamp;
@property (nonatomic) CGRect cachedBounds;
@end

@implementation MIAFXSpectrumView {
    uint8_t _bands[kMIAFXSpectrumRealBands];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) {
        return nil;
    }
    [self commonInit];
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = NO;

    _tokenA = -1;
    _tokenB = -1;
    _tokenM = -1;
    _tokenT = -1;
    _tokenTick = -1;
    _sampleCapacity = 0;
    _samples = NULL;
    _history = NULL;
    _lastFrameStamp = 0.0;
    _cachedBounds = self.bounds;

    CAShapeLayer *bloom = [CAShapeLayer layer];
    bloom.fillColor = [UIColor clearColor].CGColor;
    bloom.strokeColor = [UIColor whiteColor].CGColor;
    bloom.lineCap = kCALineCapRound;
    bloom.opacity = 0.0;
    [self.layer addSublayer:bloom];
    self.bloomLayer = bloom;

    CAShapeLayer *main = [CAShapeLayer layer];
    main.fillColor = [UIColor clearColor].CGColor;
    main.strokeColor = [UIColor whiteColor].CGColor;
    main.lineCap = kCALineCapRound;
    main.opacity = 1.0;
    [self.layer addSublayer:main];
    self.mainLayer = main;

    [self reloadConfiguration];
}

- (void)dealloc {
    [self unregisterNotifications];
    if (_samples) {
        free(_samples);
        _samples = NULL;
    }
    if (_history) {
        free(_history);
        _history = NULL;
    }
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"SpectrumView", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        self.enabled = [config boolForKey:@"Spectrum.Enabled"];
        self.form = (NSInteger)MIAFXSpectrumClamp((CGFloat)[config integerForKey:@"Spectrum.Form"], 0, (CGFloat)(MIAFXSpectrumFormCount - 1));
        self.barCount = (NSInteger)MIAFXSpectrumClamp((CGFloat)[config integerForKey:@"Spectrum.Bars"], 8, (CGFloat)kMIAFXSpectrumMaxBars);
        self.scaleValue = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Scale"], 0.1, 8.0);
        self.radius = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Radius"], 1.0, 500.0);
        self.length = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Length"], 1.0, 500.0);
        self.thickness = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Thickness"], 0.2, 60.0);
        self.sensitivity = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Sensitivity"], 0.05, 4.0);
        self.smoothing = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Smoothing"], 0.0, 0.98);
        self.bpmLink = [config doubleForKey:@"Spectrum.BPMLink"];
        self.rotation = [config doubleForKey:@"Spectrum.Rotation"];
        self.rainbow = [config boolForKey:@"Spectrum.Rainbow"];
        self.bloom = MIAFXSpectrumClamp([config doubleForKey:@"Spectrum.Bloom"], 0.0, 2.0);

        [self ensureSampleCapacity:(NSUInteger)self.barCount];
        self.hidden = !self.enabled;
    });
}

- (void)ensureSampleCapacity:(NSUInteger)count {
    if (count == 0 || count <= self.sampleCapacity) {
        return;
    }
    float *samples = (float *)calloc(count, sizeof(float));
    float *history = (float *)calloc(count, sizeof(float));
    if (!samples || !history) {
        free(samples);
        free(history);
        return;
    }
    if (self.samples) {
        memcpy(samples, self.samples, sizeof(float) * self.sampleCapacity);
        free(self.samples);
    }
    if (self.history) {
        memcpy(history, self.history, sizeof(float) * self.sampleCapacity);
        free(self.history);
    }
    self.samples = samples;
    self.history = history;
    self.sampleCapacity = count;
}

#pragma mark - Notify

- (void)setRunning:(BOOL)running {
    if (self.running == running) {
        return;
    }
    _running = running;
    if (running) {
        [self registerNotifications];
    } else {
        [self unregisterNotifications];
        self.mainLayer.path = NULL;
        self.bloomLayer.path = NULL;
        self.bloomLayer.opacity = 0.0;
    }
}

- (void)registerNotifications {
    if (notify_register_check(MIAFX_NOTIFY_FFT_A, &_tokenA) != NOTIFY_STATUS_OK) {
        self.tokenA = -1;
    }
    if (notify_register_check(MIAFX_NOTIFY_FFT_B, &_tokenB) != NOTIFY_STATUS_OK) {
        self.tokenB = -1;
    }
    if (notify_register_check(MIAFX_NOTIFY_FFT_M, &_tokenM) != NOTIFY_STATUS_OK) {
        self.tokenM = -1;
    }
    if (notify_register_check(MIAFX_NOTIFY_FFT_T, &_tokenT) != NOTIFY_STATUS_OK) {
        self.tokenT = -1;
    }

    if (self.tokenTick >= 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    if (notify_register_dispatch(MIAFX_NOTIFY_FFT_TICK, &_tokenTick, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [weakSelf pullFrame];
    }) != NOTIFY_STATUS_OK) {
        self.tokenTick = -1;
    }
}

- (void)unregisterNotifications {
    if (self.tokenA >= 0) {
        notify_cancel(self.tokenA);
        self.tokenA = -1;
    }
    if (self.tokenB >= 0) {
        notify_cancel(self.tokenB);
        self.tokenB = -1;
    }
    if (self.tokenM >= 0) {
        notify_cancel(self.tokenM);
        self.tokenM = -1;
    }
    if (self.tokenT >= 0) {
        notify_cancel(self.tokenT);
        self.tokenT = -1;
    }
    if (self.tokenTick >= 0) {
        notify_cancel(self.tokenTick);
        self.tokenTick = -1;
    }
}

static BOOL MIAFXSpectrumReadState(int token, uint64_t *value) {
    if (token < 0) {
        return NO;
    }
    uint64_t raw = 0;
    if (notify_get_state(token, &raw) != NOTIFY_STATUS_OK) {
        return NO;
    }
    *value = raw;
    return YES;
}

/// 从四路 notify state 里取回一帧
- (void)pullFrame {
    uint64_t wordA = 0, wordB = 0, wordM = 0, wordT = 0;
    BOOL hasA = MIAFXSpectrumReadState(self.tokenA, &wordA);
    BOOL hasB = MIAFXSpectrumReadState(self.tokenB, &wordB);
    BOOL hasM = MIAFXSpectrumReadState(self.tokenM, &wordM);
    BOOL hasT = MIAFXSpectrumReadState(self.tokenT, &wordT);
    if (!hasA || !hasB || !hasM) {
        self.receivingFrames = NO;
        return;
    }
    (void)hasT;

    MIAFXIPCWords words;
    words.a = wordA;
    words.b = wordB;
    words.metadata = wordM;
    words.timing = wordT;

    MIAFXSpectrumFrame frame;
    if (!MIAFXIPCUnpack(&words, &frame)) {
        self.receivingFrames = NO;
        return;
    }

    memcpy(_bands, frame.bands, kMIAFXSpectrumRealBands);
    self.level = (float)frame.rms / 255.0f;
    self.peakLevel = (float)frame.peak / 255.0f;
    self.receivingFrames = YES;
}

#pragma mark - Running / Layout

- (void)layoutInBounds:(CGRect)bounds {
    MIAFXRunProtected(@"SpectrumView", ^{
        if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.size.width)) {
            return;
        }
        self.cachedBounds = bounds;
        self.frame = bounds;
        self.bounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
        CGRect layerBounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
        self.mainLayer.frame = layerBounds;
        self.bloomLayer.frame = layerBounds;
    });
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    (void)delta;
    if (!self.enabled || !self.running) {
        return;
    }
    CGFloat width = self.cachedBounds.size.width;
    CGFloat height = self.cachedBounds.size.height;
    if (width <= 0.0 || height <= 0.0) {
        return;
    }

    NSUInteger bars = (NSUInteger)MAX(self.barCount, 8);
    [self ensureSampleCapacity:bars];
    if (!self.samples) {
        return;
    }

    MIAFXSpectrumResample(_bands, self.samples, bars, self.sensitivity, self.smoothing, self.history);

    UIBezierPath *path = [UIBezierPath bezierPath];
    CGPoint center = CGPointMake(width * 0.5, height * 0.5);
    CGFloat unit = MIN(width, height) * 0.5;
    CGFloat baseRadius = self.radius * self.scaleValue * (unit / 44.0);
    CGFloat barLength = self.length * self.scaleValue * (unit / 44.0);
    CGFloat phase = (CGFloat)(timestamp * (self.bpmLink > 0.0 ? self.bpmLink / 60.0 : 0.0));
    CGFloat rotation = (CGFloat)(self.rotation * M_PI / 180.0) + phase * (CGFloat)(2.0 * M_PI);
    CGFloat lineWidth = MAX(0.2, self.thickness);

    switch (self.form) {
        case MIAFXSpectrumFormBars: {
            CGFloat slot = width / (CGFloat)bars;
            for (NSUInteger index = 0; index < bars; index++) {
                CGFloat value = self.samples[index];
                CGFloat barHeight = MAX(1.0, height * value);
                CGFloat x = slot * ((CGFloat)index + 0.5);
                [path moveToPoint:CGPointMake(x, height)];
                [path addLineToPoint:CGPointMake(x, height - barHeight)];
            }
            break;
        }
        case MIAFXSpectrumFormRingWave: {
            for (NSUInteger index = 0; index < bars; index++) {
                CGFloat value = self.samples[index];
                CGFloat angle = rotation + (CGFloat)(2.0 * M_PI * (double)index / (double)bars);
                CGFloat inner = baseRadius;
                CGFloat outer = baseRadius + barLength * value;
                [path moveToPoint:CGPointMake(center.x + cosf(angle) * inner, center.y + sinf(angle) * inner)];
                [path addLineToPoint:CGPointMake(center.x + cosf(angle) * outer, center.y + sinf(angle) * outer)];
            }
            break;
        }
        case MIAFXSpectrumFormDoubleRing: {
            for (NSUInteger index = 0; index < bars; index++) {
                CGFloat value = self.samples[index];
                CGFloat angle = rotation + (CGFloat)(2.0 * M_PI * (double)index / (double)bars);
                CGFloat inner = baseRadius;
                CGFloat outer = baseRadius + barLength * value;
                [path moveToPoint:CGPointMake(center.x + cosf(angle) * inner, center.y + sinf(angle) * inner)];
                [path addLineToPoint:CGPointMake(center.x + cosf(angle) * outer, center.y + sinf(angle) * outer)];
                CGFloat opposite = angle + (CGFloat)M_PI;
                [path moveToPoint:CGPointMake(center.x + cosf(opposite) * inner, center.y + sinf(opposite) * inner)];
                [path addLineToPoint:CGPointMake(center.x + cosf(opposite) * outer, center.y + sinf(opposite) * outer)];
            }
            break;
        }
        case MIAFXSpectrumFormPulseRing: {
            double cycle = fmod(timestamp * 0.6, 1.0);
            CGFloat pulseRadius = baseRadius + barLength * (0.35 + 0.65 * self.peakLevel) * (CGFloat)cycle;
            UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:center
                                                               radius:MAX(pulseRadius, 1.0)
                                                           startAngle:0.0
                                                             endAngle:(CGFloat)(2.0 * M_PI)
                                                            clockwise:YES];
            [path appendPath:ring];
            lineWidth = MAX(0.2, self.thickness * (1.0 - (CGFloat)cycle) * (CGFloat)(0.5 + self.level));
            break;
        }
        case MIAFXSpectrumFormRadialRays: {
            for (NSUInteger index = 0; index < bars; index++) {
                CGFloat value = self.samples[index];
                CGFloat angle = rotation + (CGFloat)(2.0 * M_PI * (double)index / (double)bars);
                CGFloat inner = baseRadius * 0.65;
                CGFloat outer = inner + barLength * (0.35 + value);
                [path moveToPoint:CGPointMake(center.x + cosf(angle) * inner, center.y + sinf(angle) * inner)];
                [path addLineToPoint:CGPointMake(center.x + cosf(angle) * outer, center.y + sinf(angle) * outer)];
            }
            break;
        }
        default:
            break;
    }

    self.mainLayer.path = path.CGPath;
    self.mainLayer.lineWidth = lineWidth;

    if (self.rainbow) {
        CGFloat hue = (CGFloat)fmod(timestamp * 0.08, 1.0);
        UIColor *color = [UIColor colorWithHue:hue saturation:0.75 brightness:1.0 alpha:1.0];
        self.mainLayer.strokeColor = color.CGColor;
    } else {
        self.mainLayer.strokeColor = [UIColor whiteColor].CGColor;
    }

    if (self.bloom > 0.0) {
        self.bloomLayer.path = path.CGPath;
        self.bloomLayer.lineWidth = MAX(0.2, self.thickness) * 2.6;
        self.bloomLayer.strokeColor = self.mainLayer.strokeColor;
        self.bloomLayer.opacity = (float)MIN(0.85, self.bloom * (0.35 + self.level));
    } else {
        self.bloomLayer.opacity = 0.0;
    }
}

@end
