//
//  MIAFXPreviewView.m
//  MIAFXPrefs
//

#import "MIAFXPreviewView.h"

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXSettingsCatalog.h"

#import <QuartzCore/QuartzCore.h>

#include <stdlib.h>

static const CGFloat kMIAFXPreviewPadding = 18.0;

@interface MIAFXPreviewView ()
@property (nonatomic, strong) UIView *capsuleView;        // 承载 breathing 变换
@property (nonatomic, strong) UIView *capsuleBox;         // 实际胶囊（用于裁剪）
@property (nonatomic, strong) CAShapeLayer *capsuleShape;
@property (nonatomic, strong) CAGradientLayer *videoLayer;
@property (nonatomic, strong) CAShapeLayer *primaryMarquee;
@property (nonatomic, strong) CAGradientLayer *primaryMarqueeGradient;
@property (nonatomic, strong) CAShapeLayer *secondaryMarquee;
@property (nonatomic, strong) CAShapeLayer *maskOverlay;
@property (nonatomic, strong) UIView *orbitHost;
@property (nonatomic, strong) UIView *metaballHost;
@property (nonatomic, strong) UIView *spectrumHost;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong, nullable) NSTimer *spectrumTimer;

@property (nonatomic, strong) NSMutableArray<CALayer *> *orbitLayers;
@property (nonatomic, strong) NSMutableArray<CALayer *> *metaballLayers;
@property (nonatomic, strong) NSMutableArray<CALayer *> *spectrumBars;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spectrumValues;

@property (nonatomic) BOOL animationsRunning;
@property (nonatomic) CGSize capsuleSize;
@end

@implementation MIAFXPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self buildHierarchy];
    return self;
}

- (instancetype)initWithCoder:(id)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    [self buildHierarchy];
    return self;
}

- (void)dealloc {
    [self.spectrumTimer invalidate];
}

#pragma mark 构建

- (void)buildHierarchy {
    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = YES;

    _orbitLayers = [NSMutableArray array];
    _metaballLayers = [NSMutableArray array];
    _spectrumBars = [NSMutableArray array];
    _spectrumValues = [NSMutableArray array];

    _capsuleView = [[UIView alloc] initWithFrame:CGRectZero];
    _capsuleView.backgroundColor = UIColor.clearColor;
    [self addSubview:_capsuleView];

    _capsuleBox = [[UIView alloc] initWithFrame:CGRectZero];
    _capsuleBox.backgroundColor = UIColor.blackColor;
    _capsuleBox.layer.cornerRadius = 18.0;
    _capsuleBox.layer.masksToBounds = YES;
    [_capsuleView addSubview:_capsuleBox];

    _capsuleShape = [CAShapeLayer layer];
    _capsuleShape.fillColor = UIColor.blackColor.CGColor;
    [_capsuleBox.layer addSublayer:_capsuleShape];

    _videoLayer = [CAGradientLayer layer];
    _videoLayer.startPoint = CGPointMake(0.0, 0.0);
    _videoLayer.endPoint = CGPointMake(1.0, 1.0);
    _videoLayer.opacity = 0.0;
    _videoLayer.masksToBounds = YES;
    [_capsuleBox.layer addSublayer:_videoLayer];

    _primaryMarqueeGradient = [CAGradientLayer layer];
    _primaryMarqueeGradient.startPoint = CGPointMake(0.0, 0.5);
    _primaryMarqueeGradient.endPoint = CGPointMake(1.0, 0.5);
    _primaryMarqueeGradient.masksToBounds = YES;
    _primaryMarqueeGradient.frame = self.bounds;

    _primaryMarquee = [CAShapeLayer layer];
    _primaryMarquee.fillColor = UIColor.clearColor.CGColor;
    _primaryMarquee.lineCap = kCALineCapRound;
    _primaryMarquee.strokeEnd = 1.0;
    _primaryMarquee.mask = _primaryMarqueeGradient;
    [self.layer addSublayer:_primaryMarquee];

    _secondaryMarquee = [CAShapeLayer layer];
    _secondaryMarquee.fillColor = UIColor.clearColor.CGColor;
    _secondaryMarquee.lineCap = kCALineCapRound;
    [self.layer addSublayer:_secondaryMarquee];

    _maskOverlay = [CAShapeLayer layer];
    _maskOverlay.opacity = 0.0;
    [_capsuleBox.layer addSublayer:_maskOverlay];

    _orbitHost = [[UIView alloc] initWithFrame:CGRectZero];
    _orbitHost.backgroundColor = UIColor.clearColor;
    _orbitHost.userInteractionEnabled = NO;
    [self addSubview:_orbitHost];

    _metaballHost = [[UIView alloc] initWithFrame:CGRectZero];
    _metaballHost.backgroundColor = UIColor.clearColor;
    _metaballHost.userInteractionEnabled = NO;
    [self addSubview:_metaballHost];

    _spectrumHost = [[UIView alloc] initWithFrame:CGRectZero];
    _spectrumHost.backgroundColor = UIColor.clearColor;
    _spectrumHost.userInteractionEnabled = NO;
    [self addSubview:_spectrumHost];

    _statusBadge = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusBadge.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
    _statusBadge.textColor = UIColor.whiteColor;
    _statusBadge.backgroundColor = UIColor.systemGreenColor;
    _statusBadge.textAlignment = NSTextAlignmentCenter;
    _statusBadge.numberOfLines = 1;
    _statusBadge.layer.cornerRadius = 9.0;
    _statusBadge.layer.masksToBounds = YES;
    [self addSubview:_statusBadge];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    _hintLabel.textColor = UIColor.secondaryLabelColor;
    _hintLabel.textAlignment = NSTextAlignmentLeft;
    _hintLabel.numberOfLines = 1;
    [self addSubview:_hintLabel];
}

