//
//  MIAFXMetaballFX.m
//  MIAFX
//
//  元球：CAShapeLayer 画圆，两球之间用二次贝塞尔近似颈部，O(n^2) 配对。
//  球体越多帧率越低：<=4 -> 60fps，<=7 -> 45fps，其余 30fps。
//

#import "MIAFXMetaballFX.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPassthroughView.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

typedef struct {
    CGFloat x;
    CGFloat y;
    CGFloat vx;
    CGFloat vy;
    CGFloat radius;
} MIAFXMetaball;

static CGFloat MIAFXMetaballClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

@interface MIAFXMetaballFX ()
@property (nonatomic, strong, readwrite) UIView *contentView;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) double activeFPS;
@property (nonatomic, readwrite) NSInteger ballCount;

@property (nonatomic, strong) CAShapeLayer *shapeLayer;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) CAShapeLayer *highlightLayer;

@property (nonatomic, assign, nullable) MIAFXMetaball *balls;
@property (nonatomic) NSUInteger capacity;
/// 已经初始化过随机状态的球数量
@property (nonatomic) NSUInteger allocatedCount;

@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger configuredCount;
@property (nonatomic) CGFloat speed;
@property (nonatomic) CGFloat size;
@property (nonatomic) CGFloat deformation;
@property (nonatomic) CGFloat fusion;
@property (nonatomic) BOOL rainbow;
@property (nonatomic) CGFloat highlight;
@property (nonatomic) NSInteger maxFPS;
@property (nonatomic) CGRect cachedBounds;
@end

@implementation MIAFXMetaballFX

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (!self) {
        return nil;
    }
    MIAFXPassthroughView *view = [[MIAFXPassthroughView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    view.clipsToBounds = YES;
    _contentView = view;
    _cachedBounds = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
    _capacity = 0;
    _balls = NULL;
    [self buildLayers];
    [self reloadConfiguration];
    return self;
}

- (void)dealloc {
    if (_balls) {
        free(_balls);
        _balls = NULL;
    }
}

#pragma mark - Build

- (void)buildLayers {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    gradient.frame = self.contentView.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.30 green:0.70 blue:1.00 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.75 green:0.45 blue:1.00 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.35 green:1.00 blue:0.80 alpha:1.0].CGColor
    ];
    [self.contentView.layer addSublayer:gradient];
    self.gradientLayer = gradient;

    CAShapeLayer *shape = [CAShapeLayer layer];
    shape.frame = self.contentView.bounds;
    shape.fillColor = [UIColor whiteColor].CGColor;
    shape.strokeColor = [UIColor clearColor].CGColor;
    gradient.mask = shape;
    self.shapeLayer = shape;

    CAShapeLayer *highlight = [CAShapeLayer layer];
    highlight.frame = self.contentView.bounds;
    highlight.fillColor = [UIColor clearColor].CGColor;
    highlight.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    highlight.lineWidth = 1.0;
    [self.contentView.layer addSublayer:highlight];
    self.highlightLayer = highlight;
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"MetaballFX", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        self.enabled = [config boolForKey:@"Metaball.Enabled"];
        self.configuredCount = (NSInteger)MIAFXMetaballClamp((CGFloat)[config integerForKey:@"Metaball.Count"], 2, 10);
        self.speed = MIAFXMetaballClamp([config doubleForKey:@"Metaball.Speed"], 0.0, 20.0);
        self.size = MIAFXMetaballClamp([config doubleForKey:@"Metaball.Size"], 1.0, 200.0);
        self.deformation = MIAFXMetaballClamp([config doubleForKey:@"Metaball.Deformation"], 0.0, 2.0);
        self.fusion = MIAFXMetaballClamp([config doubleForKey:@"Metaball.Fusion"], 0.0, 2.0);
        self.rainbow = [config boolForKey:@"Metaball.Rainbow"];
        self.highlight = MIAFXMetaballClamp([config doubleForKey:@"Metaball.Highlight"], 0.0, 1.0);
        self.maxFPS = (NSInteger)MIAFXMetaballClamp((CGFloat)[config integerForKey:@"Global.MaxFPS"], 30, 60);

        self.ballCount = self.configuredCount;
        [self recomputeFPS];
        [self rebuildBalls];
        self.contentView.hidden = !self.enabled;
    });
}

