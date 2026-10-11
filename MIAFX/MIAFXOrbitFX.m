//
//  MIAFXOrbitFX.m
//  MIAFX
//
//  环绕轨道：19 个程序化矢量图形（全部用 UIBezierPath 现算，不依赖资源文件）。
//

#import "MIAFXOrbitFX.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPassthroughView.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

static CGFloat MIAFXOrbitClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

static UIBezierPath *MIAFXRegularPolygonPath(NSUInteger sides, CGFloat radius, CGFloat rotation) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < sides; i++) {
        CGFloat angle = rotation + (CGFloat)(2.0 * M_PI * (double)i / (double)sides);
        CGPoint point = CGPointMake(cosf(angle) * radius, sinf(angle) * radius);
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

static UIBezierPath *MIAFXStarPath(NSUInteger points, CGFloat outer, CGFloat inner, CGFloat rotation) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSUInteger total = points * 2;
    for (NSUInteger i = 0; i < total; i++) {
        CGFloat radius = (i % 2 == 0) ? outer : inner;
        CGFloat angle = rotation + (CGFloat)(M_PI * (double)i / (double)points);
        CGPoint point = CGPointMake(cosf(angle) * radius, sinf(angle) * radius);
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

/// 生成某个 asset 的形状路径。outStroked 为 YES 表示该图形应当只描边不填充。
static UIBezierPath *MIAFXOrbitAssetPath(MIAFXOrbitAsset asset, CGFloat size, BOOL *outStroked) {
    CGFloat radius = size * 0.5;
    BOOL stroked = NO;
    UIBezierPath *path = nil;

    switch (asset) {
        case MIAFXOrbitAssetStar:
            path = MIAFXStarPath(5, radius, radius * 0.44, (CGFloat)(-M_PI_2));
            break;
        case MIAFXOrbitAssetHeart: {
            path = [UIBezierPath bezierPath];
            CGFloat w = size;
            CGFloat h = size;
            [path moveToPoint:CGPointMake(0.0, h * 0.32)];
            [path addCurveToPoint:CGPointMake(-w * 0.5, -h * 0.12)
                    controlPoint1:CGPointMake(-w * 0.16, h * 0.02)
                    controlPoint2:CGPointMake(-w * 0.5, h * 0.16)];
            [path addCurveToPoint:CGPointMake(0.0, -h * 0.5)
                    controlPoint1:CGPointMake(-w * 0.5, -h * 0.34)
                    controlPoint2:CGPointMake(-w * 0.22, -h * 0.5)];
            [path addCurveToPoint:CGPointMake(w * 0.5, -h * 0.12)
                    controlPoint1:CGPointMake(w * 0.22, -h * 0.5)
                    controlPoint2:CGPointMake(w * 0.5, -h * 0.34)];
            [path addCurveToPoint:CGPointMake(0.0, h * 0.32)
                    controlPoint1:CGPointMake(w * 0.5, h * 0.16)
                    controlPoint2:CGPointMake(w * 0.16, h * 0.02)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetDiamond: {
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(0.0, -radius)];
            [path addLineToPoint:CGPointMake(radius * 0.72, 0.0)];
            [path addLineToPoint:CGPointMake(0.0, radius)];
            [path addLineToPoint:CGPointMake(-radius * 0.72, 0.0)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetTriangle:
            path = MIAFXRegularPolygonPath(3, radius, (CGFloat)(-M_PI_2));
            break;
        case MIAFXOrbitAssetSquare:
            path = [UIBezierPath bezierPathWithRect:CGRectMake(-radius * 0.82, -radius * 0.82, radius * 1.64, radius * 1.64)];
            break;
        case MIAFXOrbitAssetPentagon:
            path = MIAFXRegularPolygonPath(5, radius, (CGFloat)(-M_PI_2));
            break;
        case MIAFXOrbitAssetHexagon:
            path = MIAFXRegularPolygonPath(6, radius, (CGFloat)(-M_PI_2));
            break;
        case MIAFXOrbitAssetRing:
            path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-radius, -radius, size, size)];
            stroked = YES;
            break;
        case MIAFXOrbitAssetCross: {
            CGFloat arm = radius * 0.30;
            CGFloat len = radius;
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(-arm, -len)];
            [path addLineToPoint:CGPointMake(arm, -len)];
            [path addLineToPoint:CGPointMake(arm, -arm)];
            [path addLineToPoint:CGPointMake(len, -arm)];
            [path addLineToPoint:CGPointMake(len, arm)];
            [path addLineToPoint:CGPointMake(arm, arm)];
            [path addLineToPoint:CGPointMake(arm, len)];
            [path addLineToPoint:CGPointMake(-arm, len)];
            [path addLineToPoint:CGPointMake(-arm, arm)];
            [path addLineToPoint:CGPointMake(-len, arm)];
            [path addLineToPoint:CGPointMake(-len, -arm)];
            [path addLineToPoint:CGPointMake(-arm, -arm)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetSparkle: {
            // 四角星：四个长尖 + 四个短尖
            path = [UIBezierPath bezierPath];
            NSUInteger total = 8;
            for (NSUInteger i = 0; i < total; i++) {
                CGFloat r = (i % 2 == 0) ? radius : radius * 0.26;
                CGFloat angle = (CGFloat)(M_PI * (double)i / 4.0);
                CGPoint point = CGPointMake(cosf(angle) * r, sinf(angle) * r);
                if (i == 0) {
                    [path moveToPoint:point];
                } else {
                    [path addLineToPoint:point];
                }
            }
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetDroplet: {
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(0.0, -radius)];
            [path addCurveToPoint:CGPointMake(radius * 0.78, radius * 0.30)
                    controlPoint1:CGPointMake(radius * 0.30, -radius * 0.30)
                    controlPoint2:CGPointMake(radius * 0.78, -radius * 0.20)];
            [path addArcWithCenter:CGPointMake(0.0, radius * 0.30)
                            radius:radius * 0.78
                        startAngle:0.0
                          endAngle:(CGFloat)M_PI
                         clockwise:YES];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetMoon: {
            path = [UIBezierPath bezierPath];
            [path addArcWithCenter:CGPointZero
                            radius:radius
                        startAngle:(CGFloat)(M_PI * 0.35)
                          endAngle:(CGFloat)(M_PI * 1.65)
                         clockwise:NO];
            [path addQuadCurveToPoint:CGPointMake(cosf((CGFloat)(M_PI * 0.35)) * radius, sinf((CGFloat)(M_PI * 0.35)) * radius)
                         controlPoint:CGPointMake(-radius * 0.35, 0.0)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetCloud: {
            path = [UIBezierPath bezierPath];
            [path addArcWithCenter:CGPointMake(-radius * 0.42, radius * 0.10) radius:radius * 0.42 startAngle:(CGFloat)(M_PI * 0.65) endAngle:(CGFloat)(M_PI * 1.85) clockwise:NO];
            [path addArcWithCenter:CGPointMake(0.0, -radius * 0.16) radius:radius * 0.52 startAngle:(CGFloat)(M_PI * 1.05) endAngle:(CGFloat)(M_PI * 1.98) clockwise:NO];
            [path addArcWithCenter:CGPointMake(radius * 0.46, radius * 0.10) radius:radius * 0.40 startAngle:(CGFloat)(M_PI * 1.10) endAngle:(CGFloat)(M_PI * 0.10) clockwise:NO];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetBolt: {
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(radius * 0.18, -radius)];
            [path addLineToPoint:CGPointMake(-radius * 0.46, radius * 0.14)];
            [path addLineToPoint:CGPointMake(-radius * 0.02, radius * 0.14)];
            [path addLineToPoint:CGPointMake(-radius * 0.22, radius)];
            [path addLineToPoint:CGPointMake(radius * 0.48, -radius * 0.20)];
            [path addLineToPoint:CGPointMake(radius * 0.04, -radius * 0.20)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetNote: {
            path = [UIBezierPath bezierPath];
            CGFloat headW = radius * 0.92;
            CGFloat headH = radius * 0.62;
            CGRect head = CGRectMake(-radius * 0.52, radius * 0.06, headW, headH);
            [path addQuadCurveToPoint:CGPointMake(CGRectGetMaxX(head), CGRectGetMidY(head))
                         controlPoint:CGPointMake(CGRectGetMidX(head), CGRectGetMaxY(head) + radius * 0.16)];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(head), -radius)];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(head) - radius * 0.16, -radius)];
            [path addLineToPoint:CGPointMake(CGRectGetMaxX(head) - radius * 0.16, CGRectGetMinY(head) + radius * 0.10)];
            [path addQuadCurveToPoint:CGPointMake(CGRectGetMinX(head), CGRectGetMidY(head) - radius * 0.02)
                         controlPoint:CGPointMake(CGRectGetMidX(head) - radius * 0.10, CGRectGetMinY(head) - radius * 0.14)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetDot:
            path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-radius * 0.42, -radius * 0.42, radius * 0.84, radius * 0.84)];
            break;
        case MIAFXOrbitAssetArrow: {
            path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(0.0, -radius)];
            [path addLineToPoint:CGPointMake(radius * 0.62, 0.0)];
            [path addLineToPoint:CGPointMake(radius * 0.26, 0.0)];
            [path addLineToPoint:CGPointMake(radius * 0.26, radius)];
            [path addLineToPoint:CGPointMake(-radius * 0.26, radius)];
            [path addLineToPoint:CGPointMake(-radius * 0.26, 0.0)];
            [path addLineToPoint:CGPointMake(-radius * 0.62, 0.0)];
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetFlower: {
            path = [UIBezierPath bezierPath];
            NSUInteger petals = 6;
            CGFloat petalRadius = radius * 0.42;
            CGFloat orbit = radius * 0.50;
            for (NSUInteger i = 0; i < petals; i++) {
                CGFloat angle = (CGFloat)(2.0 * M_PI * (double)i / (double)petals);
                CGPoint center = CGPointMake(cosf(angle) * orbit, sinf(angle) * orbit);
                UIBezierPath *petal = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - petalRadius, center.y - petalRadius, petalRadius * 2.0, petalRadius * 2.0)];
                [path appendPath:petal];
            }
            UIBezierPath *core = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-radius * 0.20, -radius * 0.20, radius * 0.40, radius * 0.40)];
            [path appendPath:core];
            break;
        }
        case MIAFXOrbitAssetGear: {
            // 8 齿轮廓
            path = [UIBezierPath bezierPath];
            NSUInteger teeth = 8;
            NSUInteger total = teeth * 4;
            for (NSUInteger i = 0; i < total; i++) {
                NSUInteger phase = i % 4;
                CGFloat r;
                if (phase == 0 || phase == 3) {
                    r = radius * 0.62;
                } else {
                    r = radius;
                }
                CGFloat angle = (CGFloat)(2.0 * M_PI * (double)i / (double)total);
                CGPoint point = CGPointMake(cosf(angle) * r, sinf(angle) * r);
                if (i == 0) {
                    [path moveToPoint:point];
                } else {
                    [path addLineToPoint:point];
                }
            }
            [path closePath];
            break;
        }
        case MIAFXOrbitAssetCount:
            path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-radius, -radius, size, size)];
            break;
    }

    if (outStroked) {
        *outStroked = stroked;
    }
    return path ?: [UIBezierPath bezierPath];
}

