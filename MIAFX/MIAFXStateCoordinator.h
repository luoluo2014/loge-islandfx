//
//  MIAFXStateCoordinator.h
//  MIAFX
//
//  监听 SpringBoard 的 hasBlankedScreen / displayStatus / lockstate，
//  在 AOD、息屏、锁屏、岛隐藏时统一通知渲染器暂停。
//  SBDashBoardBlankingWindow 只做“存在性”诊断，不去 hook 它。
//

#import <Foundation/Foundation.h>

#import "MIAFXConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^MIAFXStateCoordinatorChange)(MIAFXRuntimeState state);

@interface MIAFXStateCoordinator : NSObject

+ (instancetype)sharedCoordinator;

@property (nonatomic, copy, nullable) MIAFXStateCoordinatorChange stateChange;

@property (nonatomic, readonly) MIAFXRuntimeState state;
@property (nonatomic, readonly) BOOL screenBlanked;
@property (nonatomic, readonly) BOOL deviceLocked;
@property (nonatomic, readonly) NSString *displayStatus;
/// SBDashBoardBlankingWindow 是否存在（仅诊断，不 hook）
@property (nonatomic, readonly) BOOL dashBoardBlankingWindowAvailable;

/// 由 IslandHostBridge 告知岛是否可见
@property (nonatomic) BOOL islandVisible;

- (void)start;
- (void)stop;

/// 把状态转成可写入诊断的可读字符串
+ (NSString *)nameForState:(MIAFXRuntimeState)state;

@end

NS_ASSUME_NONNULL_END
