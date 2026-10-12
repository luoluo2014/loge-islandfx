//
//  LOGXLog.h
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  诊断日志：常开，512KB 轮转，写入 Logs/video-diag.log。
//  插件端同时把日志尾部经 CFPreferences（Logs.Tail）发布给设置端展示，
//  用户出问题时可直接在设置里复制全文反馈。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// 常规日志（os_log + 诊断文件）
void LOGXDiag(NSString *format, ...);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
