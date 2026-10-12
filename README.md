# 落格Loge·灵动岛 — iOS 17.1 灵动岛特效插件

> 落格出品 · 每一个插件都有他的灵魂

> 目标环境：iOS 17.1 · Relaxin（RootHide 隐根）· arm64e
> 包名：`com.loge.islandfx` · 版本：`1.3.1`

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
- push `v*` 标签（如 `v1.3.1`）→ 自动创建 GitHub Release 并附上 deb。

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
dpkg -i com.loge.islandfx_1.3.1_iphoneos-arm64e.deb
uicache -a; sbreload
```

装完在 `设置 → 落格Loge·灵动岛` 里调参。数据目录（RootHide 下自动落到 jbroot）：
`var/mobile/Library/LogeIsland/{Videos,Masks,CustomOrbits,Presets,Logs}`。

---

## 分阶段启用

默认只开「视频 + 呼吸」，其余在设置里逐项打开，建议顺序：
视频 → 呼吸 → 原生元素 → 流光跑马灯 → 轨迹 → 液滴 → 频谱 → 律动。

`Global.PerformanceTier`（0 节能 / 1 均衡 / 2 华丽）与 `Global.MaxFPS` 联动降级；
息屏 / AOD / 岛隐藏时全部特效停摆以省电。

---

## 测试

纯 C 链路无需 iOS SDK：

```sh
make -C tests
```

65 条断言覆盖 FFT、16 频段、环形缓冲、IPC 打包、插值重采样与越界防御。
