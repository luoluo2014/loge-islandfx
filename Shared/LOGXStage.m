//
//  LOGXStage.m
//  LogeIsland — 落格Loge·灵动岛
//
//  崩溃定位打点：POSIX open/write/fsync 同步写，立即落盘。
//  设备没有 CrashReporter 日志时，靠 stage.log 的最后一行定位崩溃阶段。
//  写失败一律吞掉——打点本身绝不能成为新的崩溃源。
//

#import "LOGXStage.h"
#import "LOGXPath.h"

#import <fcntl.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>

void LOGXStage(const char *stage) {
    @autoreleasepool {
        @try {
            NSString *dir = LOGXDataDirectory();
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path = [dir stringByAppendingPathComponent:@"stage.log"];
            const char *cpath = path.fileSystemRepresentation;
            int fd = open(cpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
            if (fd >= 0) {
                char buf[640];
                time_t t = time(NULL);
                struct tm tmv;
                localtime_r(&t, &tmv);
                int n = snprintf(buf, sizeof(buf), "%02d:%02d:%02d %s pid=%d\n",
                                 tmv.tm_hour, tmv.tm_min, tmv.tm_sec, stage, (int)getpid());
                if (n > 0) {
                    (void)write(fd, buf, (size_t)n);
                    (void)fsync(fd);
                }
                close(fd);
            }
        } @catch (NSException *e) {
        }
    }
}
