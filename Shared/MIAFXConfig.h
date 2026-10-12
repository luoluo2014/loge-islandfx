#import <Foundation/Foundation.h>
#import "MIAFXConstants.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^MIAFXConfigObserver)(NSDictionary<NSString *, id> *settings);

/// CFPreferences app-id 域（跨进程主通道）。
/// 设置 App（沙盒内）写入 → cfprefsd 落到真实 /var/mobile/Library/Preferences/com.loge.islandfx.plist
/// → SpringBoard 插件读取同一域。这是 RootHide 下唯一被验证可用的跨进程配置通道。
FOUNDATION_EXPORT NSString *const MIAFXPrefsAppID;

FOUNDATION_EXPORT void MIAFXPrefsSetObject(id _Nullable value, NSString *key);
FOUNDATION_EXPORT void MIAFXPrefsRemoveObject(NSString *key);
FOUNDATION_EXPORT id _Nullable MIAFXPrefsObject(NSString *key);
FOUNDATION_EXPORT NSArray<NSString *> *MIAFXPrefsAllKeys(void);
FOUNDATION_EXPORT void MIAFXPrefsSynchronize(void);

/// 素材投递协议（视频文件经 CFPreferences 暂存，由插件端落入真实目录）
FOUNDATION_EXPORT NSString *const MIAFXPrefsKeyPendingImports;   // NSArray<NSString *> 待投递文件名
FOUNDATION_EXPORT NSString *const MIAFXPrefsKeyImportBlobPrefix; // "Import.Blob." + 文件名 → NSData
FOUNDATION_EXPORT NSString *const MIAFXPrefsKeyAssetsVideos;     // NSArray<NSDictionary{name,size}> 插件端发布的素材清单
FOUNDATION_EXPORT NSString *const MIAFXPrefsKeyHeartbeat;        // NSDictionary{at,version,pid} 插件端心跳（证明插件存活且在读同一域）

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
