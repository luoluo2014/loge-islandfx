//
//  MIAFXIslandHostBridge.m
//  MIAFX
//
//  延迟探测宿主类；只用 class_getInstanceMethod 确认过的方法装 MSHookMessageEx。
//  原始 IMP 每次恰好调用一次；MIAFX 的后处理包在异常保护里，不影响系统调用链。
//

#import "MIAFXIslandHostBridge.h"

#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPassthroughView.h"
#import "MIAFXProbe.h"
#import "MIAFXRootRenderer.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"
#import "MIAFXStateCoordinator.h"

#if __has_include(<substrate.h>)
#import <substrate.h>
#elif __has_include(<CydiaSubstrate/CydiaSubstrate.h>)
#import <CydiaSubstrate/CydiaSubstrate.h>
#else
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);
#endif

#pragma mark - Hook helper

/// 只有在 class_getInstanceMethod 确认方法存在时才装 hook。
BOOL MIAFXInstallInstanceHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (cls == Nil || selector == NULL || replacement == NULL) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return NO;
    }
    if (method_getImplementation(method) == replacement) {
        // 已经装过，避免重复包装
        return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}

#pragma mark - Function pointer types

typedef void (*MIAFXVoidIMP)(id, SEL);
typedef void (*MIAFXBoolIMP)(id, SEL, BOOL);
typedef double (*MIAFXDoubleIMP)(id, SEL);

#pragma mark - Originals

// MRUActivityNowPlayingViewController
static IMP MIAFXOrig_MRUVC_viewDidLoad = NULL;
static IMP MIAFXOrig_MRUVC_viewWillAppear = NULL;
static IMP MIAFXOrig_MRUVC_viewDidDisappear = NULL;
static IMP MIAFXOrig_MRUVC_viewDidLayoutSubviews = NULL;
static IMP MIAFXOrig_MRUVC_preferredHeight = NULL;

// MRUActivityNowPlayingView
static IMP MIAFXOrig_MRUV_viewDidLoad = NULL;
static IMP MIAFXOrig_MRUV_viewWillAppear = NULL;
static IMP MIAFXOrig_MRUV_viewDidDisappear = NULL;
static IMP MIAFXOrig_MRUV_viewDidLayoutSubviews = NULL;
static IMP MIAFXOrig_MRUV_preferredHeight = NULL;

// SAUIElementView
static IMP MIAFXOrig_SAUI_viewDidLoad = NULL;
static IMP MIAFXOrig_SAUI_viewWillAppear = NULL;
static IMP MIAFXOrig_SAUI_viewDidDisappear = NULL;
static IMP MIAFXOrig_SAUI_viewDidLayoutSubviews = NULL;
static IMP MIAFXOrig_SAUI_preferredHeight = NULL;

// SpringBoard
static IMP MIAFXOrig_SB_applicationDidFinishLaunching = NULL;

#pragma mark - Hook macros

/// 无参无返回值
#define MIAFX_DEFINE_VOID_HOOK(symbol, selectorName, event)                                \
static void MIAFXHook_##symbol(id self, SEL _cmd) {                                        \
    IMP original = MIAFXOrig_##symbol;                                                      \
    if (original != NULL) { ((MIAFXVoidIMP)original)(self, _cmd); }                        \
    MIAFXRunProtected(@"IslandHostBridge", ^{                                                \
        [[MIAFXIslandHostBridge sharedBridge] noteHostEvent:(event) object:self];          \
    });                                                                                      \
}

/// 带 BOOL 参数
#define MIAFX_DEFINE_BOOL_HOOK(symbol, selectorName, event)                                \
static void MIAFXHook_##symbol(id self, SEL _cmd, BOOL animated) {                        \
    IMP original = MIAFXOrig_##symbol;                                                      \
    if (original != NULL) { ((MIAFXBoolIMP)original)(self, _cmd, animated); }              \
    MIAFXRunProtected(@"IslandHostBridge", ^{                                                \
        [[MIAFXIslandHostBridge sharedBridge] noteHostEvent:(event) object:self];          \
    });                                                                                      \
}