- (void)recomputeFPS {
    NSInteger tier = 60;
    if (self.ballCount > 7) {
        tier = 30;
    } else if (self.ballCount > 4) {
        tier = 45;
    }
    NSInteger allowed[] = { 60, 45, 30 };
    NSInteger chosen = 30;
    for (NSUInteger i = 0; i < 3; i++) {
        if (allowed[i] <= self.maxFPS && allowed[i] <= tier) {
            chosen = allowed[i];
            break;
        }
    }
    self.activeFPS = (double)chosen;
}

- (void)rebuildBalls {
    NSUInteger wanted = (NSUInteger)MAX(self.ballCount, 0);
    if (wanted > self.capacity) {
        MIAFXMetaball *grown = (MIAFXMetaball *)realloc(self.balls, sizeof(MIAFXMetaball) * wanted);
        if (!grown) {
            wanted = self.capacity;
        } else {
            self.balls = grown;
            memset(self.balls + self.capacity, 0, sizeof(MIAFXMetaball) * (wanted - self.capacity));
            self.capacity = wanted;
        }
    }

    CGRect bounds = self.cachedBounds;
    if (CGRectIsEmpty(bounds)) {
        bounds = CGRectMake(0.0, 0.0, 120.0, 40.0);
    }
    CGFloat scale = MIN(bounds.size.width, bounds.size.height) / 40.0;
    if (scale <= 0.0) {
        scale = 1.0;
    }
    CGFloat baseRadius = MAX(1.0, self.size * 0.5 * scale);

    for (NSUInteger index = 0; index < wanted; index++) {
        MIAFXMetaball *ball = &self.balls[index];
        if (index >= self.allocatedCount) {
            CGFloat seed = wanted > 1 ? (CGFloat)index / (CGFloat)(wanted - 1) : 0.5f;
            ball->x = bounds.size.width * (0.2 + 0.6 * seed);
            ball->y = bounds.size.height * (0.3 + 0.4 * seed);
            CGFloat angle = (CGFloat)(2.0 * M_PI * (double)seed);
            ball->vx = cosf(angle) * self.speed * 22.0;
            ball->vy = sinf(angle) * self.speed * 12.0;
            ball->radius = baseRadius * (0.7 + 0.6 * seed);
        } else {
            ball->radius = MIN(MAX(ball->radius, baseRadius * 0.5), baseRadius * 2.0);
        }
        ball->x = MIN(MAX(ball->x, ball->radius), MAX(bounds.size.width - ball->radius, ball->radius));
        ball->y = MIN(MAX(ball->y, ball->radius), MAX(bounds.size.height - ball->radius, ball->radius));
    }

    self.allocatedCount = wanted;
}

#pragma mark - Running

- (void)setRunning:(BOOL)running {
    if (self.running == running) {
        return;
    }
    _running = running;
    if (!running) {
        self.shapeLayer.path = NULL;
        self.highlightLayer.path = NULL;
    }
}

#pragma mark - Layout

