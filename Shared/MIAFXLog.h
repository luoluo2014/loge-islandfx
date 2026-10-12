#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void MIAFXLogMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT void MIAFXLogError(NSString *module, NSException * _Nullable exception, NSString *detail);

/// 常开诊断日志：不受 Global.DebugLog 限制，始终写入 MIAFXVideoDiagPath()（512KB 轮转），
/// 同时输出到 os_log（Console / idevicesyslog 可见）。用于线上问题定位。
FOUNDATION_EXPORT void MIAFXDiagLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#define MIAFXLog(fmt, ...) MIAFXLogMessage((fmt), ##__VA_ARGS__)
#define MIAFXDiag(fmt, ...) MIAFXDiagLog((fmt), ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