/// 返回 double
#define MIAFX_DEFINE_DOUBLE_HOOK(symbol, selectorName, event)                              \
static double MIAFXHook_##symbol(id self, SEL _cmd) {                                      \
    IMP original = MIAFXOrig_##symbol;                                                      \
    double value = 0.0;                                                                     \
    if (original != NULL) { value = ((MIAFXDoubleIMP)original)(self, _cmd); }                \
    MIAFXRunProtected(@"IslandHostBridge", ^{                                                \
        [[MIAFXIslandHostBridge sharedBridge] noteHostEvent:(event) object:self];          \
    });                                                                                      \
    return value;                                                                            \
}

#pragma mark - Hook implementations

// MRUActivityNowPlayingViewController
MIAFX_DEFINE_VOID_HOOK(MRUVC_viewDidLoad, viewDidLoad, MIAFXHostEventViewDidLoad)
MIAFX_DEFINE_BOOL_HOOK(MRUVC_viewWillAppear, viewWillAppear:, MIAFXHostEventViewWillAppear)
MIAFX_DEFINE_BOOL_HOOK(MRUVC_viewDidDisappear, viewDidDisappear:, MIAFXHostEventViewDidDisappear)
MIAFX_DEFINE_VOID_HOOK(MRUVC_viewDidLayoutSubviews, viewDidLayoutSubviews, MIAFXHostEventDidLayout)
MIAFX_DEFINE_DOUBLE_HOOK(MRUVC_preferredHeight, preferredHeightForBottomSafeArea, MIAFXHostEventPreferredHeight)

// MRUActivityNowPlayingView
MIAFX_DEFINE_VOID_HOOK(MRUV_viewDidLoad, viewDidLoad, MIAFXHostEventViewDidLoad)
MIAFX_DEFINE_BOOL_HOOK(MRUV_viewWillAppear, viewWillAppear:, MIAFXHostEventViewWillAppear)
MIAFX_DEFINE_BOOL_HOOK(MRUV_viewDidDisappear, viewDidDisappear:, MIAFXHostEventViewDidDisappear)
MIAFX_DEFINE_VOID_HOOK(MRUV_viewDidLayoutSubviews, viewDidLayoutSubviews, MIAFXHostEventDidLayout)
MIAFX_DEFINE_DOUBLE_HOOK(MRUV_preferredHeight, preferredHeightForBottomSafeArea, MIAFXHostEventPreferredHeight)

// SAUIElementView
MIAFX_DEFINE_VOID_HOOK(SAUI_viewDidLoad, viewDidLoad, MIAFXHostEventViewDidLoad)
MIAFX_DEFINE_BOOL_HOOK(SAUI_viewWillAppear, viewWillAppear:, MIAFXHostEventViewWillAppear)
MIAFX_DEFINE_BOOL_HOOK(SAUI_viewDidDisappear, viewDidDisappear:, MIAFXHostEventViewDidDisappear)
MIAFX_DEFINE_VOID_HOOK(SAUI_viewDidLayoutSubviews, viewDidLayoutSubviews, MIAFXHostEventDidLayout)
MIAFX_DEFINE_DOUBLE_HOOK(SAUI_preferredHeight, preferredHeightForBottomSafeArea, MIAFXHostEventPreferredHeight)

/// SpringBoard 启动完成：只做记录 + 启动渲染，不改任何系统行为
static void MIAFXHook_SB_applicationDidFinishLaunching(id self, SEL _cmd, id application) {
    IMP original = MIAFXOrig_SB_applicationDidFinishLaunching;
    if (original != NULL) {
        ((void (*)(id, SEL, id))original)(self, _cmd, application);
    }
    MIAFXRunProtected(@"IslandHostBridge", ^{
        [[MIAFXIslandHostBridge sharedBridge] noteSpringBoardReady];
    });
}

#pragma mark - Layout mode

