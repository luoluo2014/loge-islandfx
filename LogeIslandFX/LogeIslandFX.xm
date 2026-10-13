//
//  LogeIslandFX.xm
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  插件入口：hook 安装 + 素材投递引擎 + 崩溃循环保护。
//
//  ===== 架构（v2.0 重做，只保留「灵动岛背景视频」一个功能）=====
//
//  (1) 懒加载 hook：
//      真机日志显示 _SPIslandRenderSurface 在 dylib 注入时并不存在（类由更晚
//      加载的框架注册），Logos 静态 %hook 会静默失败。改为运行时安装：
//      轮询 + dyld 镜像回调 + 系统通知（SPRenderContextChangedNotif /
//      SPNotifSuppressionChangedNotif，与 DynamicFX 同源）多重触发，
//      类出现后逐个确认方法存在再装 MSHookMessageEx。
//
//  (2) 跨进程 realms：
//      设置 App（沙盒）与 SpringBoard（系统进程）的 jbroot() 指向不同文件
//      世界，配置走 CFPreferences app-id 域（cfprefsd 代写）；视频文件由
//      设置端以 NSData 暂存于 CFPreferences，插件端消费后落入真实
//      /var/jb/var/mobile/Library/LogeIsland/Videos/。
//
//  (3) 投递引擎：
//      5 秒轮询暂存队列 + 发布素材清单/心跳/日志尾部。不依赖任何通知，
//      灵动岛从未被触发、hook 安装失败——这些情况下轮询是最后的保底。
//
//  (4) 崩溃循环保护：
//      文件记录加载时间戳；30 秒内连续两次加载判定为崩溃循环，插件进入
//      暂停（不装 hook、不播放），设置端显示「已暂停」并可一键恢复。
//      SpringBoard 构造期不做任何 CFPreferences 写入（疑似黑屏诱因），
//      引擎整体延后 5 秒启动。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <time.h>

#import "LOGXConfig.h"
#import "LOGXConstants.h"
#import "LOGXLog.h"
#import "LOGXPath.h"
#import "LOGXStage.h"
#import "LOGXVideoBackground.h"

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

static NSString *const kLOGXSurfaceClassName = @"_SPIslandRenderSurface";
static NSString *const kLOGXContainerClassName = @"SBSystemApertureContainerView";

#pragma mark - 运行时 hook 安装器

typedef void (*LOGXVoidIMP)(id, SEL);
typedef void (*LOGXBoolIMP)(id, SEL, BOOL);
typedef void (*LOGXIdIMP)(id, SEL, id);
typedef void (*LOGXDoubleIMP)(id, SEL, double);
typedef void (*LOGXSizeIMP)(id, SEL, CGSize);

static IMP LOGXOrig_surface_setRenderVisible = NULL;
static IMP LOGXOrig_surface_displayTick = NULL;
static IMP LOGXOrig_surface_setRadius = NULL;
static IMP LOGXOrig_surface_setSize = NULL;
static IMP LOGXOrig_surface_layoutSubviews = NULL;
static IMP LOGXOrig_container_layoutSubviews = NULL;

static BOOL LOGXInstallInstanceHook(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (cls == Nil || selector == NULL || replacement == NULL) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) return NO;
    if (method_getImplementation(method) == replacement) return NO;
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}

#pragma mark - 替换实现

static void LOGXHook_surface_setRenderVisible(id self, SEL _cmd, BOOL visible) {
    if (LOGXOrig_surface_setRenderVisible != NULL) {
        ((LOGXBoolIMP)LOGXOrig_surface_setRenderVisible)(self, _cmd, visible);
    }
    if (visible) {
        [LOGXVideoBackground triggerAll:@"岛显示"];
    } else {
        [LOGXVideoBackground stopAll];
        LOGXDiag(@"岛隐藏，视频背景停止（surface=%p）", self);
    }
}