@interface MIAFXOrbitFX ()
@property (nonatomic, strong, readwrite) UIView *contentView;
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) NSInteger assetCount;
@property (nonatomic, readwrite) NSInteger orbitCount;

@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *items;
@property (nonatomic) BOOL enabled;
@property (nonatomic) MIAFXOrbitAsset asset;
@property (nonatomic) NSInteger count;
@property (nonatomic) MIAFXOrbitShape shape;
@property (nonatomic) BOOL reverse;
@property (nonatomic) CGFloat speed;
@property (nonatomic) CGFloat radiusX;
@property (nonatomic) CGFloat radiusY;
@property (nonatomic) CGFloat expandRatio;
@property (nonatomic) CGFloat glow;
@property (nonatomic) CGFloat swing;
@property (nonatomic) CGFloat itemScale;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGRect cachedBounds;
@end

@implementation MIAFXOrbitFX

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super init];
    if (!self) {
        return nil;
    }
    _contentView = [[MIAFXPassthroughView alloc] initWithFrame:frame];
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.opaque = NO;
    _items = [NSMutableArray array];
    _cachedBounds = CGRectMake(0.0, 0.0, frame.size.width, frame.size.height);
    [self reloadConfiguration];
    return self;
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"OrbitFX", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        self.enabled = [config boolForKey:@"Orbit.Enabled"];
        self.asset = (MIAFXOrbitAsset)MIAFXOrbitClamp((CGFloat)[config integerForKey:@"Orbit.Asset"], 0, (CGFloat)(MIAFXOrbitAssetCount - 1));
        self.count = (NSInteger)MIAFXOrbitClamp((CGFloat)[config integerForKey:@"Orbit.Count"], 1, 12);
        self.shape = (MIAFXOrbitShape)MIAFXOrbitClamp((CGFloat)[config integerForKey:@"Orbit.Shape"], 0, (CGFloat)(MIAFXOrbitShapeCount - 1));
        self.reverse = [config boolForKey:@"Orbit.Reverse"];
        self.speed = MIAFXOrbitClamp([config doubleForKey:@"Orbit.Speed"], 0.0, 20.0);
        self.radiusX = MIAFXOrbitClamp([config doubleForKey:@"Orbit.RadiusX"], 0.05, 4.0);
        self.radiusY = MIAFXOrbitClamp([config doubleForKey:@"Orbit.RadiusY"], 0.05, 4.0);
        self.expandRatio = MIAFXOrbitClamp([config doubleForKey:@"Orbit.ExpandRatio"], 0.0, 2.0);
        self.glow = MIAFXOrbitClamp([config doubleForKey:@"Orbit.Glow"], 0.0, 2.0);
        self.swing = MIAFXOrbitClamp([config doubleForKey:@"Orbit.Swing"], 0.0, 1.0);
        self.itemScale = MIAFXOrbitClamp([config doubleForKey:@"Orbit.Scale"], 0.05, 4.0);
        self.alpha = MIAFXOrbitClamp([config doubleForKey:@"Orbit.Alpha"], 0.0, 1.0);

        self.assetCount = (NSInteger)MIAFXOrbitAssetCount;
        self.orbitCount = self.count;

        [self rebuildItems];
        self.contentView.hidden = !self.enabled;
        [self layoutInBounds:self.cachedBounds];
    });
}