- (void)layoutInBounds:(CGRect)bounds {
    MIAFXRunProtected(@"MetaballFX", ^{
        if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.size.width)) {
            return;
        }
        self.cachedBounds = bounds;
        self.contentView.frame = bounds;
        self.contentView.bounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
        CGRect layerBounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
        self.gradientLayer.frame = layerBounds;
        self.shapeLayer.frame = layerBounds;
        self.highlightLayer.frame = layerBounds;
        [self rebuildBalls];
    });
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    if (!self.enabled || !self.running) {
        return;
    }
    CGRect bounds = self.cachedBounds;
    if (CGRectIsEmpty(bounds) || !self.balls) {
        return;
    }

    CGFloat step = (CGFloat)MIN(MAX(delta, 0.0), 0.1);
    NSUInteger count = (NSUInteger)MAX(self.ballCount, 0);

    for (NSUInteger index = 0; index < count; index++) {
        MIAFXMetaball *ball = &self.balls[index];
        ball->x += ball->vx * step;
        ball->y += ball->vy * step;
        CGFloat minimum = ball->radius;
        CGFloat maximumX = bounds.size.width - ball->radius;
        CGFloat maximumY = bounds.size.height - ball->radius;
        if (ball->x < minimum) {
            ball->x = minimum;
            ball->vx = fabs(ball->vx);
        } else if (ball->x > maximumX) {
            ball->x = maximumX > minimum ? maximumX : minimum;
            ball->vx = -fabs(ball->vx);
        }
        if (ball->y < minimum) {
            ball->y = minimum;
            ball->vy = fabs(ball->vy);
        } else if (ball->y > maximumY) {
            ball->y = maximumY > minimum ? maximumY : minimum;
            ball->vy = -fabs(ball->vy);
        }
    }

    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger index = 0; index < count; index++) {
        MIAFXMetaball *ball = &self.balls[index];
        CGRect rect = CGRectMake(ball->x - ball->radius, ball->y - ball->radius, ball->radius * 2.0, ball->radius * 2.0);
        [path appendPath:[UIBezierPath bezierPathWithOvalInRect:rect]];
    }

    // O(n^2)：所有球两两配对，距离足够近时用二次贝塞尔近似颈部
    CGFloat fusionDistance = MAX(1.0, self.size) * (0.6 + self.fusion);
    for (NSUInteger i = 0; i < count; i++) {
        MIAFXMetaball *first = &self.balls[i];
        for (NSUInteger j = i + 1; j < count; j++) {
            MIAFXMetaball *second = &self.balls[j];
            CGFloat dx = second->x - first->x;
            CGFloat dy = second->y - first->y;
            CGFloat distance = sqrtf(dx * dx + dy * dy);
            CGFloat maximum = (first->radius + second->radius) + fusionDistance;
            if (distance <= 0.001f || distance >= maximum) {
                continue;
            }
            CGFloat unitX = dx / distance;
            CGFloat unitY = dy / distance;
            CGFloat normalX = -unitY;
            CGFloat normalY = unitX;
            CGFloat ratio = 1.0 - (distance / maximum);
            CGFloat neck = ratio * self.deformation * MIN(first->radius, second->radius) * 1.10;
            CGFloat firstOffset = first->radius * 0.72 + neck * 0.22;
            CGFloat secondOffset = second->radius * 0.72 + neck * 0.22;
            CGFloat midX = (first->x + second->x) * 0.5;
            CGFloat midY = (first->y + second->y) * 0.5;

            CGPoint pointA = CGPointMake(first->x + normalX * firstOffset, first->y + normalY * firstOffset);
            CGPoint pointB = CGPointMake(second->x + normalX * secondOffset, second->y + normalY * secondOffset);
            CGPoint pointC = CGPointMake(second->x - normalX * secondOffset, second->y - normalY * secondOffset);
            CGPoint pointD = CGPointMake(first->x - normalX * firstOffset, first->y - normalY * firstOffset);
            CGPoint controlPositive = CGPointMake(midX + normalX * neck, midY + normalY * neck);
            CGPoint controlNegative = CGPointMake(midX - normalX * neck, midY - normalY * neck);

            UIBezierPath *neckPath = [UIBezierPath bezierPath];
            [neckPath moveToPoint:pointA];
            [neckPath addQuadCurveToPoint:pointB controlPoint:controlPositive];
            [neckPath addLineToPoint:pointC];
            [neckPath addQuadCurveToPoint:pointD controlPoint:controlNegative];
            [neckPath closePath];
            [path appendPath:neckPath];
        }
    }

    self.shapeLayer.path = path.CGPath;
    self.highlightLayer.path = path.CGPath;
    self.highlightLayer.opacity = (float)self.highlight;

    if (self.rainbow) {
        CGFloat shift = (CGFloat)fmod(timestamp * 0.12, 1.0);
        self.gradientLayer.colors = @[
            (id)[UIColor colorWithHue:shift saturation:0.70 brightness:1.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithHue:fmodf(shift + 0.33, 1.0) saturation:0.70 brightness:1.0 alpha:1.0].CGColor,
            (id)[UIColor colorWithHue:fmodf(shift + 0.66, 1.0) saturation:0.70 brightness:1.0 alpha:1.0].CGColor
        ];
    }
}

@end
