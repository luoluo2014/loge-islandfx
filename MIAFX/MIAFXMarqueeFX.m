//
//  MIAFXMarqueeFX.m
//  MIAFX
//
//  双层胶囊流光：CAGradientLayer（流光）+ CAShapeLayer（胶囊 mask）+ 描边。
//

#import "MIAFXMarqueeFX.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPassthroughView.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

static NSArray<UIColor *> *MIAFXMarqueePaletteColors(MIAFXMarqueePalette palette) {
    switch (palette) {
        case MIAFXMarqueePaletteAurora:
            return @[
                [UIColor colorWithRed:0.20 green:0.95 blue:0.75 alpha:1.0],
                [UIColor colorWithRed:0.30 green:0.65 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.65 green:0.45 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.20 green:0.95 blue:0.75 alpha:1.0]
            ];
        case MIAFXMarqueePaletteSunset:
            return @[
                [UIColor colorWithRed:1.00 green:0.85 blue:0.35 alpha:1.0],
                [UIColor colorWithRed:1.00 green:0.45 blue:0.30 alpha:1.0],
                [UIColor colorWithRed:0.95 green:0.25 blue:0.55 alpha:1.0],
                [UIColor colorWithRed:1.00 green:0.85 blue:0.35 alpha:1.0]
            ];
        case MIAFXMarqueePaletteIce:
            return @[
                [UIColor colorWithRed:0.65 green:0.95 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.45 green:0.75 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.80 green:0.90 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.65 green:0.95 blue:1.00 alpha:1.0]
            ];
        case MIAFXMarqueePaletteNeon:
            return @[
                [UIColor colorWithRed:0.15 green:1.00 blue:0.35 alpha:1.0],
                [UIColor colorWithRed:1.00 green:0.20 blue:0.85 alpha:1.0],
                [UIColor colorWithRed:0.35 green:0.55 blue:1.00 alpha:1.0],
                [UIColor colorWithRed:0.15 green:1.00 blue:0.35 alpha:1.0]
            ];
        case MIAFXMarqueePaletteMono:
            return @[
                [UIColor colorWithWhite:1.00 alpha:1.0],
                [UIColor colorWithWhite:0.75 alpha:1.0],
                [UIColor colorWithWhite:0.55 alpha:1.0],
                [UIColor colorWithWhite:1.00 alpha:1.0]
            ];
        case MIAFXMarqueePaletteCount:
            break;
    }
    return @[ [UIColor whiteColor], [UIColor lightGrayColor], [UIColor whiteColor] ];
}

static id _Nullable MIAFXMarqueeCompositingFilter(MIAFXMarqueeBlendMode mode) {
    switch (mode) {
        case MIAFXMarqueeBlendModeNormal: return nil;
        case MIAFXMarqueeBlendModeAdd: return @"plusLBlendMode";
        case MIAFXMarqueeBlendModeScreen: return @"screenBlendMode";
        case MIAFXMarqueeBlendModeOverlay: return @"overlayBlendMode";
        case MIAFXMarqueeBlendModeCount: break;
    }
    return nil;
}

static CGFloat MIAFXMarqueeClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

@interface MIAFXMarqueeTier : NSObject
@property (nonatomic, strong) UIView *view;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) CAShapeLayer *outline;
@property (nonatomic) CGFloat phase;
@property (nonatomic) CGFloat speedScale;
@end

@implementation MIAFXMarqueeTier
@end

@interface MIAFXMarqueeFX ()
@property (nonatomic, strong, readwrite) UIView *contentView;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;

@property (nonatomic, strong) MIAFXMarqueeTier *primary;
@property (nonatomic, strong) MIAFXMarqueeTier *secondary;

@property (nonatomic) BOOL enabled;
@property (nonatomic) MIAFXMarqueePalette palette;
@property (nonatomic) MIAFXMarqueeBlendMode blendMode;
@property (nonatomic) CGFloat angle;
@property (nonatomic) CGFloat strength;
@property (nonatomic) CGFloat shiftSpeed;
@property (nonatomic) CGFloat shiftAmplitude;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic) BOOL secondaryEnabled;
@property (nonatomic) CGFloat secondaryPhase;
@property (nonatomic) NSInteger cornerMode;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) CGRect cachedBounds;
@end