- (void)rebuildItems {
    for (CAShapeLayer *item in self.items) {
        [item removeFromSuperlayer];
    }
    [self.items removeAllObjects];

    UIColor *tint = [MIAFXOrbitFX colorForAsset:self.asset];
    for (NSInteger index = 0; index < self.count; index++) {
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.fillColor = tint.CGColor;
        layer.strokeColor = tint.CGColor;
        layer.lineWidth = 1.2;
        layer.opacity = (float)self.alpha;
        layer.shadowColor = tint.CGColor;
        layer.shadowRadius = (CGFloat)(6.0 * self.glow);
        layer.shadowOpacity = (float)MIN(1.0, self.glow);
        layer.shadowOffset = CGSizeZero;
        [self.contentView.layer addSublayer:layer];
        [self.items addObject:layer];
    }
}

+ (UIColor *)colorForAsset:(MIAFXOrbitAsset)asset {
    CGFloat hue = (CGFloat)((double)asset / (double)MIAFXOrbitAssetCount);
    return [UIColor colorWithHue:hue saturation:0.72 brightness:1.0 alpha:1.0];
}

#pragma mark - Running

- (void)setRunning:(BOOL)running {
    if (self.running == running) {
        return;
    }
    _running = running;
    if (!running) {
        for (CAShapeLayer *item in self.items) {
            item.opacity = 0.0;
        }
    }
}

