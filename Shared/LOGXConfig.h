//
//  LOGXConfig.h
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  跨进程配置通道：CFPreferences app-id 域（com.loge.islandfx）。
//  沙盒设置进程与系统 SpringBoard 的文件世界不同（RootHide 双 realm），
//  但 cfprefsd 作为代写 broker，两端都能通过 CFPreferences 读写同一份
//  /var/mobile/Library/Preferences/com.loge.islandfx.plist。
//

#import <Foundation/Foundation.h>
#import "LOGXConstants.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - CFPreferences 直连辅助（不经过任何缓存）

void LOGXPrefsSetObject(id value, NSString *key);
void LOGXPrefsRemoveObject(NSString *key);
id LOGXPrefsObject(NSString *key);
void LOGXPrefsSynchronize(void);

#pragma mark - 带默认值的读取

BOOL LOGXConfigBool(NSString *key);
NSInteger LOGXConfigInteger(NSString *key);
double LOGXConfigDouble(NSString *key);
NSString *LOGXConfigString(NSString *key);

/// 设置端专用：写入用户配置并通知插件端重评
void LOGXConfigSetBool(BOOL value, NSString *key);
void LOGXConfigSetInteger(NSInteger value, NSString *key);
void LOGXConfigSetDouble(double value, NSString *key);
void LOGXConfigSetString(NSString *value, NSString *key);

/// 模式键拼接：LOGXModeKey(LOGX_KEY_MODE_ALPHA_FMT, LOGX_MODE_COMPACT)
NSString *LOGXModeKey(NSString *format, NSString *mode);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