static void LOGXHook_surface_displayTick(id self, SEL _cmd, id tick) {
    if (LOGXOrig_surface_displayTick != NULL) {
        ((LOGXIdIMP)LOGXOrig_surface_displayTick)(self, _cmd, tick);
    }
    [LOGXVideoBackground triggerAll:@"display_tick"];
}

static void LOGXHook_surface_setRadius(id self, SEL _cmd, double radius) {
    if (LOGXOrig_surface_setRadius != NULL) {
        ((LOGXDoubleIMP)LOGXOrig_surface_setRadius)(self, _cmd, radius);
    }
    [LOGXVideoBackground triggerAll:[NSString stringWithFormat:@"radius=%.1f", radius]];
}

static void LOGXHook_surface_setSize(id self, SEL _cmd, CGSize size) {
    if (LOGXOrig_surface_setSize != NULL) {
        ((LOGXSizeIMP)LOGXOrig_surface_setSize)(self, _cmd, size);
    }
    [LOGXVideoBackground triggerAll:[NSString stringWithFormat:@"size=%@@", NSStringFromCGSize(size)]];
}

static void LOGXHook_surface_layoutSubviews(id self, SEL _cmd) {
    if (LOGXOrig_surface_layoutSubviews != NULL) {
        ((LOGXVoidIMP)LOGXOrig_surface_layoutSubviews)(self, _cmd);
    }
    [LOGXVideoBackground triggerAll:@"surface.layout"];
}

#pragma mark - 视图树遍历（容器视图布局时发现 surface 实例）

static NSMutableArray *LOGXCollectSurfaces(UIView *view, Class surfaceClass) {
    NSMutableArray *result = [NSMutableArray array];
    if (view == NULL || surfaceClass == NULL) return result;
    if ([view isKindOfClass:surfaceClass]) {
        [result addObject:view];
        return result;
    }
    for (UIView *sub in view.subviews) {
        [result addObjectsFromArray:LOGXCollectSurfaces(sub, surfaceClass)];
    }
    return result;
}

static void LOGXHook_container_layoutSubviews(id self, SEL _cmd) {
    if (LOGXOrig_container_layoutSubviews != NULL) {
        ((LOGXVoidIMP)LOGXOrig_container_layoutSubviews)(self, _cmd);
    }
    Class surfaceClass = objc_getClass(kLOGXSurfaceClassName.UTF8String);
    if (surfaceClass == NULL) return;
    NSMutableArray *found = LOGXCollectSurfaces((UIView *)self, surfaceClass);
    if (found.count > 0) {
        [LOGXVideoBackground triggerAll:@"container.layout"];
    }
}

static BOOL LOGXHooksInstalled = NO;

static void LOGXTryInstallHooks(BOOL logResult) {
    Class surfaceClass = objc_getClass(kLOGXSurfaceClassName.UTF8String);
    if (surfaceClass == NULL) {
        if (logResult) LOGXDiag(@"_SPIslandRenderSurface 类不存在，稍后重试");
        return;
    }
    LOGXStage("hooks-surface-class-ok");
    BOOL any = NO;
    any |= LOGXInstallInstanceHook(surfaceClass, @selector(_sp_set_render_visible:),
                                   (IMP)LOGXHook_surface_setRenderVisible, &LOGXOrig_surface_setRenderVisible);
    LOGXStage("hooks-visible");
    any |= LOGXInstallInstanceHook(surfaceClass, @selector(_sp_display_tick:),
                                   (IMP)LOGXHook_surface_displayTick, &LOGXOrig_surface_displayTick);
    LOGXStage("hooks-tick");
    any |= LOGXInstallInstanceHook(surfaceClass, @selector(setLastPresentationRadius:),
                                   (IMP)LOGXHook_surface_setRadius, &LOGXOrig_surface_setRadius);
    LOGXStage("hooks-radius");
    any |= LOGXInstallInstanceHook(surfaceClass, @selector(setLastPresentationSize:),
                                   (IMP)LOGXHook_surface_setSize, &LOGXOrig_surface_setSize);
    LOGXStage("hooks-size");
    any |= LOGXInstallInstanceHook(surfaceClass, @selector(layoutSubviews),
                                   (IMP)LOGXHook_surface_layoutSubviews, &LOGXOrig_surface_layoutSubviews);
    LOGXStage("hooks-layout");

    Class containerClass = objc_getClass(kLOGXContainerClassName.UTF8String);
    if (containerClass != NULL) {
        LOGXStage("hooks-container-class-ok");
        any |= LOGXInstallInstanceHook(containerClass, @selector(layoutSubviews),
                                       (IMP)LOGXHook_container_layoutSubviews, &LOGXOrig_container_layoutSubviews);
        LOGXStage("hooks-container");
    }

    if (any) {
        LOGXHooksInstalled = YES;
        LOGXDiag(@"运行时 hook 安装完成（%@）", NSStringFromClass(surfaceClass));
    } else if (logResult) {
        LOGXDiag(@"类已存在但未装上新 hook（可能已安装）");
    }
}