/// NextUp3 已验证的 iOS17 expanded 判据：activeLayoutMode >= 4
static NSInteger MIAFXReadLayoutMode(id object) {
    static NSArray<NSString *> *selectors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selectors = @[ @"activeLayoutMode", @"layoutMode" ];
    });
    if (!object) {
        return 0;
    }
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if (![object respondsToSelector:selector]) {
            continue;
        }
        NSInteger (*getter)(id, SEL) = (NSInteger (*)(id, SEL))objc_msgSend;
        NSInteger value = getter(object, selector);
        if (value != 0) {
            return value;
        }
    }
    return 0;
}

static BOOL MIAFXIsExpandedLayoutMode(NSInteger mode) {
    return mode >= 4;
}

#pragma mark - Hook table

typedef struct {
    const char *className;
    const char *selectorName;
    IMP replacement;
    IMP *original;
    BOOL installed;
} MIAFXHookRecord;

static MIAFXHookRecord gHookRecords[] = {
    { "MRUActivityNowPlayingViewController", "viewDidLoad", (IMP)MIAFXHook_MRUVC_viewDidLoad, &MIAFXOrig_MRUVC_viewDidLoad, NO },
    { "MRUActivityNowPlayingViewController", "viewWillAppear:", (IMP)MIAFXHook_MRUVC_viewWillAppear, &MIAFXOrig_MRUVC_viewWillAppear, NO },
    { "MRUActivityNowPlayingViewController", "viewDidDisappear:", (IMP)MIAFXHook_MRUVC_viewDidDisappear, &MIAFXOrig_MRUVC_viewDidDisappear, NO },
    { "MRUActivityNowPlayingViewController", "viewDidLayoutSubviews", (IMP)MIAFXHook_MRUVC_viewDidLayoutSubviews, &MIAFXOrig_MRUVC_viewDidLayoutSubviews, NO },
    { "MRUActivityNowPlayingViewController", "preferredHeightForBottomSafeArea", (IMP)MIAFXHook_MRUVC_preferredHeight, &MIAFXOrig_MRUVC_preferredHeight, NO },

    { "MRUActivityNowPlayingView", "viewDidLoad", (IMP)MIAFXHook_MRUV_viewDidLoad, &MIAFXOrig_MRUV_viewDidLoad, NO },
    { "MRUActivityNowPlayingView", "viewWillAppear:", (IMP)MIAFXHook_MRUV_viewWillAppear, &MIAFXOrig_MRUV_viewWillAppear, NO },
    { "MRUActivityNowPlayingView", "viewDidDisappear:", (IMP)MIAFXHook_MRUV_viewDidDisappear, &MIAFXOrig_MRUV_viewDidDisappear, NO },
    { "MRUActivityNowPlayingView", "viewDidLayoutSubviews", (IMP)MIAFXHook_MRUV_viewDidLayoutSubviews, &MIAFXOrig_MRUV_viewDidLayoutSubviews, NO },
    { "MRUActivityNowPlayingView", "preferredHeightForBottomSafeArea", (IMP)MIAFXHook_MRUV_preferredHeight, &MIAFXOrig_MRUV_preferredHeight, NO },

    { "SAUIElementView", "viewDidLoad", (IMP)MIAFXHook_SAUI_viewDidLoad, &MIAFXOrig_SAUI_viewDidLoad, NO },
    { "SAUIElementView", "viewWillAppear:", (IMP)MIAFXHook_SAUI_viewWillAppear, &MIAFXOrig_SAUI_viewWillAppear, NO },
    { "SAUIElementView", "viewDidDisappear:", (IMP)MIAFXHook_SAUI_viewDidDisappear, &MIAFXOrig_SAUI_viewDidDisappear, NO },
    { "SAUIElementView", "viewDidLayoutSubviews", (IMP)MIAFXHook_SAUI_viewDidLayoutSubviews, &MIAFXOrig_SAUI_viewDidLayoutSubviews, NO },
    { "SAUIElementView", "preferredHeightForBottomSafeArea", (IMP)MIAFXHook_SAUI_preferredHeight, &MIAFXOrig_SAUI_preferredHeight, NO },

    { "SpringBoard", "applicationDidFinishLaunching:", (IMP)MIAFXHook_SB_applicationDidFinishLaunching, &MIAFXOrig_SB_applicationDidFinishLaunching, NO },
};

