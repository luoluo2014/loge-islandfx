//
//  MIAFXVideoBackground.xm
//  MIAFX
//
//  视频背景：在 SpringBoard 灵动岛渲染表面 _SPIslandRenderSurface 的
//  系统原生 _playerLayer（AVPlayerLayer）上播放用户选择的背景视频。
//
//  ===== 1.4.0 架构修正（依据真机诊断日志）=====
//
//  (1) 懒加载 hook：
//      真机日志显示 _SPIslandRenderSurface 在 dylib 注入时并不存在（类由更晚加载的
//      框架注册），Logos 静态 %hook 会静默失败。改为运行时安装：轮询 + dyld 镜像
//      回调 + 系统通知（SPRenderContextChangedNotif / SPNotifSuppressionChangedNotif，
//      与 DynamicFX 同源）多重触发，类出现后逐个确认方法存在再装 MSHookMessageEx。
//
//  (2) 跨进程 realms：
//      设置 App（沙盒）与 SpringBoard（系统进程）的 jbroot() 指向不同文件世界，
//      配置改走 CFPreferences app-id 域（cfprefsd 代写到真实
//      /var/mobile/Library/Preferences/com.loge.islandfx.plist）；视频文件由设置端
//      以 NSData 暂存于 CFPreferences，插件端消费后落入真实
//      /var/jb/var/mobile/Library/LogeIsland/Videos/。
//
//  (3) 挂载强化：强制 _playerLayer 可见、入层树、正确 frame/圆角，三级兜底。
//
//  诊断：全链路写入 Logs/video-diag.log（常开，512KB 轮转）+ os_log。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <mach-o/dyld.h>

#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXPath.h"
#import "MIAFXLog.h"

#if __has_include(<substrate.h>)
#import <substrate.h>
#elif __has_include(<CydiaSubstrate/CydiaSubstrate.h>)
#import <CydiaSubstrate/CydiaSubstrate.h>
#else
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);
#endif

@interface _SPIslandRenderSurface : UIView
@end
@interface SBSystemApertureContainerView : UIView
@end

/// 前向声明：hook 实现位于类定义之前，需要先看到完整接口
@interface MIAFXVideoBackground : NSObject
@property (nonatomic, weak) UIView *surface;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) AVQueuePlayer *player;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy, nullable) NSString *loadedPath;
@property (nonatomic) BOOL needsSync;
@property (nonatomic) double presentationRadius;
@property (nonatomic) CGSize presentationSize;
@property (nonatomic) NSTimeInterval lastEvaluation;
@property (nonatomic) NSTimeInterval lastLog;
+ (MIAFXVideoBackground *)backgroundForSurface:(UIView *)surface;
+ (void)consumePendingImports;
+ (void)publishAssets;
- (void)handleTrigger:(NSString *)reason;
- (void)stop;
@end

static const void *kMIAFXVideoBackgroundKey = &kMIAFXVideoBackgroundKey;
static const NSTimeInterval kMIAFXVideoEvalInterval = 0.4;   // 评估节流
static const NSTimeInterval kMIAFXVideoLogInterval = 2.0;    // 日志节流
static NSString *const kMIAFXSurfaceClassName = @"_SPIslandRenderSurface";
static NSString *const kMIAFXContainerClassName = @"SBSystemApertureContainerView";

#pragma mark - 已知 surface 弱表（容器视图遍历时补充）

static NSHashTable *_MIAFXKnownSurfaces(void) {
    static NSHashTable *table;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

#pragma mark - 运行时 hook 安装器

typedef void (*MIAFXVoidIMP)(id, SEL);
typedef void (*MIAFXBoolIMP)(id, SEL, BOOL);
typedef void (*MIAFXIdIMP)(id, SEL, id);
typedef void (*MIAFXDoubleIMP)(id, SEL, double);
typedef void (*MIAFXSizeIMP)(id, SEL, CGSize);

static IMP MIAFXOrig_surface_setRenderVisible = NULL;
static IMP MIAFXOrig_surface_displayTick = NULL;
static IMP MIAFXOrig_surface_setRadius = NULL;
static IMP MIAFXOrig_surface_setSize = NULL;
static IMP MIAFXOrig_surface_layoutSubviews = NULL;
static IMP MIAFXOrig_container_layoutSubviews = NULL;

static BOOL MIAFXInstallInstanceHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (cls == Nil || selector == NULL || replacement == NULL) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) return NO;
    if (method_getImplementation(method) == replacement) return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}