static void LOGXScheduleHookRetry(void) {
    static dispatch_source_t timer;
    static NSInteger attempt = 0;
    if (timer != NULL) return;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC, 0.5 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (LOGXHooksInstalled) {
            attempt += 1;
            if (attempt > 15) {
                dispatch_source_cancel(timer);
                timer = NULL;
                return;
            }
        }
        LOGXTryInstallHooks(NO);
    });
    dispatch_resume(timer);
}

static void LOGXDyldImageCallback(const struct mach_header *mhp, intptr_t vmaddr_slide) {
    (void)vmaddr_slide;
    LOGXTryInstallHooks(NO);
}

static int LOGXRenderContextToken = -1;
static int LOGXSuppressionToken = -1;
static int LOGXReloadToken = -1;
static int LOGXStopToken = -1;

static void LOGXRegisterSystemNotifications(void) {
    // 这两个通知由系统在灵动岛渲染上下文/抑制状态变化时投递（DynamicFX 同源）
    notify_register_dispatch("SPRenderContextChangedNotif", &LOGXRenderContextToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        LOGXTryInstallHooks(NO);
        [LOGXVideoBackground invalidateConfigCache];
        [LOGXVideoBackground triggerAll:@"SPRenderContextChanged"];
    });
    notify_register_dispatch("SPNotifSuppressionChangedNotif", &LOGXSuppressionToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [LOGXVideoBackground triggerAll:@"SPNotifSuppressionChanged"];
    });
    // 设置端保存配置时也会投递这条：立刻重评，实现「改完即生效」
    notify_register_dispatch(LOGX_NOTIFY_RELOAD, &LOGXReloadToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [LOGXVideoBackground invalidateConfigCache];
        [LOGXVideoBackground triggerAll:@"config.reload"];
    });
    // 注销前置：立刻停掉全部播放并隐藏图层，黑屏恢复期间不留半死状态
    notify_register_dispatch(LOGX_NOTIFY_SUSPEND, &LOGXStopToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [LOGXVideoBackground suspendAll];
    });
    LOGXDiag(@"已注册系统通知 SPRenderContextChangedNotif / SPNotifSuppressionChangedNotif / %s / %s",
             LOGX_NOTIFY_RELOAD, LOGX_NOTIFY_SUSPEND);
}

#pragma mark - 崩溃循环保护

static BOOL LOGXSuspended = NO;
// 真崩溃循环：SpringBoard 被 launchd 反复重拉，间隔通常 1~3 秒；
// 用户主动注销/覆盖安装到下一次加载至少十几秒。窗口收到 12 秒、
// 阈值提到 3 次，既抓得住崩溃循环，也不会再把正常操作误判成异常。
static const NSTimeInterval kLOGXFastLoadWindow = 12.0;
static const NSInteger kLOGXFastLoadLimit = 3;

