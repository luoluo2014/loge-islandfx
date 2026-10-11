#import <Foundation/Foundation.h>
#import "MIAFXConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^MIAFXConfigObserver)(NSDictionary<NSString *, id> *settings);

@interface MIAFXConfig : NSObject
+ (instancetype)sharedConfig;
- (NSDictionary<NSString *, id> *)snapshot;
- (id _Nullable)objectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (void)setObject:(id _Nullable)object forKey:(NSString *)key;
- (BOOL)save:(NSError **)error;
- (void)reload;
- (void)addObserver:(MIAFXConfigObserver)observer;
- (void)publishLiveState;
- (uint32_t)liveFeatureMask;
- (BOOL)isFeatureEnabled:(MIAFXFeature)feature;
@end

NS_ASSUME_NONNULL_END
