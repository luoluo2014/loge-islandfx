//
//  MIAFXStateCoordinator.m
//  MIAFX
//

#import "MIAFXStateCoordinator.h"

#import <mach/mach.h>
#import <notify.h>
#import <objc/runtime.h>

#import "MIAFXLog.h"
#import "MIAFXProbe.h"
#import "MIAFXSafe.h"
#import "MIAFXSafeInline.h"

static const char * const kMIAFXNotifyHasBlankedScreen = "com.apple.springboard.hasBlankedScreen";
static const char * const kMIAFXNotifyDisplayStatus = "com.apple.springboard.displayStatus";
static const char * const kMIAFXNotifyLockState = "com.apple.springboard.lockstate";

/// 读取 notify state；读取失败时 outState 不变，返回 NO。
static BOOL MIAFXNotifyReadState(int token, uint64_t *outState) {
    if (token < 0 || !outState) {
        return NO;
    }
    uint64_t value = 0;
    if (notify_get_state(token, &value) != NOTIFY_STATUS_OK) {
        return NO;
    }
    *outState = value;
    return YES;
}

/// displayStatus 在不同系统版本上可能以整数、也可能以 C 字符串指针形式下发。
/// 这里用 vm_read_overwrite 做一次安全拷贝，避免直接解引用未知地址。
static NSString * _Nullable MIAFXNotifyStateString(int token) {
    uint64_t raw = 0;
    if (!MIAFXNotifyReadState(token, &raw)) {
        return nil;
    }
    if (raw <= 1) {
        return raw ? @"1" : @"0";
    }
    char buffer[64];
    memset(buffer, 0, sizeof(buffer));
    /* 必须是 vm_size_t：内核会按 8 字节写入，用 32 位变量会破坏栈。 */
    vm_size_t outSize = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(),
                                            (vm_address_t)raw,
                                            (vm_size_t)(sizeof(buffer) - 1),
                                            (vm_address_t)buffer,
                                            &outSize);
    if (result != KERN_SUCCESS || outSize == 0 || outSize >= sizeof(buffer)) {
        return nil;
    }
    buffer[sizeof(buffer) - 1] = '\0';
    NSString *candidate = [[NSString alloc] initWithUTF8String:buffer];
    if (candidate.length == 0) {
        return nil;
    }
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger index = 0; index < candidate.length; index++) {
        if (![allowed characterIsMember:[candidate characterAtIndex:index]]) {
            return nil;
        }
    }
    return candidate;
}

@interface MIAFXStateCoordinator ()
@property (nonatomic) MIAFXRuntimeState state;
@property (nonatomic) BOOL screenBlanked;
@property (nonatomic) BOOL deviceLocked;
@property (nonatomic, copy) NSString *displayStatus;
@property (nonatomic) BOOL dashBoardBlankingWindowAvailable;
@property (nonatomic, getter=isRunning) BOOL running;
@property (nonatomic) int blankToken;
@property (nonatomic) int displayToken;
@property (nonatomic) int lockToken;
@end

@implementation MIAFXStateCoordinator

+ (instancetype)sharedCoordinator {
    static MIAFXStateCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [[MIAFXStateCoordinator alloc] init];
    });
    return coordinator;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _state = MIAFXRuntimeBoot;
    _screenBlanked = NO;
    _deviceLocked = NO;
    _displayStatus = @"";
    _islandVisible = YES;
    _blankToken = -1;
    _displayToken = -1;
    _lockToken = -1;
    _dashBoardBlankingWindowAvailable = (objc_getClass("SBDashBoardBlankingWindow") != Nil);
    return self;
}

+ (NSString *)nameForState:(MIAFXRuntimeState)state {
    switch (state) {
        case MIAFXRuntimeBoot: return @"Boot";
        case MIAFXRuntimeActive: return @"Active";
        case MIAFXRuntimeDimmed: return @"Dimmed";
        case MIAFXRuntimeScreenOff: return @"ScreenOff";
        case MIAFXRuntimeIslandHidden: return @"IslandHidden";
        case MIAFXRuntimeSuspended: return @"Suspended";
    }
    return @"Unknown";
}

- (void)start {
    if (self.running) {
        return;
    }
    self.running = YES;

    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_get_main_queue();

    if (notify_register_dispatch(kMIAFXNotifyHasBlankedScreen, &_blankToken, queue, ^(int token) {
        (void)token;
        [weakSelf refresh];
    }) != NOTIFY_STATUS_OK) {
        self.blankToken = -1;
    }

    if (notify_register_dispatch(kMIAFXNotifyDisplayStatus, &_displayToken, queue, ^(int token) {
        (void)token;
        [weakSelf refresh];
    }) != NOTIFY_STATUS_OK) {
        self.displayToken = -1;
    }

    if (notify_register_dispatch(kMIAFXNotifyLockState, &_lockToken, queue, ^(int token) {
        (void)token;
        [weakSelf refresh];
    }) != NOTIFY_STATUS_OK) {
        self.lockToken = -1;
    }

    [self refresh];
}

- (void)stop {
    if (!self.running) {
        return;
    }
    self.running = NO;
    if (self.blankToken >= 0) {
        notify_cancel(self.blankToken);
        self.blankToken = -1;
    }
    if (self.displayToken >= 0) {
        notify_cancel(self.displayToken);
        self.displayToken = -1;
    }
    if (self.lockToken >= 0) {
        notify_cancel(self.lockToken);
        self.lockToken = -1;
    }
}

- (void)setIslandVisible:(BOOL)islandVisible {
    if (_islandVisible == islandVisible) {
        return;
    }
    _islandVisible = islandVisible;
    [self refresh];
}

- (void)refresh {
    MIAFXRunProtected(@"StateCoordinator", ^{
        uint64_t blanked = 0;
        uint64_t locked = 0;
        BOOL hasBlanked = MIAFXNotifyReadState(self.blankToken, &blanked);
        BOOL hasLocked = MIAFXNotifyReadState(self.lockToken, &locked);
        NSString *display = MIAFXNotifyStateString(self.displayToken);

        BOOL blankedOn = hasBlanked && blanked != 0;
        BOOL lockedOn = hasLocked && locked != 0;
        BOOL displayOff = NO;
        if (display.length > 0) {
            NSString *lowercase = display.lowercaseString;
            displayOff = [lowercase isEqualToString:@"lock"] ||
                         [lowercase isEqualToString:@"off"] ||
                         [lowercase isEqualToString:@"0"];
        }

        self.screenBlanked = blankedOn;
        self.deviceLocked = lockedOn;
        self.displayStatus = display ?: @"";

        MIAFXRuntimeState next = MIAFXRuntimeActive;
        if (blankedOn || displayOff) {
            next = MIAFXRuntimeScreenOff;
        } else if (lockedOn) {
            next = MIAFXRuntimeDimmed;
        } else if (!self.islandVisible) {
            next = MIAFXRuntimeIslandHidden;
        }

        if (next != self.state) {
            self.state = next;
            MIAFXLog(@"运行时状态切换 -> %@", [MIAFXStateCoordinator nameForState:next]);
            [[MIAFXProbe sharedProbe] recordRuntimeStatus:[NSString stringWithFormat:@"state:%@",
                                                           [MIAFXStateCoordinator nameForState:next]]];
            [[MIAFXProbe sharedProbe] flush];
            MIAFXStateCoordinatorChange change = self.stateChange;
            if (change) {
                @try {
                    change(next);
                } @catch (NSException *exception) {
                    MIAFXLogError(@"StateCoordinator", exception, @"状态回调异常");
                }
            }
        }
    });
}

- (void)dealloc {
    [self stop];
}

@end
