//
//  LOGXConstants.h
//  LogeIsland — 落格Loge·灵动岛 v2.0
//
//  包级常量：版本、通知名、配置键。设置端（沙盒 Preferences）与插件端
//  （SpringBoard）共享本文件，保证键名永远一致。
//

#ifndef LOGX_CONSTANTS_H
#define LOGX_CONSTANTS_H

#include <stdint.h>

#define LOGX_PACKAGE_ID "com.loge.islandfx"
#define LOGX_PLUGIN_VERSION_STRING @"2.0.14"

/// 配置变更通知：设置端写入后投递，插件端立即重新评估（5 秒轮询之外的加速通道）
#define LOGX_NOTIFY_RELOAD "com.loge.islandfx.reload"

/// 注销前置通知：设置端执行注销前投递，插件端立即停止全部渲染，
/// 避免 SpringBoard 重载期间出现半死状态（黑屏恢复过程的保险丝）
#define LOGX_NOTIFY_SUSPEND "com.loge.islandfx.suspend"

#pragma mark - 用户配置键（CFPreferences app-id 域，两端直读直写）

#define LOGX_KEY_ENABLED              @"Enabled"               // 总开关
#define LOGX_KEY_MODE_ENABLED_FMT     @"%@.Enabled"            // 模式开关（%@ = Compact/Expanded）
#define LOGX_KEY_MODE_PATH_FMT        @"%@.Path"               // 背景视频文件名
#define LOGX_KEY_MODE_FILL_FMT        @"%@.FillMode"           // 填充模式 0 适应 / 1 填充 / 2 拉伸
#define LOGX_KEY_MODE_ALPHA_FMT       @"%@.Alpha"              // 透明度 0.2 ~ 1.0
#define LOGX_KEY_MODE_SCALE_FMT       @"%@.Scale"              // 缩放 0.5 ~ 1.5
#define LOGX_KEY_MODE_OFFSETX_FMT     @"%@.OffsetX"            // 水平偏移 -40 ~ 40
#define LOGX_KEY_MODE_OFFSETY_FMT     @"%@.OffsetY"            // 垂直偏移 -40 ~ 40
#define LOGX_KEY_MODE_CORNER_FMT      @"%@.CornerMode"         // 圆角模式 0 直角 / 1 跟随 / 2 自定义
#define LOGX_KEY_MODE_RADIUS_FMT      @"%@.CornerRadius"       // 自定义圆角半径 0 ~ 60

#define LOGX_MODE_COMPACT   @"Compact"     // 未展开（待机）状态
#define LOGX_MODE_EXPANDED  @"Expanded"    // 长按展开状态

#pragma mark - 投递 / 心跳 / 日志键（插件端独占维护，设置端只读或只写请求）

#define LOGX_KEY_PENDING_IMPORTS  @"Import.Pending"        // 待落地视频文件名队列
#define LOGX_KEY_IMPORT_BLOB_FMT  @"Import.Blob.%@"
#define LOGX_KEY_DELETE_FMT       @"Import.Delete.%@"
#define LOGX_KEY_DELETE_QUEUE     @"Import.Delete.Queue"   // 待删除文件名队列（避免 CopyKeyList 遍历崩溃）
#define LOGX_KEY_ASSETS_VIDEOS    @"Assets.Videos"         // 插件发布的素材清单
#define LOGX_KEY_HEARTBEAT        @"Plugin.Heartbeat"      // 插件心跳（版本/pid/目录/暂停态）
#define LOGX_KEY_RESUME_REQUEST   @"Plugin.ResumeRequest"  // 设置端请求恢复启用
#define LOGX_KEY_LOG_TAIL         @"Logs.Tail"             // 诊断日志尾部（设置端展示用）
#define LOGX_KEY_LOG_SIZE         @"Logs.Size"
#define LOGX_KEY_LOG_CLEAR_REQ    @"Logs.ClearRequest"     // 设置端请求清空日志
#define LOGX_KEY_INTENTIONAL_RESPRING @"Plugin.IntentionalRespring"  // 设置端注销前置标记：告知插件端这是用户主动重启，清零崩溃循环计数

#pragma mark - 默认值（两端保持一致）

#define LOGX_DEFAULT_FILL_MODE      1      // 填充
#define LOGX_DEFAULT_ALPHA          1.0
#define LOGX_DEFAULT_SCALE          1.0
#define LOGX_DEFAULT_OFFSET         0.0
#define LOGX_DEFAULT_CORNER_MODE    1      // 跟随
#define LOGX_DEFAULT_CORNER_RADIUS  24.0

#endif
