#import "MIAFXConfig.h"
#import "MIAFXDefaults.h"
#import "MIAFXPath.h"
#import <notify.h>

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
    if (!MIAFXEnsureDataDirectories(error)) return NO;
    NSDictionary *snapshot = [self snapshot];
    BOOL ok = [snapshot writeToURL:[NSURL fileURLWithPath:MIAFXSettingsPath()] error:error];
    if (ok) {
        [self publishLiveState];
        notify_post(MIAFX_NOTIFY_RELOAD);
    }
    return ok;
}

- (void)reload {
    NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile:MIAFXSettingsPath()];
    NSMutableDictionary *merged = [MIAFXDefaultSettings() mutableCopy];
    if ([disk isKindOfClass:NSDictionary.class]) [merged addEntriesFromDictionary:disk];
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