#pragma mark 布局

- (void)layoutSubviews {
    [super layoutSubviews];

    CGSize size = self.bounds.size;
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    CGFloat compactWidth = (CGFloat)[config doubleForKey:@"Geometry.CompactWidth"];
    CGFloat compactHeight = (CGFloat)[config doubleForKey:@"Geometry.CompactHeight"];
    if (compactWidth < 40.0) compactWidth = 126.0;
    if (compactHeight < 12.0) compactHeight = 37.0;

    CGFloat maxBoxWidth = size.width - kMIAFXPreviewPadding * 2.0;
    CGFloat boxHeight = MIN(MAX(compactHeight, 24.0), size.height - 54.0);
    CGFloat boxWidth = MIN(compactWidth, maxBoxWidth);
    CGFloat scale = boxWidth / compactWidth;
    CGFloat scaledHeight = compactHeight * scale;
    if (scaledHeight > boxHeight) {
        scaledHeight = boxHeight;
    }
    self.capsuleSize = CGSizeMake(boxWidth, scaledHeight);

    CGRect capsuleFrame = CGRectMake((size.width - boxWidth) / 2.0,
                                     (size.height - scaledHeight) / 2.0 - 6.0,
                                     boxWidth,
                                     scaledHeight);
    self.capsuleView.frame = CGRectMake(capsuleFrame.origin.x, capsuleFrame.origin.y, boxWidth, scaledHeight);
    self.capsuleBox.frame = self.capsuleView.bounds;
    self.capsuleBox.layer.cornerRadius = [self capsuleCornerRadius];

    CGFloat corner = [self capsuleCornerRadius];
    UIBezierPath *capsulePath = [UIBezierPath bezierPathWithRoundedRect:self.capsuleBox.bounds cornerRadius:corner];
    self.capsuleShape.frame = self.capsuleBox.bounds;
    self.capsuleShape.path = capsulePath.CGPath;

    self.videoLayer.frame = self.capsuleBox.bounds;
    self.videoLayer.cornerRadius = corner;
    self.maskOverlay.frame = self.capsuleBox.bounds;
    self.maskOverlay.path = capsulePath.CGPath;

    self.orbitHost.frame = self.bounds;
    self.metaballHost.frame = self.bounds;
    self.spectrumHost.frame = self.bounds;

    CGRect marqueeFrame = CGRectInset(capsuleFrame, -6.0, -6.0);
    UIBezierPath *marqueePath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, marqueeFrame.size.width, marqueeFrame.size.height) cornerRadius:corner + 6.0];
    [CATransaction setDisableActions:YES];
    self.primaryMarquee.frame = marqueeFrame;
    self.primaryMarquee.path = marqueePath.CGPath;
    self.primaryMarqueeGradient.frame = self.primaryMarquee.bounds;
    self.secondaryMarquee.frame = marqueeFrame;
    self.secondaryMarquee.path = marqueePath.CGPath;
    [CATransaction setDisableActions:NO];

    CGSize badgeSize = [self.statusBadge sizeThatFits:CGSizeMake(size.width - kMIAFXPreviewPadding * 2.0, 18.0)];
    CGFloat badgeWidth = MIN(size.width - kMIAFXPreviewPadding * 2.0, MAX(96.0, badgeSize.width + 18.0));
    self.statusBadge.frame = CGRectMake(size.width - kMIAFXPreviewPadding - badgeWidth, kMIAFXPreviewPadding - 6.0, badgeWidth, 20.0);
    self.hintLabel.frame = CGRectMake(kMIAFXPreviewPadding, size.height - 20.0, size.width - kMIAFXPreviewPadding * 2.0, 16.0);
}

