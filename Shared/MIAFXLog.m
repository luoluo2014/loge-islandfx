#import "MIAFXLog.h"
#import "MIAFXConfig.h"
#import "MIAFXPath.h"
#import <os/log.h>

void MIAFXLogMessage(NSString *format, ...) {
    if (format.length == 0) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[MIAFX] %{public}s", message.UTF8String);
    if (![[MIAFXConfig sharedConfig] boolForKey:@"Global.DebugLog"]) return;
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.loge.islandfx.log", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        MIAFXEnsureDataDirectories(nil);
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = MIAFXLogPath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    });
}

void MIAFXLogError(NSString *module, NSException *exception, NSString *detail) {
    MIAFXLogMessage(@"[%@] %@%@", module ?: @"Unknown", detail ?: @"异常", exception ? [NSString stringWithFormat:@": %@", exception.reason] : @"");
}

static const NSUInteger kMIAFXDiagMaxBytes = 512 * 1024;

void MIAFXDiagLog(NSString *format, ...) {
    if (format.length == 0) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[MIAFX-DIAG] %{public}s", message.UTF8String);
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ queue = dispatch_queue_create("com.loge.islandfx.diag", DISPATCH_QUEUE_SERIAL); });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    dispatch_async(queue, ^{
        MIAFXEnsureDataDirectories(nil);
        NSString *path = MIAFXVideoDiagPath();
        NSFileManager *manager = [NSFileManager defaultManager];
        BOOL exists = [manager fileExistsAtPath:path];
        if (exists) {
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
            if ([attributes[NSFileSize] unsignedIntegerValue] >= kMIAFXDiagMaxBytes) {
                // 轮转：保留最后 64KB 作为新文件开头，避免无限增长
                NSFileHandle *reader = [NSFileHandle fileHandleForReadingAtPath:path];
                [reader seekToFileOffset:([attributes[NSFileSize] unsignedIntegerValue] - 64 * 1024)];
                NSData *tail = [reader readDataToEndOfFile];
                [reader closeFile];
                [manager removeItemAtPath:path error:nil];
                exists = NO;
                if (tail.length > 0) {
                    NSMutableData *seed = [NSMutableData dataWithData:[@"--- rotated ---\n" dataUsingEncoding:NSUTF8StringEncoding]];
                    [seed appendData:tail];
                    [manager createFileAtPath:path contents:seed attributes:nil];
                    exists = YES;
                }
            }
        }
        if (!exists) {
            [manager createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    });
}
