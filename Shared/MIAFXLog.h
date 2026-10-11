#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void MIAFXLogMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
FOUNDATION_EXPORT void MIAFXLogError(NSString *module, NSException * _Nullable exception, NSString *detail);

#define MIAFXLog(fmt, ...) MIAFXLogMessage((fmt), ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