- (CGFloat)capsuleCornerRadius {
    return self.capsuleSize.height / 2.0;
}

#pragma mark 配置刷新

- (void)refresh {
    [self layoutIfNeeded];
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    BOOL master = [config boolForKey:@"Global.Enabled"];

    BOOL hasVideo = master && [config isFeatureEnabled:MIAFXFeatureVideo];
    BOOL hasMarquee = master && [config isFeatureEnabled:MIAFXFeatureMarquee];
    BOOL hasMask = master && [config isFeatureEnabled:MIAFXFeatureMask];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // 视频层
    BOOL videoEnabled = hasVideo && [config boolForKey:@"Compact.Video.Enabled"];
    self.videoLayer.opacity = (float)(videoEnabled ? [config doubleForKey:@"Compact.Video.Alpha"] : 0.0);
    NSArray *palette = [self marqueePaletteColors];
    self.videoLayer.colors = @[
        (__bridge id)[(UIColor *)palette[1] colorWithAlphaComponent:0.85].CGColor,
        (__bridge id)[(UIColor *)palette[3] colorWithAlphaComponent:0.65].CGColor
    ];

    // 遮罩
    self.maskOverlay.opacity = (float)(hasMask && [config boolForKey:@"Mask.Enabled"] ? [config doubleForKey:@"Mask.Alpha"] * 0.35 : 0.0);
    self.maskOverlay.fillColor = UIColor.systemPurpleColor.CGColor;

    // 跑马灯
    CGFloat lineWidth = (CGFloat)[config doubleForKey:@"Marquee.LineWidth"];
    self.primaryMarquee.lineWidth = MAX(0.4, lineWidth);
    self.primaryMarquee.hidden = !(hasMarquee && [config boolForKey:@"Marquee.Enabled"]);
    self.primaryMarquee.opacity = (float)MIN(1.0, [config doubleForKey:@"Marquee.Strength"]);
    self.primaryMarqueeGradient.colors = @[
        (__bridge id)((UIColor *)palette[0]).CGColor,
        (__bridge id)((UIColor *)palette[2]).CGColor,
        (__bridge id)((UIColor *)palette[4]).CGColor
    ];
    self.secondaryMarquee.hidden = self.primaryMarquee.hidden || ![config boolForKey:@"Marquee.SecondaryEnabled"];
    self.secondaryMarquee.lineWidth = MAX(0.3, lineWidth * 0.6);
    self.secondaryMarquee.strokeColor = ((UIColor *)palette[3]).CGColor;
    self.secondaryMarquee.opacity = (float)(MIN(1.0, [config doubleForKey:@"Marquee.Strength"]) * 0.55);
    self.secondaryMarquee.lineDashPattern = @[@6.0, @10.0];

    [CATransaction commit];

    [self rebuildOrbitLayers];
    [self rebuildMetaballLayers];
    [self rebuildSpectrumBars];
    [self updateStatusBadge];
    [self restartAnimations];
    [self scheduleSpectrumTimer];
    [self setNeedsLayout];
}