static const size_t kMIAFXHookRecordCount = sizeof(gHookRecords) / sizeof(gHookRecords[0]);

/// 只做存在性诊断的类
static const char * const kMIAFXDiagnosticClasses[] = {
    "SBDashBoardBlankingWindow",
    "MRUActivityNowPlayingViewController",
    "MRUActivityNowPlayingView",
    "SAUIElementView",
    "SpringBoard"
};

static const size_t kMIAFXDiagnosticClassCount = sizeof(kMIAFXDiagnosticClasses) / sizeof(kMIAFXDiagnosticClasses[0]);

#pragma mark - Bridge

/// dyld 镜像加载回调（前向声明，-registerDelayedDetection 会用到）
static void MIAFXImageAddedCallback(const struct mach_header *header, intptr_t slide);

@interface MIAFXIslandHostBridge ()
@property (nonatomic, readwrite) MIAFXHostKind hostKind;
@property (nonatomic, readwrite, getter=isHooked) BOOL hooked;
@property (nonatomic, readwrite) BOOL mountSucceeded;
@property (nonatomic, readwrite) BOOL usingFallbackWindows;
@property (nonatomic, readwrite) CGRect hostBounds;
@property (nonatomic, readwrite, getter=isExpanded) BOOL expanded;
@property (nonatomic, readwrite) BOOL islandVisible;
@property (nonatomic, copy, readwrite) NSString *diagnosticsDescription;

@property (nonatomic, weak) UIView *currentHostView;
@property (nonatomic, weak) id currentHostObject;
@property (nonatomic, strong) MIAFXRootRenderer *renderer;
@property (nonatomic, strong) UIWindow *fallbackBackgroundWindow;
@property (nonatomic, strong) UIWindow *fallbackOverlayWindow;
@property (nonatomic, strong) MIAFXPassthroughView *fallbackBackgroundHost;
@property (nonatomic, strong) MIAFXPassthroughView *fallbackOverlayHost;
@property (nonatomic) BOOL springBoardReady;
@end

@implementation MIAFXIslandHostBridge

+ (instancetype)sharedBridge {
    static MIAFXIslandHostBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[MIAFXIslandHostBridge alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _hostKind = MIAFXHostKindNone;
    _hooked = NO;
    _mountSucceeded = NO;
    _usingFallbackWindows = NO;
    _islandVisible = YES;
    _hostBounds = CGRectZero;
    _expanded = NO;
    _diagnosticsDescription = @"idle";
    _springBoardReady = NO;
    return self;
}

#pragma mark - Detection

- (void)registerDelayedDetection {
    _dyld_register_func_for_add_image(MIAFXImageAddedCallback);
}

static void MIAFXImageAddedCallback(const struct mach_header *header, intptr_t slide) {
    (void)header;
    (void)slide;
    [[MIAFXIslandHostBridge sharedBridge] handleImageAdded];
}

- (void)handleImageAdded {
    if (MIAFXIsModuleDisabled(@"IslandHostBridge")) {
        return;
    }
    MIAFXRunProtected(@"IslandHostBridge", ^{
        [self recordDiagnostics];
        [self installPendingHooks];
    });
}

- (void)recordDiagnostics {
    for (size_t index = 0; index < kMIAFXDiagnosticClassCount; index++) {
        const char *name = kMIAFXDiagnosticClasses[index];
        Class cls = objc_getClass(name);
        NSString *className = [NSString stringWithUTF8String:name];
        [[MIAFXProbe sharedProbe] recordClassPresence:className exists:(cls != Nil)];
        if (cls == Nil) {
            continue;
        }
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:count];
        for (unsigned int methodIndex = 0; methodIndex < count; methodIndex++) {
            [names addObject:NSStringFromSelector(method_getName(methods[methodIndex]))];
        }
        free(methods);
        [[MIAFXProbe sharedProbe] recordMethodList:names forClass:className];
    }
}