@implementation MIAFXMarqueeFX

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (!self) {
        return nil;
    }
    MIAFXPassthroughView *view = [[MIAFXPassthroughView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.clipsToBounds = NO;
    _contentView = view;
    _cachedBounds = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
    [self buildTiers];
    [self reloadConfiguration];
    return self;
}

#pragma mark - Build

- (void)buildTiers {
    self.primary = [self makeTierWithPhase:0.0 speedScale:1.0];
    self.secondary = [self makeTierWithPhase:0.5 speedScale:0.72];
    self.secondary.view.alpha = 0.55;
}

- (MIAFXMarqueeTier *)makeTierWithPhase:(CGFloat)phase speedScale:(CGFloat)scale {
    MIAFXMarqueeTier *tier = [[MIAFXMarqueeTier alloc] init];
    UIView *tierView = [[MIAFXPassthroughView alloc] initWithFrame:self.contentView.bounds];
    tierView.backgroundColor = [UIColor clearColor];
    tierView.opaque = NO;
    tierView.clipsToBounds = YES;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor clearColor].CGColor,
        (id)[UIColor whiteColor].CGColor,
        (id)[UIColor clearColor].CGColor
    ];
    gradient.startPoint = CGPointMake(0.0, 0.5);
    gradient.endPoint = CGPointMake(1.0, 0.5);
    gradient.locations = @[@0.18, @0.5, @0.82];
    gradient.frame = tierView.bounds;
    gradient.opacity = 0.0;

    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = tierView.bounds;
    maskLayer.fillColor = [UIColor blackColor].CGColor;
    gradient.mask = maskLayer;

    CAShapeLayer *outline = [CAShapeLayer layer];
    outline.frame = tierView.bounds;
    outline.fillColor = [UIColor clearColor].CGColor;
    outline.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    outline.lineWidth = 2.0;

    [tierView.layer addSublayer:gradient];
    [tierView.layer addSublayer:outline];

    tier.view = tierView;
    tier.gradient = gradient;
    tier.maskLayer = maskLayer;
    tier.outline = outline;
    tier.phase = phase;
    tier.speedScale = scale;
    [self.contentView addSubview:tierView];
    return tier;
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"MarqueeFX", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        self.enabled = [config boolForKey:@"Marquee.Enabled"];
        self.palette = (MIAFXMarqueePalette)MIAFXMarqueeClamp((CGFloat)[config integerForKey:@"Marquee.Palette"], 0, (CGFloat)(MIAFXMarqueePaletteCount - 1));
        self.blendMode = (MIAFXMarqueeBlendMode)MIAFXMarqueeClamp((CGFloat)[config integerForKey:@"Marquee.BlendMode"], 0, (CGFloat)(MIAFXMarqueeBlendModeCount - 1));
        self.angle = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.Angle"], -360.0, 360.0);
        self.strength = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.Strength"], 0.0, 3.0);
        self.shiftSpeed = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.ShiftSpeed"], 0.0, 20.0);
        self.shiftAmplitude = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.ShiftAmplitude"], 0.0, 200.0);
        self.lineWidth = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.LineWidth"], 0.0, 40.0);
        self.secondaryEnabled = [config boolForKey:@"Marquee.SecondaryEnabled"];
        self.secondaryPhase = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.SecondaryPhase"], 0.0, 1.0);
        self.cornerMode = [config integerForKey:@"Marquee.CornerMode"];
        self.cornerRadius = MIAFXMarqueeClamp([config doubleForKey:@"Marquee.CornerRadius"], 0.0, 500.0);

        NSArray<UIColor *> *colors = MIAFXMarqueePaletteColors(self.palette);
        NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count + 2];
        [cgColors addObject:(id)[UIColor clearColor].CGColor];
        for (UIColor *color in colors) {
            [cgColors addObject:(id)color.CGColor];
        }
        [cgColors addObject:(id)[UIColor clearColor].CGColor];

        id filter = MIAFXMarqueeCompositingFilter(self.blendMode);

        for (MIAFXMarqueeTier *tier in @[ self.primary, self.secondary ]) {
            tier.gradient.colors = [cgColors copy];
            tier.gradient.compositingFilter = filter;
            tier.outline.lineWidth = self.lineWidth;
            tier.outline.strokeColor = [UIColor colorWithWhite:1.0 alpha:(CGFloat)(0.20 + 0.35 * self.strength)].CGColor;
            tier.view.hidden = !self.enabled;
        }
        self.secondary.phase = self.secondaryPhase;
        self.secondary.view.hidden = !self.enabled || !self.secondaryEnabled;
        self.contentView.hidden = !self.enabled;

        [self layoutInBounds:self.cachedBounds];
    });
}

