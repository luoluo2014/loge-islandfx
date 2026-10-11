//
//  MIAFXNativeElementBridge.m
//  MIAFX
//
//  只按“明确类名”匹配 UIView；匹配不到就什么都不做。
//  匹配到之后保存原始 transform，卸载时恢复。
//

#import "MIAFXNativeElementBridge.h"

#import <QuartzCore/QuartzCore.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXProbe.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

/// 只认这些关键字，避免误伤系统布局视图
static NSArray<NSString *> *MIAFXNativeElementKeywords(void) {
    static NSArray<NSString *> *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"Artwork",
            @"Cover",
            @"Recording",
            @"Waveform",
            @"Track",
            @"Accessory"
        ];
    });
    return keywords;
}

static NSString *MIAFXNativePrefixForSlot(MIAFXNativeSlot slot) {
    switch (slot) {
        case MIAFXNativeSlotCompactLeft: return @"Native.CompactLeft";
        case MIAFXNativeSlotCompactRight: return @"Native.CompactRight";
        case MIAFXNativeSlotExpandedTrack: return @"Native.ExpandedTrack";
        case MIAFXNativeSlotExpandedSide: return @"Native.ExpandedSide";
        case MIAFXNativeSlotCount: return @"Native.CompactLeft";
    }
    return @"Native.CompactLeft";
}

static NSString *MIAFXNativeSlotName(MIAFXNativeSlot slot) {
    switch (slot) {
        case MIAFXNativeSlotCompactLeft: return @"CompactLeft";
        case MIAFXNativeSlotCompactRight: return @"CompactRight";
        case MIAFXNativeSlotExpandedTrack: return @"ExpandedTrack";
        case MIAFXNativeSlotExpandedSide: return @"ExpandedSide";
        case MIAFXNativeSlotCount: return @"Unknown";
    }
    return @"Unknown";
}

static CGFloat MIAFXNativeClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite((double)value)) {
        return low;
    }
    return value < low ? low : (value > high ? high : value);
}

/// 递归收集所有匹配关键字的 UIView。限制深度与总数，避免在深层视图树上跑太久。
static void MIAFXCollectMatchingViews(UIView *view,
                                      NSUInteger depth,
                                      NSMutableArray<UIView *> *result) {
    if (!view || depth > 12 || result.count >= 64) {
        return;
    }
    NSString *className = NSStringFromClass(view.class);
    if (className.length > 0) {
        for (NSString *keyword in MIAFXNativeElementKeywords()) {
            if ([className rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [result addObject:view];
                break;
            }
        }
    }
    for (UIView *subview in view.subviews) {
        MIAFXCollectMatchingViews(subview, depth + 1, result);
    }
}

@interface MIAFXNativeElementBridge ()
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) MIAFXNativeSlot slot;
@property (nonatomic, copy, readwrite) NSString *configurationPrefix;
@property (nonatomic, readwrite) BOOL matched;
@property (nonatomic, copy, readwrite, nullable) NSString *matchedClassName;
@property (nonatomic, readwrite) NSUInteger matchCount;

@property (nonatomic, strong) NSMutableArray<UIView *> *boundViews;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *originalTransforms;
@property (nonatomic, weak) UIView *rootView;

@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger direction;
@property (nonatomic) CGFloat speed;
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGFloat offsetX;
@property (nonatomic) CGFloat offsetY;
@property (nonatomic) NSInteger fps;
@property (nonatomic) NSTimeInterval lastTickStamp;
@end

@implementation MIAFXNativeElementBridge

- (instancetype)initWithSlot:(MIAFXNativeSlot)slot {
    self = [super init];
    if (!self) {
        return nil;
    }
    _slot = slot;
    _configurationPrefix = MIAFXNativePrefixForSlot(slot);
    _boundViews = [NSMutableArray array];
    _originalTransforms = [NSMutableDictionary dictionary];
    _fps = 30;
    _lastTickStamp = 0.0;
    return self;
}