- (void)installPendingHooks {
    BOOL installed = NO;
    for (size_t index = 0; index < kMIAFXHookRecordCount; index++) {
        MIAFXHookRecord *record = &gHookRecords[index];
        if (record->installed) {
            installed = YES;
            continue;
        }
        Class cls = objc_getClass(record->className);
        if (cls == Nil) {
            continue;
        }
        SEL selector = sel_registerName(record->selectorName);
        if (selector == NULL) {
            continue;
        }
        if (!MIAFXInstallInstanceHook(cls, selector, record->replacement, record->original)) {
            continue;
        }
        record->installed = YES;
        installed = YES;
        MIAFXLog(@"已安装 hook：%s %@", record->className, NSStringFromSelector(selector));
    }
    if (installed) {
        self.hooked = YES;
    }
}

#pragma mark - Host events

- (void)noteHostEvent:(MIAFXHostEvent)event object:(id)object {
    if (!object) {
        return;
    }
    MIAFXRunProtected(@"IslandHostBridge", ^{
        UIView *view = nil;
        if ([object isKindOfClass:UIViewController.class]) {
            view = ((UIViewController *)object).view;
        } else if ([object isKindOfClass:UIView.class]) {
            view = (UIView *)object;
        }
        if (!view) {
            return;
        }

        NSString *className = NSStringFromClass(object_getClass(object));
        if ([className isEqualToString:@"MRUActivityNowPlayingViewController"]) {
            self.hostKind = MIAFXHostKindMRUViewController;
        } else if ([className isEqualToString:@"MRUActivityNowPlayingView"]) {
            self.hostKind = MIAFXHostKindMRUView;
        } else if ([className isEqualToString:@"SAUIElementView"]) {
            self.hostKind = MIAFXHostKindSAUIElementView;
        }

        if (event == MIAFXHostEventViewWillAppear) {
            self.islandVisible = YES;
        } else if (event == MIAFXHostEventViewDidDisappear) {
            self.islandVisible = NO;
        }

        [self ensureRendererForHostView:view hostObject:object];
        [self refreshGeometry];
    });
}

- (void)ensureRendererForHostView:(UIView *)view hostObject:(id)hostObject {
    if (self.renderer && self.currentHostView == view) {
        self.currentHostObject = hostObject;
        return;
    }

    [self unmount];

    MIAFXRootRenderer *renderer = [[MIAFXRootRenderer alloc] initWithHostView:view];
    BOOL mounted = [renderer attachToHost];
    if (!mounted) {
        // 直接挂载失败：退回上下两个 pass-through UIWindow
        mounted = [self mountFallbackWindowsWithRenderer:renderer];
    }

    self.renderer = renderer;
    self.currentHostView = view;
    self.currentHostObject = hostObject;
    self.mountSucceeded = mounted;

    if (mounted) {
        [renderer start];
        if (self.springBoardReady) {
            [renderer resumeFromDisplayOff];
        }
    }
    [self updateDiagnostics];
}

#pragma mark - Fallback windows

/// 下窗口放在普通窗口之上、状态栏之下；上窗口放在 alert 之下，保证可见但不抢交互。
/// UIWindowLevel* 是 extern 常量，不能用于静态初始化器，改为运行时取值
static UIWindowLevel MIAFXFallbackBackgroundLevel(void) { return UIWindowLevelNormal + 10.0; }
static UIWindowLevel MIAFXFallbackOverlayLevel(void) { return UIWindowLevelAlert - 1.0; }