static void LOGXWriteBootState(double lastLoadAt, NSInteger fastLoads) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [@{@"lastLoadAt": @(lastLoadAt), @"fastLoads": @(fastLoads)}
            writeToFile:LOGXBootStatePath() atomically:YES];
    });
}

static void LOGXEvaluateBootGuard(void) {
    // 设置端注销前会写 IntentionalRespring 标记：这是用户主动重启，直接清零计数
    if ([LOGXPrefsObject(LOGX_KEY_INTENTIONAL_RESPRING) boolValue]) {
        LOGXPrefsRemoveObject(LOGX_KEY_INTENTIONAL_RESPRING);
        LOGXWriteBootState(0.0, 0);
        LOGXDiag(@"检测到用户主动注销标记：崩溃循环计数已清零");
        return;
    }

    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:LOGXBootStatePath()];
    double last = [state[@"lastLoadAt"] doubleValue];
    NSInteger fast = [state[@"fastLoads"] integerValue];
    double now = [[NSDate date] timeIntervalSince1970];

    if (last > 0.0 && (now - last) < kLOGXFastLoadWindow) {
        fast += 1;
        if (fast >= kLOGXFastLoadLimit) {
            LOGXSuspended = YES;
            LOGXDiag(@"崩溃循环保护：%.0f 秒内连续 %ld 次加载，插件进入暂停（不装 hook、不播放）。可在设置中一键恢复。",
                     now - last, (long)fast);
        }
    } else {
        fast = 0;
    }
    LOGXWriteBootState(now, fast);
}

#pragma mark - 素材投递引擎

@interface LOGXEngine : NSObject
+ (void)start;
+ (void)tick;
+ (void)consumePendingImports;
+ (void)processDeleteRequests;
+ (void)processResumeRequest;
+ (void)processClearLogRequest;
+ (void)publishAssets;
+ (void)publishHeartbeat;
+ (void)publishLogTail;
@end

@implementation LOGXEngine

+ (void)start {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LOGXDiag(@"投递引擎启动：5 秒轮询 + 心跳 + 日志发布");
        // 启动即刻来一轮：SpringBoard 若在设置端导入之后才重启，开机就能把队列消费掉
        [LOGXEngine tick];
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (timer == NULL) return;
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 5.0 * NSEC_PER_SEC, 1.0 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ [LOGXEngine tick]; });
        dispatch_resume(timer);
    });
}

+ (void)tick {
    if (LOGXSuspended) {
        // 暂停态只处理恢复请求，不消费投递、不发布（设置端据此显示「已暂停」）
        [LOGXEngine processResumeRequest];
        [LOGXEngine publishHeartbeat];
        return;
    }
    LOGXStage("tick-consume");
    [LOGXEngine consumePendingImports];
    LOGXStage("tick-delete");
    [LOGXEngine processDeleteRequests];
    LOGXStage("tick-resume");
    [LOGXEngine processResumeRequest];
    LOGXStage("tick-clearlog");
    [LOGXEngine processClearLogRequest];
    LOGXStage("tick-assets");
    [LOGXEngine publishAssets];
    LOGXStage("tick-heartbeat");
    [LOGXEngine publishHeartbeat];
    LOGXStage("tick-logtail");
    [LOGXEngine publishLogTail];
    LOGXStage("tick-notify");
    // 通知设置端刷新（引擎发布的素材清单/心跳/日志有了新值）
    notify_post(LOGX_NOTIFY_RELOAD);
    LOGXStage("tick-done");
}

