#import "MIAFXConfig.h"
#import "MIAFXDefaults.h"
#import "MIAFXPath.h"
#import <notify.h>

NSString *const MIAFXPrefsAppID = @"com.loge.islandfx";
NSString *const MIAFXPrefsKeyPendingImports = @"Import.Pending";
NSString *const MIAFXPrefsKeyImportBlobPrefix = @"Import.Blob.";
NSString *const MIAFXPrefsKeyAssetsVideos = @"Assets.Videos";
NSString *const MIAFXPrefsKeyHeartbeat = @"Plugin.Heartbeat";

#pragma mark - CFPreferences 直连辅助（不经过 MIAFXConfig 缓存）

void MIAFXPrefsSetObject(id value, NSString *key) {
    if (key.length == 0) return;
    // nil 视为删除（plist 不能写 null）
    if (value == nil) {
        MIAFXPrefsRemoveObject(key);
        return;
    }
    CFPreferencesSetAppValue((CFStringRef)key, (__bridge CFPropertyListRef)value, (CFStringRef)MIAFXPrefsAppID);
}

void MIAFXPrefsRemoveObject(NSString *key) {
    if (key.length == 0) return;
    CFPreferencesSetAppValue((CFStringRef)key, NULL, (CFStringRef)MIAFXPrefsAppID);
}

id MIAFXPrefsObject(NSString *key) {
    if (key.length == 0) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)MIAFXPrefsAppID);
    if (value == NULL) return nil;
    // Copy 系列：交出所有权给 ARC，避免泄漏
    return CFBridgingRelease(value);
}

NSArray<NSString *> *MIAFXPrefsAllKeys(void) {
    CFArrayRef keys = CFPreferencesCopyKeyList((CFStringRef)MIAFXPrefsAppID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys == NULL) return @[];
    NSArray *result = [(__bridge NSArray *)keys copy];
    CFRelease(keys);
    return result;
}

void MIAFXPrefsSynchronize(void) {
    CFPreferencesAppSynchronize((CFStringRef)MIAFXPrefsAppID);
}

@interface MIAFXConfig ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *values;
@property (nonatomic, strong) NSMutableArray<MIAFXConfigObserver> *observers;
@property (nonatomic) int reloadToken;
@property (nonatomic) int liveToken;
@end

@implementation MIAFXConfig