- (BOOL)mountFallbackWindowsWithRenderer:(MIAFXRootRenderer *)renderer {
    MIAFXRunProtected(@"IslandHostBridge", ^{
        CGRect screen = [UIScreen mainScreen].bounds;
        if (CGRectIsEmpty(screen)) {
            screen = CGRectMake(0.0, 0.0, 393.0, 852.0);
        }

        MIAFXPassthroughWindow *backgroundWindow = [[MIAFXPassthroughWindow alloc] initWithFrame:screen];
        backgroundWindow.windowLevel = MIAFXFallbackBackgroundLevel();
        MIAFXPassthroughWindow *overlayWindow = [[MIAFXPassthroughWindow alloc] initWithFrame:screen];
        overlayWindow.windowLevel = MIAFXFallbackOverlayLevel();

        UIViewController *backgroundController = [[UIViewController alloc] init];
        backgroundController.view.backgroundColor = [UIColor clearColor];
        backgroundController.view.opaque = NO;
        backgroundWindow.rootViewController = backgroundController;

        UIViewController *overlayController = [[UIViewController alloc] init];
        overlayController.view.backgroundColor = [UIColor clearColor];
        overlayController.view.opaque = NO;
        overlayWindow.rootViewController = overlayController;

        CGRect islandFrame = [MIAFXIslandHostBridge fallbackIslandFrameForExpanded:self.expanded];
        MIAFXPassthroughView *backgroundHost = [[MIAFXPassthroughView alloc] initWithFrame:islandFrame];
        MIAFXPassthroughView *overlayHost = [[MIAFXPassthroughView alloc] initWithFrame:islandFrame];
        [backgroundController.view addSubview:backgroundHost];
        [overlayController.view addSubview:overlayHost];

        backgroundWindow.hidden = NO;
        overlayWindow.hidden = NO;

        self.fallbackBackgroundWindow = backgroundWindow;
        self.fallbackOverlayWindow = overlayWindow;
        self.fallbackBackgroundHost = backgroundHost;
        self.fallbackOverlayHost = overlayHost;

        BOOL mounted = [renderer attachWithBackgroundContainer:backgroundHost overlayContainer:overlayHost];
        self.usingFallbackWindows = mounted;
        self.mountSucceeded = mounted;
    });
    return self.usingFallbackWindows;
}

+ (CGRect)fallbackIslandFrameForExpanded:(BOOL)expanded {
    MIAFXConfig *config = [MIAFXConfig sharedConfig];
    CGFloat width = [config doubleForKey:@"Geometry.CompactWidth"];
    CGFloat height = expanded
        ? [config doubleForKey:@"Geometry.ExpandedHeight"]
        : [config doubleForKey:@"Geometry.CompactHeight"];
    if (!isfinite(width) || width <= 0.0) {
        width = 126.0;
    }
    if (!isfinite(height) || height <= 0.0) {
        height = expanded ? 160.0 : 37.0;
    }
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat x = (screen.size.width - width) * 0.5;
    if (!isfinite(x)) {
        x = 0.0;
    }
    // 顶部安全区：至少给状态栏留出高度
    CGFloat top = 0.0;
    UIApplication *application = [UIApplication sharedApplication];
    if (application) {
        CGRect statusFrame = application.statusBarFrame;
        top = MAX(statusFrame.size.height, 44.0);
    }
    if (!isfinite(top) || top <= 0.0) {
        top = 44.0;
    }
    return CGRectMake(x, top, width, height);
}

#pragma mark - Geometry

- (void)setIslandVisible:(BOOL)islandVisible {
    if (_islandVisible == islandVisible) {
        return;
    }
    _islandVisible = islandVisible;
    // 同步给状态协调器，让它在“岛隐藏”时也能触发暂停
    [MIAFXStateCoordinator sharedCoordinator].islandVisible = islandVisible;
}

- (void)refreshGeometry {
    UIView *host = self.currentHostView;
    if (!host) {
        return;
    }
    id object = self.currentHostObject;
    NSInteger mode = MIAFXReadLayoutMode(object);
    if (mode == 0 && [object isKindOfClass:UIView.class]) {
        // 视图自身没有 layoutMode 时，尝试它的控制器
        UIResponder *responder = [(UIView *)object nextResponder];
        if ([responder isKindOfClass:UIViewController.class]) {
            mode = MIAFXReadLayoutMode(responder);
        }
    }
    BOOL expanded = MIAFXIsExpandedLayoutMode(mode);
    CGRect bounds = host.bounds;
    if (CGRectIsEmpty(bounds)) {
        bounds = [MIAFXIslandHostBridge fallbackIslandFrameForExpanded:expanded];
        bounds.origin = CGPointZero;
    }

    self.hostBounds = bounds;
    self.expanded = expanded;

    [self.renderer updateHostBounds:bounds expanded:expanded];

    if (self.usingFallbackWindows) {
        CGRect islandFrame = [MIAFXIslandHostBridge fallbackIslandFrameForExpanded:expanded];
        self.fallbackBackgroundHost.frame = islandFrame;
        self.fallbackOverlayHost.frame = islandFrame;
        self.fallbackBackgroundWindow.hidden = !self.islandVisible;
        self.fallbackOverlayWindow.hidden = !self.islandVisible;
    }

    [[MIAFXProbe sharedProbe] recordHostKind:[MIAFXIslandHostBridge nameForHostKind:self.hostKind]
                                    expanded:expanded
                                      bounds:bounds
                                  layoutMode:mode
                               mountStrategy:(self.usingFallbackWindows ? @"fallbackWindow" : @"hostSubview")];
    [[MIAFXProbe sharedProbe] flush];
    [self updateDiagnostics];
}

