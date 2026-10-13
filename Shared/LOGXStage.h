//
//  LOGXStage.h
//  LogeIsland — 落格Loge·灵动岛
//
//  崩溃定位打点：同步写 stage.log，靠文件最后一行定位崩溃阶段。
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 同步写一行阶段标记（POSIX open/write/fsync，立即落盘，写失败一律吞掉）。
/// 供 tweak（LogeIslandFX）在关键节点调用，与 logos 编译无关。
void LOGXStage(const char *stage);

#ifdef __cplusplus
}
#endif
