//
//  MIAFXProbe.m
//  MIAFX
//

#import "MIAFXProbe.h"

#import "MIAFXConfig.h"
#import "MIAFXLog.h"
#import "MIAFXPath.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

@interface MIAFXProbe ()
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *store;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *classes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *methods;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *native;
@property (nonatomic, strong) NSMutableArray<NSString *> *runtimeLog;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic) NSTimeInterval lastFlush;
@end

@implementation MIAFXProbe

+ (instancetype)sharedProbe {
    static MIAFXProbe *probe;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        probe = [[MIAFXProbe alloc] init];
    });
    return probe;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _store = [NSMutableDictionary dictionary];
    _classes = [NSMutableDictionary dictionary];
    _methods = [NSMutableDictionary dictionary];
    _native = [NSMutableDictionary dictionary];
    _runtimeLog = [NSMutableArray array];
    _queue = dispatch_queue_create("com.loge.islandfx.probe", DISPATCH_QUEUE_SERIAL);
    _lastFlush = 0.0;
    _enabled = NO;
    return self;
}

- (void)refreshEnabled {
    BOOL enabled = [[MIAFXConfig sharedConfig] boolForKey:@"Global.DebugLog"];
    if (enabled == self.enabled) {
        return;
    }
    self.enabled = enabled;
    MIAFXLog(@"诊断探针 %@", enabled ? @"已开启" : @"已关闭");
    if (enabled) {
        [self flushImmediately];
    }
}

- (void)recordClassPresence:(NSString *)className exists:(BOOL)exists {
    if (className.length == 0 || !self.enabled) {
        return;
    }
    dispatch_async(self.queue, ^{
        self.classes[className] = @(exists);
    });
}

- (void)recordMethodList:(NSArray<NSString *> *)methods forClass:(NSString *)className {
    if (className.length == 0 || !self.enabled) {
        return;
    }
    NSArray<NSString *> *copy = [methods copy] ?: @[];
    dispatch_async(self.queue, ^{
        self.methods[className] = copy;
    });
}

- (void)recordHostKind:(NSString *)kind
              expanded:(BOOL)expanded
                bounds:(CGRect)bounds
            layoutMode:(NSInteger)layoutMode
         mountStrategy:(NSString *)strategy {
    if (!self.enabled) {
        return;
    }
    NSDictionary *payload = @{
        @"Kind": kind ?: @"Unknown",
        @"Expanded": @(expanded),
        @"Bounds": NSStringFromCGRect(bounds),
        @"LayoutMode": @(layoutMode),
        @"Strategy": strategy ?: @"none"
    };
    dispatch_async(self.queue, ^{
        self.store[@"Host"] = payload;
    });
}

- (void)recordNativeMatchForSlot:(NSString *)slot
                       className:(NSString * _Nullable)className
                         matched:(BOOL)matched {
    if (slot.length == 0 || !self.enabled) {
        return;
    }
    NSDictionary *payload = @{
        @"ClassName": className ?: @"",
        @"Matched": @(matched)
    };
    dispatch_async(self.queue, ^{
        self.native[slot] = payload;
    });
}

- (void)recordRuntimeStatus:(NSString *)status {
    if (status.length == 0 || !self.enabled) {
        return;
    }
    dispatch_async(self.queue, ^{
        [self.runtimeLog addObject:status];
        while (self.runtimeLog.count > 40) {
            [self.runtimeLog removeObjectAtIndex:0];
        }
    });
}

- (void)setValue:(id _Nullable)value forDiagnosticKey:(NSString *)key {
    if (key.length == 0 || !self.enabled) {
        return;
    }
    dispatch_async(self.queue, ^{
        if (value) {
            self.store[key] = value;
        } else {
            [self.store removeObjectForKey:key];
        }
    });
}

- (void)flush {
    if (!self.enabled) {
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (self.lastFlush > 0.0 && (now - self.lastFlush) < 1.0) {
        return;
    }
    self.lastFlush = now;
    [self flushImmediately];
}

- (void)flushImmediately {
    if (!self.enabled) {
        return;
    }
    dispatch_async(self.queue, ^{
        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"GeneratedAt"] = @([[NSDate date] timeIntervalSince1970]);
        payload[@"Process"] = [[NSProcessInfo processInfo] processName];
        payload[@"SystemVersion"] = [[UIDevice currentDevice] systemVersion];
        payload[@"Classes"] = [self.classes copy];
        payload[@"Methods"] = [self.methods copy];
        payload[@"NativeElements"] = [self.native copy];
        payload[@"RuntimeLog"] = [self.runtimeLog copy];
        [payload addEntriesFromDictionary:[self.store copy]];

        MIAFXRunProtected(@"Probe", ^{
            MIAFXEnsureDataDirectories(nil);
            NSString *path = MIAFXDiagnosticsPath();
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                      format:NSPropertyListBinaryFormat_v1_0
                                                                     options:0
                                                                       error:nil];
            BOOL ok = NO;
            if (data.length > 0) {
                ok = [data writeToFile:path atomically:YES];
            }
            if (!ok) {
                [[payload copy] writeToFile:path atomically:YES];
            }
        });
    });
}

- (void)reset {
    dispatch_async(self.queue, ^{
        [self.store removeAllObjects];
        [self.classes removeAllObjects];
        [self.methods removeAllObjects];
        [self.native removeAllObjects];
        [self.runtimeLog removeAllObjects];
    });
}

@end
