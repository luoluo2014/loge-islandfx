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

BOOL MIAFXBeginBootGuard(void) {
    MIAFXEnsureDataDirectories(nil);
    NSMutableDictionary *state = [[NSDictionary dictionaryWithContentsOfFile:MIAFXPanicPath()] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSInteger attempts = [state[@"Attempts"] integerValue] + 1;
    state[@"Attempts"] = @(attempts);
    state[@"LastStart"] = @([[NSDate date] timeIntervalSince1970]);
    [state writeToFile:MIAFXPanicPath() atomically:YES];
    if (attempts >= 3) {
        MIAFXLog(@"启动保护已触发：连续启动次数 %ld", (long)attempts);
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