- (NSArray<UIColor *> *)marqueePaletteColors {
    NSInteger index = [[MIAFXConfig sharedConfig] integerForKey:@"Marquee.Palette"];
    switch (index) {
        case 1: return @[UIColor.systemPinkColor, UIColor.systemPurpleColor, UIColor.systemIndigoColor, UIColor.systemBlueColor, UIColor.systemPurpleColor];
        case 2: return @[UIColor.systemOrangeColor, UIColor.systemRedColor, UIColor.systemPinkColor, UIColor.systemOrangeColor, UIColor.systemYellowColor];
        case 3: return @[UIColor.systemTealColor, UIColor.systemGreenColor, UIColor.cyanColor, UIColor.systemTealColor, UIColor.systemGreenColor];
        case 4: return @[UIColor.systemRedColor, UIColor.systemOrangeColor, UIColor.systemGreenColor, UIColor.systemBlueColor, UIColor.systemPurpleColor];
        default: return @[UIColor.cyanColor, UIColor.systemBlueColor, UIColor.systemTealColor, UIColor.whiteColor, UIColor.systemBlueColor];
    }
}

#pragma mark 子图层构建

- (void)rebuildOrbitLayers {
    for (CALayer *layer in self.orbitLayers) [layer removeFromSuperlayer];
    [self.orbitLayers removeAllObjects];

    if (![[MIAFXConfig sharedConfig] boolForKey:@"Orbit.Enabled"]) return;
    if (!([[MIAFXConfig sharedConfig] isFeatureEnabled:MIAFXFeatureOrbit])) return;

    NSInteger count = [[MIAFXConfig sharedConfig] integerForKey:@"Orbit.Count"];
    count = MAX(1, MIN(count, 12));   // 预览里限制绘制数量，真实渲染仍按配置
    CGFloat particleSize = 5.0 * (CGFloat)[[MIAFXConfig sharedConfig] doubleForKey:@"Orbit.Scale"];
    if (particleSize < 2.0) particleSize = 2.0;
    for (NSInteger i = 0; i < count; i += 1) {
        CAShapeLayer *dot = [CAShapeLayer layer];
        dot.frame = CGRectMake(0.0, 0.0, particleSize, particleSize);
        dot.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.0, 0.0, particleSize, particleSize)].CGPath;
        UIColor *palette = [self marqueePaletteColors][(NSUInteger)(i % 5)];
        dot.fillColor = palette.CGColor;
        dot.opacity = (float)[[MIAFXConfig sharedConfig] doubleForKey:@"Orbit.Alpha"];
        [self.orbitHost.layer addSublayer:dot];
        [self.orbitLayers addObject:dot];
    }
}

- (void)rebuildMetaballLayers {
    for (CALayer *layer in self.metaballLayers) [layer removeFromSuperlayer];
    [self.metaballLayers removeAllObjects];

    if (![[MIAFXConfig sharedConfig] boolForKey:@"Metaball.Enabled"]) return;
    if (!([[MIAFXConfig sharedConfig] isFeatureEnabled:MIAFXFeatureMetaball])) return;

    NSInteger count = MIN([[MIAFXConfig sharedConfig] integerForKey:@"Metaball.Count"], 8);
    CGFloat size = (CGFloat)[[MIAFXConfig sharedConfig] doubleForKey:@"Metaball.Size"];
    size = MAX(4.0, MIN(size, self.bounds.size.height * 0.5));
    BOOL rainbow = [[MIAFXConfig sharedConfig] boolForKey:@"Metaball.Rainbow"];
    for (NSInteger i = 0; i < count; i += 1) {
        CAShapeLayer *ball = [CAShapeLayer layer];
        ball.frame = CGRectMake(0.0, 0.0, size, size);
        ball.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0.0, 0.0, size, size)].CGPath;
        UIColor *color = rainbow ? [self marqueePaletteColors][(NSUInteger)(i % 5)] : UIColor.systemBlueColor;
        ball.fillColor = [color colorWithAlphaComponent:0.55].CGColor;
        [self.metaballHost.layer addSublayer:ball];
        [self.metaballLayers addObject:ball];
    }
}