static void MIAFXVideoTriggerAll(NSString *reason) {
    for (id surface in _MIAFXKnownSurfaces()) {
        if ([surface isKindOfClass:objc_getClass(kMIAFXSurfaceClassName.UTF8String) ?: NSObject.class]) {
            [[MIAFXVideoBackground backgroundForSurface:surface] handleTrigger:reason];
        }
    }
}

#pragma mark - 替换实现

static void MIAFXHook_surface_setRenderVisible(id self, SEL _cmd, BOOL visible) {
    if (MIAFXOrig_surface_setRenderVisible != NULL) {
        ((MIAFXBoolIMP)MIAFXOrig_surface_setRenderVisible)(self, _cmd, visible);
    }
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    if (visible) {
        [background handleTrigger:@"岛显示"];
    } else {
        [background stop];
        MIAFXDiag(@"岛隐藏，视频背景停止（surface=%p）", self);
    }
}

static void MIAFXHook_surface_displayTick(id self, SEL _cmd, id tick) {
    if (MIAFXOrig_surface_displayTick != NULL) {
        ((MIAFXIdIMP)MIAFXOrig_surface_displayTick)(self, _cmd, tick);
    }
    [[MIAFXVideoBackground backgroundForSurface:self] handleTrigger:@"display_tick"];
}

static void MIAFXHook_surface_setRadius(id self, SEL _cmd, double radius) {
    if (MIAFXOrig_surface_setRadius != NULL) {
        ((MIAFXDoubleIMP)MIAFXOrig_surface_setRadius)(self, _cmd, radius);
    }
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    background.presentationRadius = radius;
    [background handleTrigger:[NSString stringWithFormat:@"radius=%.1f", radius]];
}

static void MIAFXHook_surface_setSize(id self, SEL _cmd, CGSize size) {
    if (MIAFXOrig_surface_setSize != NULL) {
        ((MIAFXSizeIMP)MIAFXOrig_surface_setSize)(self, _cmd, size);
    }
    MIAFXVideoBackground *background = [MIAFXVideoBackground backgroundForSurface:self];
    background.presentationSize = size;
    [background handleTrigger:[NSString stringWithFormat:@"size=%@@", NSStringFromCGSize(size)]];
}

static void MIAFXHook_surface_layoutSubviews(id self, SEL _cmd) {
    if (MIAFXOrig_surface_layoutSubviews != NULL) {
        ((MIAFXVoidIMP)MIAFXOrig_surface_layoutSubviews)(self, _cmd);
    }
    [[MIAFXVideoBackground backgroundForSurface:self] handleTrigger:@"surface.layout"];
}

#pragma mark - 视图树遍历

static NSMutableArray *MIAFXCollectSurfaces(UIView *view, Class surfaceClass) {
    NSMutableArray *result = [NSMutableArray array];
    if (view == NULL || surfaceClass == NULL) return result;
    if ([view isKindOfClass:surfaceClass]) {
        [result addObject:view];
        return result;
    }
    for (UIView *sub in view.subviews) {
        [result addObjectsFromArray:MIAFXCollectSurfaces(sub, surfaceClass)];
    }
    return result;
}

/// 容器视图布局：遍历视图树发现 surface 实例（类名在不同 iOS 版本可能迟注册），并触发全部
static void MIAFXHook_container_layoutSubviews(id self, SEL _cmd) {
    if (MIAFXOrig_container_layoutSubviews != NULL) {
        ((MIAFXVoidIMP)MIAFXOrig_container_layoutSubviews)(self, _cmd);
    }
    Class surfaceClass = objc_getClass(kMIAFXSurfaceClassName.UTF8String);
    if (surfaceClass == NULL) {
        static NSTimeInterval lastMissLog = 0;
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - lastMissLog > 30.0) {
            lastMissLog = now;
            MIAFXDiag(@"容器已布局，但 _SPIslandRenderSurface 类仍不存在");
        }
        return;
    }
    NSMutableArray *found = MIAFXCollectSurfaces((UIView *)self, surfaceClass);
    if (found.count > 0) {
        for (id surface in found) [_MIAFXKnownSurfaces() addObject:surface];
        MIAFXVideoTriggerAll(@"container.layout");
    }
}

static BOOL MIAFXHooksInstalled = NO;
static int MIAFXRenderContextToken = -1;
static int MIAFXSuppressionToken = -1;

