#import "MIAFXSafe.h"
#import "MIAFXPath.h"
#import "MIAFXLog.h"

static NSMutableDictionary<NSString *, NSNumber *> *gFailures;
static dispatch_queue_t gFailureQueue;

static void MIAFXEnsureFailureState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gFailures = [NSMutableDictionary dictionary];
        gFailureQueue = dispatch_queue_create("com.loge.islandfx.failures", DISPATCH_QUEUE_SERIAL);
    });
}

/// 启动保护：只识别真正的崩溃循环。
/// 旧实现按累计次数拦截，一旦达到阈值，插件因不加载而永远无法标记稳定，
/// 形成死锁（用户手动 respring 几次后插件被永久禁用）。
/// 新实现：只统计最近 kMIAFXBootWindow 秒内的启动次数，达到阈值才拦截；
/// 手动 respring（通常间隔远大于窗口）不会累积，崩溃循环（秒级重启）仍会被捕获。
static const NSTimeInterval kMIAFXBootWindow = 300.0;
static const NSInteger kMIAFXBootLoopThreshold = 4;

BOOL MIAFXBeginBootGuard(void) {
    MIAFXEnsureDataDirectories(nil);
    NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:MIAFXPanicPath()] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval lastStart = [state[@"LastStart"] doubleValue];
    NSInteger attempts = [state[@"Attempts"] integerValue];
    if (lastStart <= 0.0 || (now - lastStart) > kMIAFXBootWindow) {
        attempts = 1;   // 距上次启动太久：视为一次全新的正常启动
    } else {
        attempts += 1;
    }
    state[@"Attempts"] = @(attempts);
    state[@"LastStart"] = @(now);
    [state writeToFile:MIAFXPanicPath() atomically:YES];
    if (attempts >= kMIAFXBootLoopThreshold) {
        MIAFXLog(@"启动保护已触发：%ld 秒内连续启动 %ld 次，判定为崩溃循环", (long)kMIAFXBootWindow, (long)attempts);
        return NO;
    }
    return YES;
}

void MIAFXMarkBootStable(void) {
    NSDictionary *state = @{ @"Attempts": @0, @"LastStable": @([[NSDate date] timeIntervalSince1970]) };
    MIAFXEnsureDataDirectories(nil);
    [state writeToFile:MIAFXPanicPath() atomically:YES];
}

void MIAFXResetBootGuard(void) {
    MIAFXEnsureDataDirectories(nil);
    [@{ @"Attempts": @0, @"ResetAt": @([[NSDate date] timeIntervalSince1970]) } writeToFile:MIAFXPanicPath() atomically:YES];
}

BOOL MIAFXRecordModuleFailure(NSString *module) {
    if (module.length == 0) return NO;
    MIAFXEnsureFailureState();
    __block BOOL disabled = NO;
    dispatch_sync(gFailureQueue, ^{
        NSInteger count = [gFailures[module] integerValue] + 1;
        gFailures[module] = @(count);
        disabled = count >= 3;
    });
    return disabled;
}

BOOL MIAFXIsModuleDisabled(NSString *module) {
    if (module.length == 0) return NO;
    MIAFXEnsureFailureState();
    __block BOOL disabled = NO;
    dispatch_sync(gFailureQueue, ^{ disabled = [gFailures[module] integerValue] >= 3; });
    return disabled;
}