- (void)rebuildSpectrumBars {
    for (CALayer *layer in self.spectrumBars) [layer removeFromSuperlayer];
    [self.spectrumBars removeAllObjects];
    [self.spectrumValues removeAllObjects];

    BOOL enabled = [[MIAFXConfig sharedConfig] boolForKey:@"Spectrum.Enabled"] &&
                   [[MIAFXConfig sharedConfig] isFeatureEnabled:MIAFXFeatureSpectrum];
    if (!enabled) return;

    NSInteger bars = MIN([[MIAFXConfig sharedConfig] integerForKey:@"Spectrum.Bars"], 24);
    for (NSInteger i = 0; i < bars; i += 1) {
        CAShapeLayer *bar = [CAShapeLayer layer];
        bar.frame = CGRectMake(0.0, 0.0, 3.0, 2.0);
        bar.lineWidth = (CGFloat)[[MIAFXConfig sharedConfig] doubleForKey:@"Spectrum.Thickness"];
        bar.lineCap = kCALineCapRound;
        bar.fillColor = UIColor.clearColor.CGColor;
        bar.strokeColor = [self marqueePaletteColors][(NSUInteger)(i % 5)].CGColor;
        [self.spectrumHost.layer addSublayer:bar];
        [self.spectrumBars addObject:bar];
        [self.spectrumValues addObject:@0.2];
    }
}

#pragma mark 动画

- (void)startAnimating {
    self.animationsRunning = YES;
    [self refresh];
}

- (void)stopAnimating {
    self.animationsRunning = NO;
    [self.spectrumTimer invalidate];
    self.spectrumTimer = nil;
    [self.capsuleView.layer removeAllAnimations];
    [self.primaryMarquee removeAllAnimations];
    [self.secondaryMarquee removeAllAnimations];
    for (CALayer *layer in self.orbitLayers) [layer removeAllAnimations];
    for (CALayer *layer in self.metaballLayers) [layer removeAllAnimations];
}