/// 消费设置端暂存的待导入视频，落入插件可读的真实目录
+ (void)consumePendingImports {
    LOGXPrefsSynchronize();
    NSArray *pending = LOGXPrefsObject(LOGX_KEY_PENDING_IMPORTS);
    if (![pending isKindOfClass:NSArray.class] || pending.count == 0) return;

    LOGXDiag(@"投递：收到 %lu 个待导入文件", (unsigned long)pending.count);

    NSString *directory = LOGXVideosDirectory();
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                  attributes:@{NSFilePosixPermissions:@0755} error:&error]) {
        LOGXDiag(@"投递失败：创建 Videos 目录 %@ 出错：%@", directory, error.localizedDescription ?: @"未知");
        return;
    }
    BOOL changed = NO;
    for (NSString *name in pending) {
        if (![name isKindOfClass:NSString.class] || name.length == 0) continue;
        NSString *safeName = name.lastPathComponent;
        NSString *blobKey = [NSString stringWithFormat:LOGX_KEY_IMPORT_BLOB_FMT, safeName];
        NSData *data = LOGXPrefsObject(blobKey);
        if (![data isKindOfClass:NSData.class] || data.length == 0) {
            // 数据缺失（设置端没写进来 / 域没同步过来）：丢掉这条，避免反复重试同一失败项
            LOGXDiag(@"投递失败：%@ 的数据缺失（键 %@ 读不到 NSData），已从队列移除", safeName, blobKey);
            LOGXPrefsRemoveObject(blobKey);
            continue;
        }
        NSString *destination = [directory stringByAppendingPathComponent:safeName];
        if ([data writeToFile:destination atomically:YES]) {
            changed = YES;
            LOGXDiag(@"投递成功：%@（%lu KB）→ %@", safeName, (unsigned long)(data.length / 1024), destination);
        } else {
            LOGXDiag(@"投递失败：写入 %@ 出错（目录权限？）", destination);
        }
        LOGXPrefsRemoveObject(blobKey);
    }
    LOGXPrefsSetObject(@[], LOGX_KEY_PENDING_IMPORTS);
    LOGXPrefsSynchronize();
    if (changed) {
        [LOGXEngine publishAssets];
        [LOGXVideoBackground invalidateConfigCache];
        [LOGXVideoBackground triggerAll:@"导入落地"];
    }
}

/// 处理设置端的删除请求（删除已落地素材）
/// 2.0.14：不再用 CFPreferencesCopyKeyList 遍历（它在 SpringBoard 里会崩，stage.log
/// 定位到 tick-delete 即此处）。改为设置端维护一个待删除文件名队列，这里只读队列。
+ (void)processDeleteRequests {
    LOGXPrefsSynchronize();
    NSArray *queue = LOGXPrefsObject(LOGX_KEY_DELETE_QUEUE);
    if (![queue isKindOfClass:NSArray.class] || queue.count == 0) return;

    BOOL changed = NO;
    for (NSString *name in queue) {
        if (![name isKindOfClass:NSString.class] || name.length == 0) continue;
        NSString *safeName = name.lastPathComponent;
        NSString *target = [LOGXVideosDirectory() stringByAppendingPathComponent:safeName];
        NSError *error = nil;
        if ([NSFileManager.defaultManager removeItemAtPath:target error:&error]) {
            changed = YES;
            LOGXDiag(@"已按设置端请求删除素材：%@", safeName);
        } else if (![NSFileManager.defaultManager fileExistsAtPath:target]) {
            LOGXDiag(@"删除请求：%@ 已不存在", safeName);
        } else {
            LOGXDiag(@"删除失败：%@（%@）", safeName, error.localizedDescription ?: @"未知");
        }
    }
    // 清空队列（无论成功与否，避免反复重试同一失败项）
    LOGXPrefsSetObject(@[], LOGX_KEY_DELETE_QUEUE);
    LOGXPrefsSynchronize();

    if (changed) {
        [LOGXEngine publishAssets];
        [LOGXVideoBackground invalidateConfigCache];
        [LOGXVideoBackground triggerAll:@"素材删除"];
    }
}

