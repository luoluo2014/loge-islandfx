# 落格Loge·灵动岛 — iOS 17.1 灵动岛特效插件

> 落格出品 · 每一个插件都有他的灵魂

> 目标环境：iOS 17.1 · Relaxin（RootHide 隐根）· arm64e
> 包名：`com.loge.islandfx` · 版本：`1.4.0`

「落格Loge·灵动岛」（工程代号 MIAFX）是一套按「防卡死 + 省电优先」设计的灵动岛改造插件：
视频底色、10 种呼吸动效、双层流光跑马灯、19 种轨迹素材、液态粘连（Metaball）、
以及与真实音频 FFT 联动的频谱可视化。**无独立 App**，所有调节都在
`系统设置 → 落格Loge·灵动岛` 里完成，改完即时生效。

---

## 架构

| 组件 | 注入进程 | 职责 |
| --- | --- | --- |
| `MIAFX.dylib` | SpringBoard | 岛特效渲染 + 读取配置 |
| `MIAFXAudio.dylib` | mediaserverd | AudioUnitRender → 1024 点 FFT → 16 频段 → notify 多播 |
| `MIAFXSettingsEntry.bundle` | Preferences | 完整调参界面（输入框+滑块+步进、实时预览、Filza 跳转） |

---

## 目录结构

```
MIAFX/
├── Makefile                # 聚合工程：THEOS_PACKAGE_SCHEME=roothide, ARCHS=arm64e
├── control                 # iphoneos-arm64e
├── Shared/                 # 纯 C / ObjC 共享基础设施（配置、IPC、FFT 重采样、日志、路径）
├── MIAFX/                  # SpringBoard 主 tweak
├── MIAFXAudio/             # mediaserverd 采集 tweak（纯 C 实时路径）
├── MIAFXSettingsEntry/     # 系统设置入口 PreferenceBundle（含全部调参 UI）
├── layout/                 # DEBIAN 脚本 + PreferenceLoader 入口 + 素材目录
├── tests/                  # 宿主可运行的纯 C 单元测试
└── tools/                  # Linux 交叉编译脚本（仅开发自检用）
```

---

## 编译

> ⚠️ **必须用 Apple 工具链（macOS / Xcode）**。`mediaserverd` / `SpringBoard` 是 arm64e
> 系统进程，Linux 交叉编译的 arm64e 缺少函数指针的 ptrauth 签名，运行时会
> `pointer authentication failure` 崩溃。这是编译器能力限制，不是代码问题。

### 方式 A：GitHub Actions（没有 Mac 也能出包）

把本仓库推到 GitHub 即自动编译：
- push 到 `main`/`master` → 构建产物上传到 Actions 的 Artifacts；
- push `v*` 标签（如 `v1.4.0`）→ 自动创建 GitHub Release 并附上 deb。

### 方式 B：macOS 本地编译

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
make clean
make package THEOS_PACKAGE_SCHEME=roothide
# 产物在 packages/
```

---

## 安装

```sh
dpkg -i com.loge.islandfx_1.4.0_iphoneos-arm64e.deb
uicache -a; sbreload
```

装完在 `设置 → 落格Loge·灵动岛` 里调参。数据目录（RootHide 下自动落到 jbroot）：
`var/mobile/Library/LogeIsland/{Videos,Masks,CustomOrbits,Presets,Logs}`。

### 1.4.0 起：视频素材的真实路径

RootHide 下设置 App 与 SpringBoard 的 `jbroot()` 指向两个不同的文件世界，设置端
直接拷进"Videos 目录"的文件插件永远读不到。1.4.0 起：

- 相册 / 「文件」App 导入的视频会经 **CFPreferences 暂存**（app-id `com.loge.islandfx`），
  由插件端落入**真实** `/var/jb/var/mobile/Library/LogeIsland/Videos/`；
- 配置里的视频路径**只存文件名**，插件按名字去真实目录解析；
- 旧版写在沙盒容器里的历史素材会在首次打开设置页时自动迁移；
- 想手动放素材，用 Filza 打开 `/var/jb/var/mobile/Library/LogeIsland/Videos`
  （设置页「灵动岛背景 → 诊断反馈」附近有一键跳转），再「从素材目录选择」即可。

> 装上升级包后请**重新选择一次背景视频**（旧值可能是沙盒绝对路径）。

---

## 分阶段启用

默认只开「视频 + 呼吸」，其余在设置里逐项打开，建议顺序：
视频 → 呼吸 → 原生元素 → 流光跑马灯 → 轨迹 → 液滴 → 频谱 → 律动。

`Global.PerformanceTier`（0 节能 / 1 均衡 / 2 华丽）与 `Global.MaxFPS` 联动降级；
息屏 / AOD / 岛隐藏时全部特效停摆以省电。

---

## 1.4.0 修订记录（依据真机诊断日志）

| 现象 | 根因 | 处理 |
| --- | --- | --- |
| 插件完全无效果 | boot guard 把 Attempts 累到 25 后永久锁死，再也加载不了 | 改为**时间窗口**判定（300 s 内连续 4 次才触发），不再永久锁死 |
| 设置里改了没用 | 沙盒 App 与 SpringBoard 的 `jbroot()` 是两个世界，配置互不相通 | 配置改走 **CFPreferences app-id 域**（cfprefsd 代写到真实 plist），两边读同一域 |
| 视频文件插件读不到 | 同上，且视频是二进制 | 视频以 **NSData 经 CFPreferences 暂存**，插件端落地到真实目录后清掉 |
| `_SPIslandRenderSurface 类存在：0` | Logos 静态 `%hook` 在 dylib 注入时类还没注册，hook 静默失败 | 改为**运行时懒加载**：`MSHookMessageEx` + `class_getInstanceMethod` 确认，轮询 / dyld 回调 / `SPRenderContextChangedNotif` 多重触发 |
| 触发了也不动 | 触发面只有 3 个入口，且图层可能 hidden / 不在层树 | 对齐 DynamicFX 的 10 个触发点，强制 `_playerLayer` 可见、入层树、正确 frame 与圆角，三级兜底 |
| 不知道卡在哪一步 | 没有可反馈的日志 | 常开诊断日志 `Logs/video-diag.log`（512 KB 轮转）+ 设置内一键分享/查看/清空 |

---

## 测试

纯 C 链路无需 iOS SDK：

```sh
make -C tests
```

65 条断言覆盖 FFT、16 频段、环形缓冲、IPC 打包、插值重采样与越界防御。