#pragma mark - Layout

- (void)layoutInBounds:(CGRect)bounds {
    MIAFXRunProtected(@"OrbitFX", ^{
        if (CGRectIsEmpty(bounds) || !isfinite((double)bounds.size.width)) {
            return;
        }
        self.cachedBounds = bounds;
        self.contentView.frame = bounds;
        self.contentView.bounds = CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height);
    });
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    (void)delta;
    if (!self.enabled || !self.running) {
        return;
    }
    CGRect bounds = self.cachedBounds;
    if (CGRectIsEmpty(bounds)) {
        return;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat baseX = bounds.size.width * 0.5 * self.radiusX;
    CGFloat baseY = bounds.size.height * 0.5 * self.radiusY;
    double direction = self.reverse ? -1.0 : 1.0;
    double angle = timestamp * (double)self.speed * 2.0 * M_PI * direction;
    CGFloat itemSize = MIN(bounds.size.width, bounds.size.height) * 0.16 * self.itemScale;
    if (itemSize < 1.0) {
        itemSize = 1.0;
    }

    UIColor *tint = [MIAFXOrbitFX colorForAsset:self.asset];
    NSUInteger index = 0;
    for (CAShapeLayer *item in self.items) {
        double offset = (2.0 * M_PI * (double)index) / (double)MAX(self.count, 1);
        double swingPhase = timestamp * (double)self.speed * 2.0 * M_PI + (double)index * 0.7;
        CGFloat swingFactor = (CGFloat)(1.0 + (double)self.swing * sin(swingPhase));
        CGFloat radians = (CGFloat)(angle + offset);
        CGPoint position = CGPointMake(center.x + cosf(radians) * baseX * swingFactor,
                                       center.y + sinf(radians) * baseY * swingFactor);

        CGFloat scale = self.itemScale;
        CGFloat opacity = self.alpha;
        if (self.shape == MIAFXOrbitShapeExpand) {
            double cycle = fmod((double)timestamp * (double)self.speed * direction + (double)index / (double)MAX(self.count, 1), 1.0);
            if (cycle < 0.0) {
                cycle += 1.0;
            }
            scale = self.itemScale * (CGFloat)(0.55 + (double)self.expandRatio * (1.0 + cycle * 3.0));
            opacity = self.alpha * (CGFloat)(1.0 - cycle);
        } else if (self.shape == MIAFXOrbitShapeCircle) {
            CGFloat uniform = MIN(baseX, baseY);
            position = CGPointMake(center.x + cosf(radians) * uniform * swingFactor,
                                   center.y + sinf(radians) * uniform * swingFactor);
        }

        BOOL stroked = NO;
        UIBezierPath *shapePath = MIAFXOrbitAssetPath(self.asset, itemSize, &stroked);
        item.path = shapePath.CGPath;
        item.bounds = CGRectMake(0.0, 0.0, itemSize, itemSize);
        item.position = position;
        item.transform = CATransform3DMakeScale(scale, scale, 1.0);
        item.opacity = (float)MAX(0.0, MIN(1.0, opacity));
        item.fillColor = stroked ? [UIColor clearColor].CGColor : tint.CGColor;
        item.strokeColor = tint.CGColor;
        index++;
    }
}

@end