+ (instancetype)sharedConfig {
    static MIAFXConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [MIAFXConfig new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _values = [MIAFXDefaultSettings() mutableCopy];
    _observers = [NSMutableArray array];
    _reloadToken = -1;
    _liveToken = -1;
    [self reload];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(MIAFX_NOTIFY_RELOAD, &_reloadToken, dispatch_get_main_queue(), ^(__unused int token) {
        [weakSelf reload];
    });
    notify_register_check(MIAFX_NOTIFY_FEATURE_STATE, &_liveToken);
    return self;
}

- (NSDictionary<NSString *,id> *)snapshot {
    @synchronized (self) { return [self.values copy]; }
}

- (id)objectForKey:(NSString *)key {
    @synchronized (self) { return self.values[key] ?: MIAFXDefaultValue(key); }
}

- (BOOL)boolForKey:(NSString *)key { return [[self objectForKey:key] boolValue]; }
- (NSInteger)integerForKey:(NSString *)key { return [[self objectForKey:key] integerValue]; }
- (double)doubleForKey:(NSString *)key { return [[self objectForKey:key] doubleValue]; }
- (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : [value description] ?: @"";
}

- (void)setObject:(id)object forKey:(NSString *)key {
    if (key.length == 0) return;
    @synchronized (self) {
        if (object) self.values[key] = object;
        else [self.values removeObjectForKey:key];
    }
}

- (BOOL)save:(NSError **)error {
    NSDictionary *snapshot = [self snapshot];
    @synchronized (self) {
        for (NSString *key in snapshot) {
            // 素材投递/清单/心跳由插件端独占维护，设置端不回写（否则会把插件刚发布的新值覆盖成旧快照）
            if ([key hasPrefix:@"Import."] || [key hasPrefix:@"Assets."] || [key hasPrefix:@"Plugin."]) continue;
            id value = snapshot[key];
            if (value == nil) {
                CFPreferencesSetAppValue((CFStringRef)key, NULL, (CFStringRef)MIAFXPrefsAppID);
            } else {
                CFPreferencesSetAppValue((CFStringRef)key, (__bridge CFPropertyListRef)value, (CFStringRef)MIAFXPrefsAppID);
            }
        }
    }
    Boolean ok = CFPreferencesAppSynchronize((CFStringRef)MIAFXPrefsAppID);
    // 保留文件写入（仅调试/兜底，不再是跨进程通道）
    MIAFXEnsureDataDirectories(nil);
    [snapshot writeToURL:[NSURL fileURLWithPath:MIAFXSettingsPath()] error:nil];
    if (ok) {
        [self publishLiveState];
        notify_post(MIAFX_NOTIFY_RELOAD);
    }
    return ok ? YES : NO;
}

- (void)reload {
    NSMutableDictionary *merged = [MIAFXDefaultSettings() mutableCopy];

    // 1) CFPreferences 域：跨进程主通道，优先级最高
    NSArray<NSString *> *cfKeys = MIAFXPrefsAllKeys();
    for (NSString *key in cfKeys) {
        id value = MIAFXPrefsObject(key);
        if (value != nil) merged[key] = value;
    }

    // 2) 兼容旧版：仅当 CFPreferences 域为空（首次迁移）时才采用 jbroot 文件里的值
    if (cfKeys.count == 0) {
        NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:MIAFXSettingsPath()];
        if ([disk isKindOfClass:NSDictionary.class]) [merged addEntriesFromDictionary:disk];
    }

    @synchronized (self) { self.values = merged; }
    NSArray<MIAFXConfigObserver> *callbacks;
    @synchronized (self) { callbacks = [self.observers copy]; }
    NSDictionary *snapshot = [self snapshot];
    for (MIAFXConfigObserver callback in callbacks) callback(snapshot);
}

- (void)addObserver:(MIAFXConfigObserver)observer {
    if (!observer) return;
    @synchronized (self) { [self.observers addObject:[observer copy]]; }
}

- (void)publishLiveState {
    if (self.liveToken < 0) return;
    uint64_t state = MIAFX_FEATURE_VALID_BIT;
    if ([self boolForKey:@"Global.Enabled"]) state |= MIAFX_FEATURE_MASTER_BIT;
    state |= (uint32_t)[self integerForKey:@"Global.FeatureMask"];
    notify_set_state(self.liveToken, state);
    notify_post(MIAFX_NOTIFY_FEATURE_STATE);
    int audioToken = -1;
    if (notify_register_check(MIAFX_NOTIFY_AUDIO_ENABLED, &audioToken) == NOTIFY_STATUS_OK) {
        BOOL audio = [self boolForKey:@"Global.Enabled"] && [self isFeatureEnabled:MIAFXFeatureSpectrum];
        notify_set_state(audioToken, audio ? 1 : 0);
        notify_post(MIAFX_NOTIFY_AUDIO_ENABLED);
        notify_cancel(audioToken);
    }
}

- (uint32_t)liveFeatureMask {
    uint64_t state = 0;
    if (self.liveToken >= 0 && notify_get_state(self.liveToken, &state) == NOTIFY_STATUS_OK && (state & MIAFX_FEATURE_VALID_BIT)) {
        if (!(state & MIAFX_FEATURE_MASTER_BIT)) return 0;
        return (uint32_t)(state & 0xffffffffu);
    }
    if (![self boolForKey:@"Global.Enabled"]) return 0;
    return (uint32_t)[self integerForKey:@"Global.FeatureMask"];
}

- (BOOL)isFeatureEnabled:(MIAFXFeature)feature { return ([self liveFeatureMask] & feature) != 0; }

- (void)dealloc {
    if (_reloadToken >= 0) notify_cancel(_reloadToken);
    if (_liveToken >= 0) notify_cancel(_liveToken);
}

@end