#pragma mark - Runtime state

- (void)handleRuntimeState:(MIAFXRuntimeState)state {
    MIAFXRunProtected(@"IslandHostBridge", ^{
        if (state == MIAFXRuntimeActive) {
            [self.renderer start];
        } else {
            [self.renderer suspendForDisplayOff];
        }
        [self updateDiagnostics];
    });
}

- (void)handleConfigurationReload {
    MIAFXRunProtected(@"IslandHostBridge", ^{
        [[MIAFXProbe sharedProbe] refreshEnabled];
        [self.renderer reloadConfiguration];
        [self updateDiagnostics];
        [[MIAFXProbe sharedProbe] flush];
    });
}

- (void)noteSpringBoardReady {
    self.springBoardReady = YES;
    MIAFXRunProtected(@"IslandHostBridge", ^{
        [self.renderer start];
        [[MIAFXProbe sharedProbe] recordRuntimeStatus:@"springboard-ready"];
        [[MIAFXProbe sharedProbe] flush];
        [self updateDiagnostics];
    });
}

#pragma mark - Teardown

- (void)unmount {
    MIAFXRunProtected(@"IslandHostBridge", ^{
        [self.renderer detach];
        self.renderer = nil;
        self.currentHostView = nil;
        self.currentHostObject = nil;
        self.mountSucceeded = NO;

        self.fallbackBackgroundWindow.hidden = YES;
        self.fallbackOverlayWindow.hidden = YES;
        self.fallbackBackgroundWindow = nil;
        self.fallbackOverlayWindow = nil;
        self.fallbackBackgroundHost = nil;
        self.fallbackOverlayHost = nil;
        self.usingFallbackWindows = NO;
    });
}

#pragma mark - Diagnostics

+ (NSString *)nameForHostKind:(MIAFXHostKind)kind {
    switch (kind) {
        case MIAFXHostKindNone: return @"None";
        case MIAFXHostKindMRUViewController: return @"MRUActivityNowPlayingViewController";
        case MIAFXHostKindMRUView: return @"MRUActivityNowPlayingView";
        case MIAFXHostKindSAUIElementView: return @"SAUIElementView";
        case MIAFXHostKindFallbackWindow: return @"FallbackWindow";
    }
    return @"Unknown";
}

- (void)updateDiagnostics {
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"host=%@ ", [MIAFXIslandHostBridge nameForHostKind:self.hostKind]];
    [description appendFormat:@"hooked=%@ ", self.hooked ? @"YES" : @"NO"];
    [description appendFormat:@"mount=%@ ", self.mountSucceeded ? @"YES" : @"NO"];
    [description appendFormat:@"fallback=%@ ", self.usingFallbackWindows ? @"YES" : @"NO"];
    [description appendFormat:@"expanded=%@ ", self.expanded ? @"YES" : @"NO"];
    [description appendFormat:@"islandVisible=%@ ", self.islandVisible ? @"YES" : @"NO"];
    [description appendFormat:@"bounds=%@ ", NSStringFromCGRect(self.hostBounds)];
    if (self.renderer) {
        [description appendString:self.renderer.runtimeDescription];
    }
    self.diagnosticsDescription = [description copy];
}

@end