/// 处理设置端的恢复启用请求（崩溃循环暂停后解除）
+ (void)processResumeRequest {
    if (![LOGXPrefsObject(LOGX_KEY_RESUME_REQUEST) boolValue]) return;
    LOGXPrefsRemoveObject(LOGX_KEY_RESUME_REQUEST);
    LOGXPrefsSynchronize();
    LOGXSuspended = NO;
    LOGXWriteBootState(0, 0);   // 清零时间戳与计数，重新计观察期
    LOGXDiag(@"收到恢复启用请求：已解除暂停，重新安装 hook");
    LOGXTryInstallHooks(YES);
    [LOGXVideoBackground invalidateConfigCache];
    [LOGXVideoBackground triggerAll:@"恢复启用"];
}

/// 处理设置端的清空日志请求
+ (void)processClearLogRequest {
    if (![LOGXPrefsObject(LOGX_KEY_LOG_CLEAR_REQ) boolValue]) return;
    LOGXPrefsRemoveObject(LOGX_KEY_LOG_CLEAR_REQ);
    LOGXPrefsSynchronize();
    [NSFileManager.defaultManager removeItemAtPath:LOGXLogPath() error:nil];
    LOGXDiag(@"诊断日志已按设置端请求清空");
    [LOGXEngine publishLogTail];
}

/// 把真实 Videos 目录清单发布到 CFPreferences，供设置端展示
+ (void)publishAssets {
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:LOGXVideosDirectory() error:nil] ?: @[];
    NSSet<NSString *> *extensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mpg", @"mpeg", @"3gp", @"avi", @"mkv", @"webm"]];
    NSMutableArray *assets = [NSMutableArray array];
    for (NSString *name in items) {
        if (![extensions containsObject:name.pathExtension.lowercaseString]) continue;
        NSString *full = [LOGXVideosDirectory() stringByAppendingPathComponent:name];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:full error:nil];
        if ([attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) continue;
        NSDate *modified = attributes[NSFileModificationDate];
        [assets addObject:@{
            @"name": name,
            @"size": @([attributes[NSFileSize] unsignedLongLongValue] / 1024),
            @"date": modified ? modified.description : @"",
        }];
    }
    [assets sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                                 selector:@selector(localizedCaseInsensitiveCompare:)]]];
    LOGXPrefsSetObject(assets, LOGX_KEY_ASSETS_VIDEOS);
    LOGXPrefsSynchronize();
}

/// 发布心跳：设置端据此判断「插件是否加载、是否在读同一个 CFPreferences 域」
+ (void)publishHeartbeat {
    NSDictionary *heartbeat = @{
        @"at": @([[NSDate date] timeIntervalSince1970]),
        @"atText": [[NSDate date] description],
        @"version": LOGX_PLUGIN_VERSION_STRING,
        @"pid": @(getpid()),
        @"dir": LOGXVideosDirectory(),
        @"suspended": @(LOGXSuspended),
    };
    LOGXPrefsSetObject(heartbeat, LOGX_KEY_HEARTBEAT);
    LOGXPrefsSynchronize();
}

