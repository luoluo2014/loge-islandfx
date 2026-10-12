# 落格Loge·灵动岛（LogeIsland）

> 落格出品 · 每一个插件都有他的灵魂

iOS 17 灵动岛背景视频自定义插件。为灵动岛的**紧凑（待机）状态**与**长按展开状态**分别设置背景视频，支持相册直接导入、素材目录选取、Filza 手动管理，内置注销与诊断日志。

## 功能

| 模块 | 说明 |
| --- | --- |
| 紧凑背景 | 未展开状态：启用开关、背景视频、填充模式（适应/填充/拉伸）、透明度、缩放、水平/垂直偏移、圆角模式（直角/跟随/自定义）、圆角半径 |
| 展开背景 | 长按展开状态：同上 9 项独立配置 |
| 视频导入 | ① 从相册直接添加（PHPicker，无需相册授权）② 在 Filza 中打开素材目录手动管理 ③ 素材列表点选即用、滑动删除 |
| 注销 | 设置内一键 respring（`sbreload`，失败兜底 `killall -9 SpringBoard`） |
| 诊断日志 | 设置内查看 / 复制分享 / 清空；插件崩溃循环时自动暂停并可在设置内一键恢复 |

## 安装

1. 从 [Releases](https://github.com/luoluo2014/loge-islandfx/releases) 下载 `com.loge.islandfx_2.0.0_iphoneos-arm64e.deb`
2. 用 Sileo / Zebra / Filza 安装（依赖：iOS 17.1+、mobilesubstrate、preferenceloader）
3. 安装后自动 respring，进入 **设置 → 落格Loge·灵动岛**
4. 打开总开关 → 分别配置「紧凑状态」「展开状态」两组参数
5. 添加视频：设置页 → 背景视频 → 「从相册添加视频」或「在 Filza 中打开」

> 视频文件存放于 `/var/jb/var/mobile/Library/LogeIsland/Videos`（Filza 可见）。
> 推荐 mp4 / mov（H.264），建议时长 5–30 秒、分辨率不高于 1080p。

## 排障

- 设置页顶部显示「未检测到引擎」：未 respring 或插件被崩溃循环保护暂停（有「恢复启用」按钮）
- 导入后没动静：打开设置 → 诊断日志，看「投递」相关条目；复制全文反馈给开发者
- 修改不生效：确认对应组的「启用」开关已打开；必要时用设置内的「注销重启」

## 从源码构建

Linux 交叉编译（不依赖 macOS）：

```bash
./tools/linux-cross-build.sh     # 编译 + ldid 签名
./tools/package-deb.sh           # 打包 deb
./tools/verify-deb.sh            # 交付前三重校验
```

macOS / Theos：

```bash
make package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
```

## 实现要点

- **Hook**：私有类 `_SPIslandRenderSurface`（`_sp_display_tick:` / `_sp_set_render_visible:` / `setLastPresentationRadius:` / `setLastPresentationSize:`）与 `SBSystemApertureContainerView`，运行时懒加载安装，加载延后 5 秒避免拖慢 SpringBoard
- **播放**：每 surface 一个 `AVQueuePlayer + AVPlayerLooper + AVPlayerLayer`，插入到灵动岛渲染表层之下
- **跨进程配置**：RootHide 双 realm 下走 CFPreferences app-id 域（`com.loge.islandfx`），cfprefsd 代写真实 plist
- **视频投递**：设置端 NSData → CFPreferences blob → 插件 5 秒轮询落地真实文件系统
- **崩溃循环保护**：30 秒内连续加载 2 次即暂停 hook，设置内可恢复
- **诊断日志**：os_log + 文件（512KB 轮转），设置端实时查看

## 许可

个人学习研究用途。落格出品。