- (void)restartAnimations {
    [self.capsuleView.layer removeAllAnimations];
    [self.primaryMarquee removeAllAnimations];
    [self.secondaryMarquee removeAllAnimations];
    for (CALayer *layer in self.orbitLayers) [layer removeAllAnimations];
    for (CALayer *layer in self.metaballLayers) [layer removeAllAnimations];
    if (!self.animationsRunning) {
        [self startAnimating];
        return;
    }

    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config boolForKey:@"Global.Enabled"]) return;

    // 呼吸
    if ([config isFeatureEnabled:MIAFXFeatureBreathing] && [config boolForKey:@"Breathing.Enabled"]) {
        double amplitude = [config doubleForKey:@"Breathing.Amplitude"];
        double period = MAX(0.2, [config doubleForKey:@"Breathing.Period"]);
        double rate = MAX(0.1, [config doubleForKey:@"Breathing.Rate"]);
        CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        breathe.fromValue = @1.0;
        breathe.toValue = @(1.0 + amplitude);
        breathe.duration = period / rate;
        breathe.autoreverses = YES;
        breathe.repeatCount = HUGE_VALF;
        breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [self.capsuleView.layer addAnimation:breathe forKey:@"miafx.breathe"];
    }

    // 跑马灯：虚线相位滚动 + 颜色流动
    if ([config isFeatureEnabled:MIAFXFeatureMarquee] && [config boolForKey:@"Marquee.Enabled"]) {
        double shiftSpeed = MAX(0.05, [config doubleForKey:@"Marquee.ShiftSpeed"]);
        double amplitude = [config doubleForKey:@"Marquee.ShiftAmplitude"];
        self.primaryMarquee.lineDashPattern = @[@(8.0 + amplitude * 0.4), @(12.0 + amplitude * 0.2)];
        CABasicAnimation *dash = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        dash.fromValue = @0.0;
        dash.toValue = @(60.0);
        dash.duration = 3.0 / shiftSpeed;
        dash.repeatCount = HUGE_VALF;
        [self.primaryMarquee addAnimation:dash forKey:@"miafx.marquee.dash"];
        CABasicAnimation *dash2 = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
        dash2.fromValue = @([config doubleForKey:@"Marquee.SecondaryPhase"] * 60.0);
        dash2.toValue = @([config doubleForKey:@"Marquee.SecondaryPhase"] * 60.0 + 60.0);
        dash2.duration = 3.0 / shiftSpeed;
        dash2.repeatCount = HUGE_VALF;
        [self.secondaryMarquee addAnimation:dash2 forKey:@"miafx.marquee.dash2"];
    }

    // 轨迹：沿椭圆路径运动
    if (self.orbitLayers.count > 0) {
        [CATransaction setDisableActions:YES];
        CGFloat rx = self.capsuleSize.width * 0.5 * (CGFloat)[config doubleForKey:@"Orbit.RadiusX"] + 10.0;
        CGFloat ry = self.capsuleSize.height * 0.5 * (CGFloat)[config doubleForKey:@"Orbit.RadiusY"] + 10.0;
        CGRect oval = CGRectMake(CGRectGetMidX(self.bounds) - rx,
                                 CGRectGetMidY(self.bounds) - 6.0 - ry,
                                 rx * 2.0, ry * 2.0);
        UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:oval];
        double speed = MAX(0.02, [config doubleForKey:@"Orbit.Speed"]);
        BOOL reverse = [config boolForKey:@"Orbit.Reverse"];
        NSUInteger count = self.orbitLayers.count;
        NSUInteger index = 0;
        for (CALayer *layer in self.orbitLayers) {
            CAKeyframeAnimation *motion = [CAKeyframeAnimation animationWithKeyPath:@"position"];
            motion.path = path.CGPath;
            motion.duration = MAX(0.4, 8.0 / speed);
            motion.repeatCount = HUGE_VALF;
            motion.calculationMode = kCAAnimationPaced;
            motion.rotationMode = kCAAnimationRotateAuto;
            CFTimeInterval offset = (CFTimeInterval)index * (motion.duration / (double)MAX(1, count));
            if (!reverse) {
                motion.beginTime = CACurrentMediaTime() + offset;
            } else {
                motion.speed = -1.0;
                motion.beginTime = CACurrentMediaTime() + motion.duration - offset;
            }
            [layer addAnimation:motion forKey:@"miafx.orbit"];
            index += 1;
        }
        [CATransaction setDisableActions:NO];
    }

    // 液滴：脉动
    NSUInteger metaballIndex = 0;
    for (CALayer *layer in self.metaballLayers) {
        CGFloat size = layer.bounds.size.width;
        CGFloat radiusX = self.capsuleSize.width * 0.5 - size * 0.5;
        CGFloat radiusY = self.capsuleSize.height * 0.5;
        double angle = (double)metaballIndex / (double)MAX(1, self.metaballLayers.count) * M_PI * 2.0;
        CGPoint anchor = CGPointMake(CGRectGetMidX(self.bounds) - 0.0 + radiusX * cos(angle),
                                     CGRectGetMidY(self.bounds) - 6.0 + radiusY * sin(angle));
        double speed = MAX(0.05, [config doubleForKey:@"Metaball.Speed"]);
        CABasicAnimation *orbit = [CABasicAnimation animationWithKeyPath:@"position"];
        orbit.fromValue = [NSValue valueWithCGPoint:anchor];
        orbit.toValue = [NSValue valueWithCGPoint:CGPointMake(anchor.x - radiusX, anchor.y)];
        orbit.duration = 4.0 / speed;
        orbit.autoreverses = YES;
        orbit.repeatCount = HUGE_VALF;
        [layer addAnimation:orbit forKey:@"miafx.metaball.move"];
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @0.75;
        pulse.toValue = @(1.0 + [config doubleForKey:@"Metaball.Deformation"] * 0.3);
        pulse.duration = 2.0 / speed;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [layer addAnimation:pulse forKey:@"miafx.metaball.pulse"];
        metaballIndex += 1;
    }
}