- (void)setRunning:(BOOL)running {
    if (self.running == running) {
        return;
    }
    _running = running;
    if (!running) {
        self.primary.gradient.opacity = 0.0;
        self.secondary.gradient.opacity = 0.0;
        self.primary.view.transform = CGAffineTransformIdentity;
        self.secondary.view.transform = CGAffineTransformIdentity;
    }
}

#pragma mark - Layout

- (void)layoutInBounds:(CGRect)bounds {
    MIAFXRunProtected(@"MarqueeFX", ^{
        if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.size.width)) {
            return;
        }
        self.cachedBounds = bounds;
        self.contentView.frame = bounds;
        self.contentView.bounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);

        CGFloat radius = self.cornerRadius;
        if (self.cornerMode == 1) {
            radius = bounds.size.height * 0.5;
        } else if (self.cornerMode == 0) {
            radius = 0.0;
        }
        radius = MIN(radius, MIN(bounds.size.width, bounds.size.height) * 0.5);

        CGRect tierBounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
        for (MIAFXMarqueeTier *tier in @[ self.primary, self.secondary ]) {
            tier.view.frame = tierBounds;
            tier.view.bounds = tierBounds;
            tier.view.layer.cornerRadius = radius;
            tier.view.layer.masksToBounds = YES;

            UIBezierPath *capsule = [UIBezierPath bezierPathWithRoundedRect:tierBounds cornerRadius:radius];
            tier.maskLayer.frame = tierBounds;
            tier.maskLayer.path = capsule.CGPath;

            tier.gradient.frame = tierBounds;
            tier.outline.frame = tierBounds;
            tier.outline.path = capsule.CGPath;
        }
    });
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    (void)delta;
    if (!self.enabled || !self.running) {
        return;
    }

    CGFloat radians = (CGFloat)(self.angle * M_PI / 180.0);
    CGFloat dx = cosf(radians);
    CGFloat dy = sinf(radians);
    CGPoint start = CGPointMake(0.5 - dx * 0.5, 0.5 - dy * 0.5);
    CGPoint end = CGPointMake(0.5 + dx * 0.5, 0.5 + dy * 0.5);

    for (MIAFXMarqueeTier *tier in @[ self.primary, self.secondary ]) {
        if (tier.view.hidden) {
            continue;
        }
        tier.gradient.startPoint = start;
        tier.gradient.endPoint = end;

        double travel = fmod(timestamp * (double)self.shiftSpeed * 0.28 + (double)tier.phase, 1.0);
        if (travel < 0.0) {
            travel += 1.0;
        }
        CGFloat center = 0.16 + 0.68 * (CGFloat)travel;
        CGFloat band = 0.30;
        CGFloat low = MAX(0.0, center - band);
        CGFloat high = MIN(1.0, center + band);
        CGFloat mid = MIN(MAX(center, low), high);
        tier.gradient.locations = @[@(low), @(mid), @(high)];
        tier.gradient.opacity = (float)MIN(1.0, self.strength);

        // 垂直平移
        CGFloat shiftY = self.shiftAmplitude * (CGFloat)sin(timestamp * (double)self.shiftSpeed * 0.6 * M_PI + (double)tier.phase * 2.0 * M_PI);
        tier.view.transform = CGAffineTransformMakeTranslation(0.0, shiftY);
    }
}

@end