/// 发布诊断日志尾部（最多 64KB）给设置端展示。
/// 2.0.21 起同时发布 stage.log：该文件由插件端与设置端共用（stage.log 里两类
/// 打点混排即为证据），内含全部阶段打点（prefs-* / ds-rows-* / cell-*-init /
/// engine-*），是定位设置端问题的唯一实证来源。此前只发 video-diag.log，
/// 用户出问题时拿不到 stage.log，只能干等。
+ (void)publishLogTail {
    static NSUInteger lastDiagSize = 0;
    static NSUInteger lastStageSize = 0;

    NSString *stageTail = @"";
    NSString *stagePath = LOGXStageLogPath();
    NSFileHandle *stageHandle = [NSFileHandle fileHandleForReadingAtPath:stagePath];
    NSUInteger stageSize = 0;
    if (stageHandle != NULL) {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:stagePath error:nil];
        stageSize = [attributes[NSFileSize] unsignedIntegerValue];
        const NSUInteger kMaxStageTail = 6 * 1024;
        if (stageSize > kMaxStageTail) [stageHandle seekToFileOffset:stageSize - kMaxStageTail];
        NSData *stageData = [stageHandle readDataToEndOfFile];
        [stageHandle closeFile];
        stageTail = [[NSString alloc] initWithData:stageData encoding:NSUTF8StringEncoding] ?: @"";
    }

    NSString *diagTail = @"";
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:LOGXLogPath()];
    NSUInteger diagSize = 0;
    if (handle != NULL) {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:LOGXLogPath() error:nil];
        diagSize = [attributes[NSFileSize] unsignedIntegerValue];
        const NSUInteger kMaxTail = 4 * 1024;   // 只发布末尾 4KB（大字符串写 CFPreferences 在 SpringBoard 里风险高）
        if (diagSize > kMaxTail) [handle seekToFileOffset:diagSize - kMaxTail];
        NSData *tail = [handle readDataToEndOfFile];
        [handle closeFile];
        diagTail = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding] ?: @"";
    }

    if (diagSize == lastDiagSize && stageSize == lastStageSize) return;
    lastDiagSize = diagSize;
    lastStageSize = stageSize;

    if (stageTail.length == 0 && diagTail.length == 0) {
        LOGXPrefsSetObject(@"", LOGX_KEY_LOG_TAIL);
        LOGXPrefsSetObject(@0, LOGX_KEY_LOG_SIZE);
        LOGXPrefsSynchronize();
        return;
    }

    NSString *text = [NSString stringWithFormat:
                      @"===== stage.log（阶段打点：设置端+插件端共用）=====\n%@"
                      @"\n===== video-diag.log（插件端运行日志）=====\n%@",
                      stageTail, diagTail];
    LOGXPrefsSetObject(text, LOGX_KEY_LOG_TAIL);
    LOGXPrefsSetObject(@(stageSize + diagSize), LOGX_KEY_LOG_SIZE);
    LOGXPrefsSynchronize();
}

@end

#pragma mark - 模块入口

static void LOGXStartEngineDelayed(void) {
    // 延后 5 秒：等 SpringBoard 完成启动流程再开始写 CFPreferences / 装 hook。
    // 构造期写跨进程偏好被怀疑是早前「黑屏卡死」的诱因之一，重做后彻底避开。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LOGXStage("engine-callback-enter");
        if (LOGXSuspended) {
            LOGXStage("engine-suspended-branch");
            LOGXDiag(@"插件处于暂停态：不安装 hook、不播放，仅等待设置端恢复");
            [LOGXEngine start];   // 引擎仍运行，以便处理恢复请求并发布暂停态心跳
            LOGXStage("engine-suspended-started");
            return;
        }
        LOGXStage("engine-log-version");
        LOGXDiag(@"灵动岛背景视频模块启动（v%s）", LOGX_PLUGIN_VERSION_STRING.UTF8String);
        LOGXStage("engine-try-hooks");
        LOGXTryInstallHooks(YES);
        LOGXStage("engine-hooks-done");
        _dyld_register_func_for_add_image(LOGXDyldImageCallback);
        LOGXStage("engine-dyldcb-registered");
        LOGXScheduleHookRetry();
        LOGXStage("engine-retry-scheduled");
        LOGXRegisterSystemNotifications();
        LOGXStage("engine-notif-registered");
        [LOGXEngine start];
        LOGXStage("engine-started");
    });
}

%ctor {
    LOGXStage("ctor-enter");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        LOGXStage("ctor-once-enter");
        LOGXEnsureDataDirectories(nil);
        LOGXStage("ctor-dirs-ok");
        LOGXEvaluateBootGuard();
        LOGXStage("ctor-bootguard-ok");
        LOGXDiag(@"dylib 已注入 SpringBoard（pid %d，暂停=%d）", getpid(), LOGXSuspended);
        LOGXStage("ctor-diag-ok");
        LOGXStartEngineDelayed();
        LOGXStage("ctor-engine-scheduled");
    });
    LOGXStage("ctor-exit");
}