#pragma mark 频谱模拟

- (void)scheduleSpectrumTimer {
    [self.spectrumTimer invalidate];
    self.spectrumTimer = nil;
    if (self.spectrumBars.count == 0) {
        [CATransaction setDisableActions:YES];
        for (CAShapeLayer *bar in self.spectrumBars) bar.opacity = 0.0;
        [CATransaction setDisableActions:NO];
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.spectrumTimer = [NSTimer scheduledTimerWithTimeInterval:0.09 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf tickSpectrum];
    }];
}

- (void)tickSpectrum {
    NSUInteger count = self.spectrumBars.count;
    if (count == 0) return;
    double smoothing = [[MIAFXConfig sharedConfig] doubleForKey:@"Spectrum.Smoothing"];
    if (smoothing > 0.95) smoothing = 0.95;
    CGFloat width = self.bounds.size.width - kMIAFXPreviewPadding * 2.0;
    CGFloat step = width / (CGFloat)count;
    CGFloat baselineY = CGRectGetMaxY(self.capsuleView.frame) + 4.0;
    CGFloat maxHeight = MAX(6.0, self.bounds.size.height - 44.0);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSUInteger index = 0;
    for (CAShapeLayer *bar in self.spectrumBars) {
        double previous = [self.spectrumValues[index] doubleValue];
        double target = 0.15 + 0.85 * (double)arc4random_uniform(1000) / 1000.0;
        double value = previous * smoothing + target * (1.0 - smoothing);
        if (value > 1.0) value = 1.0;
        if (value < 0.05) value = 0.05;
        self.spectrumValues[index] = @(value);
        CGFloat height = (CGFloat)value * maxHeight;
        CGFloat x = kMIAFXPreviewPadding + step * (CGFloat)index + step * 0.5;
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(x, baselineY)];
        [path addLineToPoint:CGPointMake(x, baselineY - height)];
        bar.frame = CGRectMake(0.0, 0.0, 4.0, 4.0);
        bar.path = path.CGPath;
        bar.opacity = 1.0;
        index += 1;
    }
    [CATransaction commit];
}

#pragma mark 状态徽章

- (void)updateStatusBadge {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    BOOL master = [config boolForKey:@"Global.Enabled"];
    NSArray<NSString *> *titles = [[MIAFXSettingsCatalog sharedCatalog] activeFeatureTitles];
    if (!master || titles.count == 0) {
        self.statusBadge.backgroundColor = master ? UIColor.systemOrangeColor : UIColor.systemGrayColor;
        self.statusBadge.text = master ? @"总开关已开启但未选特效" : @"总开关已关闭";
    } else {
        self.statusBadge.backgroundColor = UIColor.systemGreenColor;
        NSInteger tier = [config integerForKey:@"Global.PerformanceTier"];
        NSString *tierName = tier == 0 ? @"节能" : (tier == 2 ? @"华丽" : @"均衡");
        NSInteger fps = [config integerForKey:@"Global.MaxFPS"];
        self.statusBadge.text = [NSString stringWithFormat:@"运行 %lu/%lu · %@ · %ldfps",
                                 (unsigned long)titles.count, (unsigned long)9,
                                 tierName, (long)fps];
    }
    NSString *detail = [titles componentsJoinedByString:@" · "];
    self.hintLabel.text = detail.length > 0 ? [@"生效阶段：" stringByAppendingString:detail] : @"预览：在「全局」页开启总开关与分阶段开关";
}

@end
