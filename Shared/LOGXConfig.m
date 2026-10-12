#import "LOGXConfig.h"
#import <notify.h>

NSString *const LOGXPrefsAppID = @"com.loge.islandfx";

#pragma mark - CFPreferences 直连

void LOGXPrefsSetObject(id value, NSString *key) {
    if (key.length == 0) return;
    if (value == nil) {
        LOGXPrefsRemoveObject(key);
        return;
    }
    CFPreferencesSetAppValue((CFStringRef)key, (__bridge CFPropertyListRef)value, (CFStringRef)LOGXPrefsAppID);
}

void LOGXPrefsRemoveObject(NSString *key) {
    if (key.length == 0) return;
    CFPreferencesSetAppValue((CFStringRef)key, NULL, (CFStringRef)LOGXPrefsAppID);
}

id LOGXPrefsObject(NSString *key) {
    if (key.length == 0) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)LOGXPrefsAppID);
    if (value == NULL) return nil;
    return CFBridgingRelease(value);   // Copy 系列：交出所有权给 ARC
}

void LOGXPrefsSynchronize(void) {
    CFPreferencesAppSynchronize((CFStringRef)LOGXPrefsAppID);
}

#pragma mark - 带默认值的读取

BOOL LOGXConfigBool(NSString *key) {
    id value = LOGXPrefsObject(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

NSInteger LOGXConfigInteger(NSString *key) {
    id value = LOGXPrefsObject(key);
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

double LOGXConfigDouble(NSString *key) {
    id value = LOGXPrefsObject(key);
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

NSString *LOGXConfigString(NSString *key) {
    id value = LOGXPrefsObject(key);
    return [value isKindOfClass:NSString.class] ? value : @"";
}

#pragma mark - 设置端写入

static void LOGXCommitAndNotify(void) {
    LOGXPrefsSynchronize();
    // 写后读回一次：确认值真的进了共享域（而不是只留在本进程缓存）
    notify_post(LOGX_NOTIFY_RELOAD);
}

void LOGXConfigSetBool(BOOL value, NSString *key) {
    LOGXPrefsSetObject(@(value), key);
    LOGXCommitAndNotify();
}

void LOGXConfigSetInteger(NSInteger value, NSString *key) {
    LOGXPrefsSetObject(@(value), key);
    LOGXCommitAndNotify();
}

void LOGXConfigSetDouble(double value, NSString *key) {
    LOGXPrefsSetObject(@(value), key);
    LOGXCommitAndNotify();
}

void LOGXConfigSetString(NSString *value, NSString *key) {
    LOGXPrefsSetObject(value.length > 0 ? value : @"", key);
    LOGXCommitAndNotify();
}

NSString *LOGXModeKey(NSString *format, NSString *mode) {
    return [NSString stringWithFormat:format, mode];
}