- (void)dealloc {
    [self restore];
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    MIAFXRunProtected(@"NativeElementBridge", ^{
        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        NSString *prefix = self.configurationPrefix;
        self.enabled = [config boolForKey:[prefix stringByAppendingString:@".Enabled"]];
        self.direction = [config integerForKey:[prefix stringByAppendingString:@".Direction"]];
        self.speed = MIAFXNativeClamp([config doubleForKey:[prefix stringByAppendingString:@".Speed"]], 0.0, 20.0);
        self.scale = MIAFXNativeClamp([config doubleForKey:[prefix stringByAppendingString:@".Scale"]], 0.05, 4.0);
        self.offsetX = MIAFXNativeClamp([config doubleForKey:[prefix stringByAppendingString:@".OffsetX"]], -500.0, 500.0);
        self.offsetY = MIAFXNativeClamp([config doubleForKey:[prefix stringByAppendingString:@".OffsetY"]], -500.0, 500.0);
        self.fps = (NSInteger)MIAFXNativeClamp((CGFloat)[config integerForKey:[prefix stringByAppendingString:@".FPS"]], 15, 60);

        if (!self.enabled) {
            [self restore];
        }
    });
}

#pragma mark - Matching

- (void)updateWithRootView:(UIView * _Nullable)rootView {
    MIAFXRunProtected(@"NativeElementBridge", ^{
        if (!rootView) {
            [self restore];
            return;
        }

        NSMutableArray<UIView *> *matches = [NSMutableArray array];
        MIAFXCollectMatchingViews(rootView, 0, matches);

        if (matches.count == 0) {
            [self restore];
            self.matched = NO;
            self.matchedClassName = nil;
            self.matchCount = 0;
            [[MIAFXProbe sharedProbe] recordNativeMatchForSlot:MIAFXNativeSlotName(self.slot)
                                                       className:nil
                                                         matched:NO];
            return;
        }

        self.rootView = rootView;
        if (![self.boundViews isEqualToArray:matches]) {
            [self restore];
            [self.boundViews addObjectsFromArray:matches];
        }

        self.matched = YES;
        self.matchCount = matches.count;
        self.matchedClassName = NSStringFromClass(matches.firstObject.class);
        [[MIAFXProbe sharedProbe] recordNativeMatchForSlot:MIAFXNativeSlotName(self.slot)
                                                   className:self.matchedClassName
                                                     matched:YES];
    });
}

- (void)setRunning:(BOOL)running {
    if (_running == running) {
        return;
    }
    _running = running;
    if (!running) {
        [self restore];
    }
}

- (void)restore {
    for (UIView *view in self.boundViews) {
        NSNumber *key = @((uintptr_t)view);
        NSValue *original = (NSValue *)self.originalTransforms[key];
        if (original) {
            view.transform = original.CGAffineTransformValue;
        }
    }
    [self.originalTransforms removeAllObjects];
    [self.boundViews removeAllObjects];
    _running = NO;
}

#pragma mark - Tick

- (void)tickWithTimestamp:(NSTimeInterval)timestamp delta:(NSTimeInterval)delta {
    (void)delta;
    if (!self.enabled || !self.running || self.boundViews.count == 0) {
        return;
    }

    NSInteger frameRate = MAX(self.fps, 15);
    NSTimeInterval interval = 1.0 / (NSTimeInterval)frameRate;
    if (self.lastTickStamp > 0.0 && (timestamp - self.lastTickStamp) < interval - 0.0005) {
        return;
    }
    self.lastTickStamp = timestamp;

    double direction = (self.direction == 0) ? -1.0 : 1.0;
    CGFloat radians = (CGFloat)(timestamp * (double)self.speed * direction * 2.0 * M_PI);

    for (UIView *view in self.boundViews) {
        NSNumber *key = @((uintptr_t)view);
        if (!self.originalTransforms[key]) {
            self.originalTransforms[key] = [NSValue valueWithCGAffineTransform:view.transform];
        }
        NSValue *stored = (NSValue *)self.originalTransforms[key];
        CGAffineTransform base = stored ? stored.CGAffineTransformValue : CGAffineTransformIdentity;

        CGAffineTransform transform = base;
        transform = CGAffineTransformTranslate(transform, self.offsetX, self.offsetY);
        transform = CGAffineTransformScale(transform, self.scale, self.scale);
        transform = CGAffineTransformRotate(transform, radians);
        view.transform = transform;
    }
}

@end
