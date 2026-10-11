//
//  MIAFXClock.h
//  MIAFX
//
//  全局唯一的动画时钟。所有特效（呼吸 / 流光 / 轨道 / 元球 / 频谱）
//  都不自行创建 CADisplayLink，统一向 MIAFXClock 订阅 tick，
//  这样屏幕熄灭时可以一次性停掉全部动画。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// tick 回调。timestamp 为 CACurrentMediaTime() 基准的单调递增时间，
/// delta 为距离上一次投递给该订阅者的时间增量（秒）。
typedef void (^MIAFXClockTick)(NSTimeInterval timestamp, NSTimeInterval delta);

@interface MIAFXClock : NSObject

+ (instancetype)sharedClock;

/// 当前时间（CACurrentMediaTime 基准）
- (NSTimeInterval)now;

/// 以 60fps 订阅，返回 token，token 为 0 表示失败
- (NSUInteger)subscribe:(MIAFXClockTick)block;

/// 以指定帧率订阅（内部做跳帧，不会真的把 DisplayLink 拆成多条）
- (NSUInteger)subscribeWithFPS:(double)fps block:(MIAFXClockTick)block;

/// 修改已存在订阅者的帧率（用于配置热更新 / 性能降级）
- (void)setFPS:(double)fps forToken:(NSUInteger)token;

- (void)unsubscribe:(NSUInteger)token;

/// 暂停 / 恢复整条 DisplayLink
- (void)setPaused:(BOOL)paused;
- (BOOL)isPaused;

/// 彻底销毁 DisplayLink 与全部订阅（tweak 卸载时调用）
- (void)invalidate;

/// 订阅者数量（诊断用）
@property (nonatomic, readonly) NSUInteger subscriberCount;

@end

NS_ASSUME_NONNULL_END
