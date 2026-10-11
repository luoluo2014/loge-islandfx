//
//  MIAFXMain.xm
//  MIAFX
//
//  SpringBoard 侧入口：
//   1. 进程门控（必须是 SpringBoard，且 iOS 17.1+）
//   2. MIAFXBeginBootGuard 启动保护，60 秒后 MIAFXMarkBootStable
//   3. _dyld_register_func_for_add_image 延迟探测宿主私有类
//
//  注意：所有对私有类 / 私有方法的 hook 都由 MIAFXIslandHostBridge 在
//  class_getInstanceMethod 确认之后用 MSHookMessageEx 安装，
//  本文件不做任何 Logos 静态 hook。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <mach-o/dyld.h>
#import <notify.h>
#import <objc/runtime.h>

#import "MIAFXClock.h"
#import "MIAFXConfig.h"
#import "MIAFXConstants.h"
#import "MIAFXIslandHostBridge.h"
#import "MIAFXLog.h"
#import "MIAFXPath.h"
#import "MIAFXProbe.h"
#import "MIAFXSafe.h"
#import "MIAFXStateCoordinator.h"

static BOOL gMIAFXBootGuardPassed = NO;
static int gMIAFXDiagnosticsToken = -1;
static int gMIAFXRescanToken = -1;

#pragma mark - Process gate

static BOOL MIAFXIsSpringBoardProcess(void) {
    static BOOL result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *processName = [[NSProcessInfo processInfo] processName];
        NSString *executable = [[[NSBundle mainBundle] executablePath] lastPathComponent];
        result = ([processName isEqualToString:@"SpringBoard"] ||
                  [executable isEqualToString:@"SpringBoard"]);
    });
    return result;
}

static NSString *MIAFXSystemVersionString(void) {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)version.majorVersion,
            (long)version.minorVersion,
            (long)version.patchVersion];
}

/// iOS 17.1 起才启用（NextUp3 的 expanded 判据在 17.x 上验证过）
static BOOL MIAFXIsSupportedSystemVersion(void) {
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (version.majorVersion > 17) {
        return YES;
    }
    if (version.majorVersion == 17) {
        return version.minorVersion >= 1;
    }
    return NO;
}

#pragma mark - Notifications

static void MIAFXRegisterNotifications(void) {
    if (notify_register_dispatch(MIAFX_NOTIFY_DIAGNOSTICS, &gMIAFXDiagnosticsToken,
                                 dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [[MIAFXProbe sharedProbe] flushImmediately];
    }) != NOTIFY_STATUS_OK) {
        gMIAFXDiagnosticsToken = -1;
    }

    if (notify_register_dispatch(MIAFX_NOTIFY_RESCAN, &gMIAFXRescanToken,
                                 dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [[MIAFXIslandHostBridge sharedBridge] handleImageAdded];
    }) != NOTIFY_STATUS_OK) {
        gMIAFXRescanToken = -1;
    }
}

static void MIAFXUnregisterNotifications(void) {
    if (gMIAFXDiagnosticsToken >= 0) {
        notify_cancel(gMIAFXDiagnosticsToken);
        gMIAFXDiagnosticsToken = -1;
    }
    if (gMIAFXRescanToken >= 0) {
        notify_cancel(gMIAFXRescanToken);
        gMIAFXRescanToken = -1;
    }
}

#pragma mark - Boot guard

static void MIAFXScheduleBootStable(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * (double)NSEC_PER_SEC)),
               dispatch_get_main_queue(), ^{
        MIAFXMarkBootStable();
        [[MIAFXProbe sharedProbe] recordRuntimeStatus:@"boot-stable"];
        [[MIAFXProbe sharedProbe] flushImmediately];
    });
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        if (!MIAFXIsSpringBoardProcess()) {
            return;
        }
        if (!MIAFXIsSupportedSystemVersion()) {
            MIAFXLog(@"系统版本不支持（%@），MIAFX 未启用", MIAFXSystemVersionString());
            return;
        }
        if (!MIAFXBeginBootGuard()) {
            MIAFXLog(@"启动保护已触发，本次启动不加载 MIAFX");
            return;
        }
        gMIAFXBootGuardPassed = YES;

        // .xm 会被 Logos 预处理成 ObjC++，这里用 NULL 而不是 nil，避免 C++ 重载歧义
        MIAFXEnsureDataDirectories(NULL);

        MIAFXConfig *config = [MIAFXConfig sharedConfig];
        [[MIAFXProbe sharedProbe] refreshEnabled];
        [[MIAFXProbe sharedProbe] setValue:MIAFXSystemVersionString() forDiagnosticKey:@"SystemVersion"];
        [[MIAFXProbe sharedProbe] setValue:@(1) forDiagnosticKey:@"SchemaVersion"];
        [[MIAFXProbe sharedProbe] recordRuntimeStatus:@"ctor"];

        [config publishLiveState];
        [config addObserver:^(NSDictionary<NSString *, id> *settings) {
            (void)settings;
            [[MIAFXIslandHostBridge sharedBridge] handleConfigurationReload];
        }];

        MIAFXStateCoordinator *coordinator = [MIAFXStateCoordinator sharedCoordinator];
        coordinator.stateChange = ^(MIAFXRuntimeState state) {
            [[MIAFXIslandHostBridge sharedBridge] handleRuntimeState:state];
        };
        [coordinator start];
        [[MIAFXProbe sharedProbe] setValue:@(coordinator.dashBoardBlankingWindowAvailable)
                        forDiagnosticKey:@"DashBoardBlankingWindowAvailable"];

        // 全局唯一时钟：先取一次，保证 DisplayLink 在需要时立刻可用
        (void)[[MIAFXClock sharedClock] now];

        [[MIAFXIslandHostBridge sharedBridge] registerDelayedDetection];
        MIAFXRegisterNotifications();
        MIAFXScheduleBootStable();

        MIAFXLog(@"MIAFX 已在 SpringBoard(%@) 就绪", MIAFXSystemVersionString());
    }
}

%dtor {
    @autoreleasepool {
        MIAFXUnregisterNotifications();
        [[MIAFXIslandHostBridge sharedBridge] unmount];
        [[MIAFXStateCoordinator sharedCoordinator] stop];
        [[MIAFXClock sharedClock] invalidate];
        (void)gMIAFXBootGuardPassed;
    }
}
