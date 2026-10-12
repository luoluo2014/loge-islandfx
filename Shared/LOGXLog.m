#import "LOGXLog.h"
#import "LOGXPath.h"
#import <os/log.h>

static const NSUInteger kLOGXDiagMaxBytes = 512 * 1024;

void LOGXDiag(NSString *format, ...) {
    if (format.length == 0) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[灵动岛] %{public}s", message.UTF8String);

    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.loge.islandfx.diag", DISPATCH_QUEUE_SERIAL);
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    dispatch_async(queue, ^{
        LOGXEnsureDataDirectories(nil);
        NSString *path = LOGXLogPath();
        NSFileManager *manager = NSFileManager.defaultManager;
        BOOL exists = [manager fileExistsAtPath:path];
        if (exists) {
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
            if ([attributes[NSFileSize] unsignedIntegerValue] >= kLOGXDiagMaxBytes) {
                // 轮转：保留最后 64KB 作为新文件开头
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