static void MIAFXTryInstallHooks(BOOL logResult) {
    Class surfaceClass = objc_getClass(kMIAFXSurfaceClassName.UTF8String);
    if (surfaceClass == NULL) {
        if (logResult) MIAFXDiag(@"_SPIslandRenderSurface 类不存在，稍后重试");
        return;
    }
    BOOL any = NO;
    any |= MIAFXInstallInstanceHook(surfaceClass, @selector(_sp_set_render_visible:),
                                    (IMP)MIAFXHook_surface_setRenderVisible, &MIAFXOrig_surface_setRenderVisible);
    any |= MIAFXInstallInstanceHook(surfaceClass, @selector(_sp_display_tick:),
                                    (IMP)MIAFXHook_surface_displayTick, &MIAFXOrig_surface_displayTick);
    any |= MIAFXInstallInstanceHook(surfaceClass, @selector(setLastPresentationRadius:),
                                    (IMP)MIAFXHook_surface_setRadius, &MIAFXOrig_surface_setRadius);
    any |= MIAFXInstallInstanceHook(surfaceClass, @selector(setLastPresentationSize:),
                                    (IMP)MIAFXHook_surface_setSize, &MIAFXOrig_surface_setSize);
    any |= MIAFXInstallInstanceHook(surfaceClass, @selector(layoutSubviews),
                                    (IMP)MIAFXHook_surface_layoutSubviews, &MIAFXOrig_surface_layoutSubviews);

    Class containerClass = objc_getClass(kMIAFXContainerClassName.UTF8String);
    if (containerClass != NULL) {
        any |= MIAFXInstallInstanceHook(containerClass, @selector(layoutSubviews),
                                        (IMP)MIAFXHook_container_layoutSubviews, &MIAFXOrig_container_layoutSubviews);
    }

    if (any) {
        MIAFXHooksInstalled = YES;
        MIAFXDiag(@"运行时 hook 安装完成（%@）", NSStringFromClass(surfaceClass));
    } else if (logResult) {
        MIAFXDiag(@"类已存在但未装上新 hook（可能已安装）");
    }
}

static void MIAFXScheduleHookRetry(void) {
    static dispatch_source_t timer;
    static NSInteger attempt = 0;
    if (timer != NULL) return;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (MIAFXHooksInstalled) {
            // 装好后转为低频保活（容器类可能更晚出现）
            attempt += 1;
            if (attempt > 15) {
                dispatch_source_cancel(timer);
                timer = NULL;
                return;
            }
        }
        MIAFXTryInstallHooks(NO);
    });
    dispatch_resume(timer);
}

static void MIAFXRegisterSystemNotifications(void) {
    // 这两个通知由系统在灵动岛渲染上下文/抑制状态变化时投递（DynamicFX 同源）
    notify_register_dispatch("SPRenderContextChangedNotif", &MIAFXRenderContextToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        MIAFXTryInstallHooks(NO);
        MIAFXVideoTriggerAll(@"SPRenderContextChanged");
    });
    notify_register_dispatch("SPNotifSuppressionChangedNotif", &MIAFXSuppressionToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        MIAFXVideoTriggerAll(@"SPNotifSuppressionChanged");
    });
    // 设置端保存配置时也会投递这条：立刻消费暂存的视频，实现「导入即生效」
    static int reloadToken = -1;
    notify_register_dispatch(MIAFX_NOTIFY_RELOAD, &reloadToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [MIAFXVideoBackground consumePendingImports];
        MIAFXVideoTriggerAll(@"config.reload");
    });
    MIAFXDiag(@"已注册系统通知 SPRenderContextChangedNotif / SPNotifSuppressionChangedNotif / MIAFX_NOTIFY_RELOAD");
}

static void MIAFXDyldImageCallback(const struct mach_header *mhp, intptr_t vmaddr_slide) {
    (void)vmaddr_slide;
    // 新镜像加载后立即尝试一次（类可能随框架加载而注册）
    MIAFXTryInstallHooks(NO);
}

#pragma mark - 视频背景控制器

@implementation MIAFXVideoBackground

+ (MIAFXVideoBackground *)backgroundForSurface:(UIView *)surface {
    MIAFXVideoBackground *background = objc_getAssociatedObject(surface, kMIAFXVideoBackgroundKey);
    if (background == nil) {
        background = [[MIAFXVideoBackground alloc] init];
        objc_setAssociatedObject(surface, kMIAFXVideoBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MIAFXDiag(@"新 surface=%p class=%@", surface, NSStringFromClass([surface class]));
    }
    background.surface = surface;
    [_MIAFXKnownSurfaces() addObject:surface];
    return background;
}

#pragma mark - 诊断日志

- (void)diagNow:(NSString *)message {
    self.lastLog = [NSDate timeIntervalSinceReferenceDate];
    MIAFXDiag(@"%@", message);
}

- (void)diag:(NSString *)message {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastLog < kMIAFXVideoLogInterval) return;
    self.lastLog = now;
    MIAFXDiag(@"%@", message);
}

#pragma mark - 素材投递（CFPreferences → 真实 Videos 目录）

/// 消费设置端暂存的待导入视频，落入插件可读的真实目录，并发布素材清单
+ (void)consumePendingImports {
    // 先同步一次域，确保读到设置端刚落盘的值
    MIAFXPrefsSynchronize();
    NSArray *pending = MIAFXPrefsObject(MIAFXPrefsKeyPendingImports);
    if (![pending isKindOfClass:NSArray.class] || pending.count == 0) return;

    NSString *directory = MIAFXVideosDirectory();
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) {
        MIAFXDiag(@"创建 Videos 目录失败：%@", error.localizedDescription ?: @"未知");
        return;
    }
    BOOL changed = NO;
    for (NSString *name in pending) {
        if (![name isKindOfClass:NSString.class] || name.length == 0) continue;
        NSString *safeName = name.lastPathComponent;
        NSData *data = MIAFXPrefsObject([MIAFXPrefsKeyImportBlobPrefix stringByAppendingString:name]);
        if (![data isKindOfClass:NSData.class]) {
            MIAFXDiag(@"待导入 %@ 的数据缺失，跳过", safeName);
            continue;
        }
        NSString *destination = [directory stringByAppendingPathComponent:safeName];
        if ([data writeToFile:destination atomically:YES]) {
            changed = YES;
            MIAFXDiag(@"素材已投递到真实目录：%@（%lu KB）", safeName, (unsigned long)(data.length / 1024));
        } else {
            MIAFXDiag(@"素材写入失败：%@", destination);
        }
        MIAFXPrefsRemoveObject([MIAFXPrefsKeyImportBlobPrefix stringByAppendingString:name]);
    }
    MIAFXPrefsSetObject(@[], MIAFXPrefsKeyPendingImports);
    MIAFXPrefsSynchronize();
    if (changed) {
        [MIAFXVideoBackground publishAssets];
        notify_post(MIAFX_NOTIFY_RELOAD);
    }
}

/// 把真实 Videos 目录清单发布到 CFPreferences，供设置端展示
+ (void)publishAssets {
    NSString *directory = MIAFXVideosDirectory();
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    NSSet<NSString *> *extensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mpg", @"mpeg", @"3gp", @"avi", @"mkv", @"webm"]];
    NSMutableArray *assets = [NSMutableArray array];
    for (NSString *name in items) {
        if (![extensions containsObject:name.pathExtension.lowercaseString]) continue;
        NSString *full = [directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:nil];
        if ([attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
        [assets addObject:@{ @"name": name, @"size": @([attributes[NSFileSize] unsignedLongLongValue] / 1024) }];
    }
    [assets sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    MIAFXPrefsSetObject(assets, MIAFXPrefsKeyAssetsVideos);
    MIAFXPrefsSynchronize();
}

#pragma mark - 配置解析

- (BOOL)isExpanded {
    if (self.surface != NULL && self.surface.bounds.size.width > 0) {
        return self.surface.bounds.size.width >= 220.0;
    }
    return self.presentationSize.width >= 220.0;
}

- (NSString *)configPrefix {
    return [self isExpanded] ? @"Expanded.Video" : @"Compact.Video";
}

/// 解析目标视频路径：只存文件名，落在真实 Videos 目录；旧版绝对路径仍然兼容
- (NSString *)resolvedTargetPath:(NSString **)reason {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    if (![config boolForKey:@"Global.Enabled"]) {
        if (reason) *reason = @"全局开关未开启";
        return nil;
    }
    if (![config isFeatureEnabled:MIAFXFeatureVideo]) {
        if (reason) *reason = @"全局「视频层」功能位未开启";
        return nil;
    }
    NSString *prefix = [self configPrefix];
    if (![config boolForKey:[prefix stringByAppendingString:@".Enabled"]]) {
        if (reason) *reason = [NSString stringWithFormat:@"%@ 未启用", [self isExpanded] ? @"展开背景" : @"紧凑背景"];
        return nil;
    }
    NSString *raw = [config stringForKey:[prefix stringByAppendingString:@".Path"]];
    if (raw.length == 0) {
        if (reason) *reason = @"未选择视频文件";
        return nil;
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    // 1) 绝对路径直接可用（含真实 /var/jb 路径）
    if ([raw hasPrefix:@"/"] && [manager fileExistsAtPath:raw]) {
        if (reason) *reason = nil;
        return raw;
    }
    // 2) 视为文件名，解析到真实 Videos 目录
    NSString *candidate = [MIAFXVideosDirectory() stringByAppendingPathComponent:raw.lastPathComponent];
    if ([manager fileExistsAtPath:candidate]) {
        if (reason) *reason = nil;
        return candidate;
    }
    if (reason) *reason = [NSString stringWithFormat:@"视频文件不存在：%@（已试 %@）", raw, candidate];
    return nil;
}

#pragma mark - 图层挂载

/// 沿继承链查找 ivar（系统类的 _playerLayer 可能声明在父类）
static Ivar MIAFXFindIvar(Class cls, const char *name) {
    while (cls != NULL) {
        Ivar ivar = class_getInstanceVariable(cls, name);
        if (ivar != NULL) return ivar;
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

- (AVPlayerLayer *)attachPlayerLayer {
    UIView *surface = self.surface;
    if (surface == NULL) return nil;

    Ivar ivar = MIAFXFindIvar([surface class], "_playerLayer");
    id existing = (ivar != NULL) ? object_getIvar(surface, ivar) : nil;
    if (![existing isKindOfClass:AVPlayerLayer.class]) {
        @try {
            existing = [surface valueForKey:@"_playerLayer"];
        } @catch (NSException *exception) {
            (void)exception;
            existing = nil;
        }
    }

    if ([existing isKindOfClass:AVPlayerLayer.class]) {
        AVPlayerLayer *layer = (AVPlayerLayer *)existing;
        if (layer.superlayer == NULL) {
            [surface.layer insertSublayer:layer atIndex:0];
            [self diagNow:[NSString stringWithFormat:@"系统 _playerLayer 不在层树，已插入 index 0（surface=%p）", surface]];
        }
        if (layer.hidden) {
            layer.hidden = NO;
            [self diagNow:@"系统 _playerLayer 原为 hidden，已取消隐藏"];
        }
        self.layer = layer;
        return layer;
    }

    if (ivar != NULL) {
        AVPlayerLayer *layer = [AVPlayerLayer layer];
        object_setIvar(surface, ivar, layer);
        [surface.layer insertSublayer:layer atIndex:0];
        self.layer = layer;
        [self diagNow:[NSString stringWithFormat:@"_playerLayer 为空，已自建 AVPlayerLayer 写入 ivar 并插入层树（surface=%p）", surface]];
        return layer;
    }

    AVPlayerLayer *layer = [AVPlayerLayer layer];
    [surface.layer insertSublayer:layer atIndex:0];
    self.layer = layer;
    [self diagNow:[NSString stringWithFormat:@"类 %@ 无 _playerLayer ivar，已作为子图层插入 index 0", NSStringFromClass([surface class])]];
    return layer;
}

#pragma mark - 几何 / 外观

- (void)updateGeometry {
    if (self.layer == NULL || self.surface == NULL) return;
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    NSString *prefix = [self configPrefix];

    CGRect bounds = self.surface.bounds;
    if (bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        if (self.presentationSize.width > 0.0 && self.presentationSize.height > 0.0) {
            bounds = (CGRect){CGPointZero, self.presentationSize};
        } else {
            return;
        }
    }

    double scale = [config doubleForKey:[prefix stringByAppendingString:@".Scale"]];
    double offsetX = [config doubleForKey:[prefix stringByAppendingString:@".OffsetX"]];
    double offsetY = [config doubleForKey:[prefix stringByAppendingString:@".OffsetY"]];
    double alpha = [config doubleForKey:[prefix stringByAppendingString:@".Alpha"]];
    NSInteger fill = [config integerForKey:[prefix stringByAppendingString:@".FillMode"]];
    NSInteger cornerMode = [config integerForKey:[prefix stringByAppendingString:@".CornerMode"]];
    double customRadius = [config doubleForKey:[prefix stringByAppendingString:@".CornerRadius"]];

    if (scale <= 0.0) scale = 1.0;
    CGSize size = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
    CGPoint origin = CGPointMake((bounds.size.width - size.width) / 2.0 + offsetX,
                                 (bounds.size.height - size.height) / 2.0 + offsetY);
    self.layer.frame = (CGRect){origin, size};
    self.layer.opacity = (float)alpha;
    self.layer.videoGravity = (fill == 0) ? AVLayerVideoGravityResize
                         : (fill == 2) ? AVLayerVideoGravityResizeAspect
                         : AVLayerVideoGravityResizeAspectFill;

    double radius = 0.0;
    if (cornerMode == 1) {
        radius = (self.presentationRadius > 0.0) ? self.presentationRadius
                 : MIN(size.width, size.height) / 2.0;
    } else if (cornerMode == 2) {
        radius = customRadius;
    }
    self.layer.cornerRadius = radius;
    self.layer.masksToBounds = YES;
}

#pragma mark - 同步主逻辑

- (void)handleTrigger:(NSString *)reason {
    if (self.surface == NULL) return;
    if (reason.length > 0) [self diag:[NSString stringWithFormat:@"触发[%@] surface=%p bounds=%@", reason, self.surface, NSStringFromCGRect(self.surface.bounds)]];
    if (self.layer != NULL) [self updateGeometry];
    [MIAFXVideoBackground consumePendingImports];
    [self syncIfNeeded];
}

- (void)syncIfNeeded {
    if (self.surface == NULL) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!self.needsSync && (now - self.lastEvaluation) < kMIAFXVideoEvalInterval) return;
    self.needsSync = NO;
    self.lastEvaluation = now;

    NSString *reason = nil;
    NSString *path = [self resolvedTargetPath:&reason];

    if (path == nil) {
        if (self.player != NULL) {
            [self diagNow:[NSString stringWithFormat:@"视频背景停止：%@", reason ?: @"未知原因"]];
            [self stop];
        } else if (reason.length > 0) {
            [self diagNow:[NSString stringWithFormat:@"视频背景未播放：%@", reason]];
        }
        return;
    }

    if ([path isEqualToString:self.loadedPath] && self.player != NULL) {
        [self updateGeometry];
        if (self.player.rate == 0.0) {
            [self.player play];
            [self diagNow:[NSString stringWithFormat:@"恢复播放 %@", path.lastPathComponent]];
        }
        return;
    }

    AVPlayerLayer *layer = [self attachPlayerLayer];
    if (layer == NULL) {
        self.needsSync = YES;
        self.lastEvaluation = now - kMIAFXVideoEvalInterval;
        return;
    }

    [self stop];

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
    self.player = [AVQueuePlayer queuePlayerWithItems:@[item]];
    self.player.muted = YES;
    self.looper = [AVPlayerLooper playerLooperWithPlayer:self.player templateItem:item];
    layer.player = self.player;
    layer.hidden = NO;
    [self updateGeometry];
    self.loadedPath = path;
    [self.player play];

    [self diagNow:[NSString stringWithFormat:@"视频背景已挂载：%@ layer=%p frame=%@ radius=%.1f gravity=%ld",
                   path.lastPathComponent, layer, NSStringFromCGRect(layer.frame),
                   layer.cornerRadius, (long)layer.videoGravity]];
}

- (void)stop {
    if (self.layer != NULL && self.layer.player == self.player) {
        self.layer.player = nil;
    }
    if (self.player != NULL) {
        [self.player pause];
        self.player = nil;
    }
    self.looper = nil;
    self.loadedPath = nil;
    self.needsSync = NO;
}

- (void)dealloc {
    [self stop];
}

@end

#pragma mark - 模块入口

#ifdef __cplusplus
extern "C" {
#endif

void MIAFXVideoBackgroundStart(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MIAFXDiag(@"视频背景模块启动，开始探测宿主类");
        // 1) 先消费设置端暂存的视频（SpringBoard realm 与沙盒 App 不互通，文件必须由插件端落地）
        [MIAFXVideoBackground consumePendingImports];
        // 2) 安装懒加载 hook（类可能晚注册）
        MIAFXTryInstallHooks(YES);
        _dyld_register_func_for_add_image(MIAFXDyldImageCallback);
        MIAFXScheduleHookRetry();
        MIAFXRegisterSystemNotifications();
    });
}

#ifdef __cplusplus
}
#endif
