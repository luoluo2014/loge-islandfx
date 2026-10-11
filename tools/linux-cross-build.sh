#!/usr/bin/env bash
# MIAFX / 落格Loge·灵动岛 —— Linux 交叉编译脚本（不依赖 Theos 的 Darwin 工具链）
#
# 用法：
#   ./build.sh            # 编译 arm64e（iOS 17.1 系统进程的必需架构）
#   ARCHS="arm64e arm64" ./build.sh
#
# 依赖：clang（支持 arm64e-apple-ios）、ld64.lld（LLVM lld 的 Mach-O 驱动）、
#       iPhoneOS17.1.sdk、Theos（Logos 预处理 + 私有框架头）、RootHide lib（tbd）、ldid。
set -euo pipefail

SDK="${SDK:-/opt/build/iPhoneOS17.1.sdk}"
THEOS="${THEOS:-/opt/build/theos}"
RH="${RH:-/opt/build/rhlib/iphone/roothide}"
SRC="${SRC:-/workspace/MIAFX}"
WORK="${WORK:-/opt/build/work}"
STAGE="${STAGE:-/opt/build/stage}"
ARCHS="${ARCHS:-arm64e}"
MINVER="${MINVER:-17.1}"
LOGOS="$THEOS/bin/logos.pl"
LDID="${LDID:-/opt/build/ldid/ldid}"

CC=clang
CXX=clang++
# 链接器优先用 Apple 原版 ld64（cctools-port 自编译，支持 arm64e/ptrauth）；
# 退化到 LLVM 的 ld64.lld（只能产出 arm64，无法注入 SpringBoard 等系统进程）。
if [ -n "${LD:-}" ]; then
    :
elif [ -x /opt/build/toolchain/bin/aarch64-apple-darwin-ld ]; then
    LD=/opt/build/toolchain/bin/aarch64-apple-darwin-ld
else
    LD=ld64.lld
fi
# -fno-ptrauth-objc-class-ro 只有 Apple clang 支持；Linux clang 上会直接报错，
# 因此先探测再决定是否带上（与工程 Makefile 的处理方式一致）。
if $CC -x objective-c -fsyntax-only -fno-ptrauth-objc-class-ro /dev/null >/dev/null 2>&1; then
    PTRAUTH_FLAG="-fno-ptrauth-objc-class-ro"
else
    PTRAUTH_FLAG=""
fi

COMMON_INC="-I$SRC/MIAFXAudio -I$SRC/Shared -I$THEOS/vendor/include -I/opt/build/inc -I$SRC/MIAFX -I$SRC/MIAFXPrefs -I$SRC/MIAFXSettingsEntry"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m错误：%s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$SDK" ] || die "找不到 SDK：$SDK"
[ -f "$LOGOS" ] || die "找不到 Logos：$LOGOS"
command -v "$LD" >/dev/null || die "找不到链接器 $LD"

rm -rf "$WORK" "$STAGE"
mkdir -p "$WORK" "$STAGE"

# ---------------------------------------------------------------- Logos 预处理
log "Logos 预处理"
mkdir -p "$WORK/logos"
for xm in "$SRC"/MIAFX/MIAFXMain.xm "$SRC"/MIAFXAudio/MIAFXAudioMain.xm; do
    base="$(basename "$xm" .xm)"
    perl "$LOGOS" "$xm" > "$WORK/logos/$base.mm" || die "Logos 处理失败：$xm"
    printf '  %s -> %s.mm (%s 行)\n' "$(basename "$xm")" "$base" "$(wc -l < "$WORK/logos/$base.mm" | tr -d ' ')"
done

compile_one() {
    local src="$1" out="$2" mode="$3" arch="$4"
    local triple="arm64-apple-ios$MINVER"
    [ "$arch" = "arm64e" ] && triple="arm64e-apple-ios$MINVER"

    local flags="-target $triple -miphoneos-version-min=$MINVER -isysroot $SDK"
    flags="$flags -isystem $SDK/usr/include -I$SDK/usr/include"
    flags="$flags $COMMON_INC"
    flags="$flags -Wall -Wno-unused-parameter -Wno-deprecated-declarations -Wno-unused-variable"
    flags="$flags $PTRAUTH_FLAG"

    case "$mode" in
        objc)   flags="$flags -fobjc-arc";;
        objcpp) flags="$flags -fobjc-arc";;
        c)      flags="$flags -fno-objc-arc";;
        cxx)    ;;
    esac

    case "$src" in
        *.mm) $CXX $flags -x objective-c++ -std=gnu++17 -c "$src" -o "$out" ;;
        *.m)  $CC  $flags -x objective-c   -std=gnu11  -c "$src" -o "$out" ;;
        *.c)  $CC  $flags -x c             -std=gnu11  -c "$src" -o "$out" ;;
        *) die "未知源文件：$src" ;;
    esac
}

link_macho() {
    # link_macho <输出> <类型 dylib|exec|bundle> <arch...> <obj...>
    local out="$1"; shift
    local kind="$1"; shift
    local archs="$1"; shift
    # install_name 必须是合并后的最终文件名（去掉 -arm64e 之类的架构后缀），
    # 否则 lipo 合并后 ID 会残留架构名。
    local idname="$(basename "$out" | sed -E 's/-(arm64e|arm64)(\.|$)/\2/')"
    local cmd=("$LD" "-syslibroot" "$SDK" "-o" "$out")
    cmd+=("-F$SDK/System/Library/Frameworks" "-F$SDK/System/Library/PrivateFrameworks")
    for a in $archs; do cmd+=("-arch" "$a"); done
    for a in $archs; do
        local ver="$MINVER"; [ "$a" = "arm64e" ] && ver="$MINVER"
        cmd+=("-platform_version" "ios" "$ver" "$ver")
    done
    case "$kind" in
        dylib) cmd+=("-dylib" "-install_name" "/Library/MobileSubstrate/DynamicLibraries/$idname" "-undefined" "dynamic_lookup");;
        exec)  cmd+=("-execute");;
        bundle) cmd+=("-bundle" "-undefined" "dynamic_lookup");;
    esac
    cmd+=("$@")
    "${cmd[@]}"
}

# ------------------------------------------------------------------ 编译
for arch in $ARCHS; do
    log "编译 $arch"
    objs="$WORK/objs-$arch"
    mkdir -p "$objs"

    # SpringBoard tweak
    i=0
    for f in "$WORK/logos/MIAFXMain.mm" \
             "$SRC"/MIAFX/MIAFXClock.m "$SRC"/MIAFX/MIAFXPassthroughView.m \
             "$SRC"/MIAFX/MIAFXStateCoordinator.m "$SRC"/MIAFX/MIAFXIslandHostBridge.m \
             "$SRC"/MIAFX/MIAFXNativeElementBridge.m "$SRC"/MIAFX/MIAFXRootRenderer.m \
             "$SRC"/MIAFX/MIAFXVideoLayer.m "$SRC"/MIAFX/MIAFXBreathing.m \
             "$SRC"/MIAFX/MIAFXMarqueeFX.m "$SRC"/MIAFX/MIAFXOrbitFX.m \
             "$SRC"/MIAFX/MIAFXMetaballFX.m "$SRC"/MIAFX/MIAFXSpectrumView.m \
             "$SRC"/MIAFX/MIAFXProbe.m \
             "$SRC"/Shared/MIAFXPath.m "$SRC"/Shared/MIAFXDefaults.m \
             "$SRC"/Shared/MIAFXConfig.m "$SRC"/Shared/MIAFXLog.m "$SRC"/Shared/MIAFXSafe.m; do
        i=$((i+1))
        case "$f" in *.mm) mode=objcpp;; *) mode=objc;; esac
        compile_one "$f" "$objs/sb-$i-$(basename "$f" | tr '.' '_').o" "$mode" "$arch" || die "编译失败：$f"
    done
    for f in "$SRC"/Shared/MIAFXIPC.c "$SRC"/Shared/MIAFXSpectrumResample.c; do
        i=$((i+1))
        compile_one "$f" "$objs/sb-$i-$(basename "$f" | tr '.' '_').o" c "$arch" || die "编译失败：$f"
    done

    # mediaserverd tweak
    j=0
    for f in "$WORK/logos/MIAFXAudioMain.mm" \
             "$SRC"/MIAFXAudio/MIAFXFFT.c "$SRC"/MIAFXAudio/MIAFXBands.c \
             "$SRC"/MIAFXAudio/MIAFXRing.c "$SRC"/MIAFXAudio/MIAFXUnitProbe.c \
             "$SRC"/MIAFXAudio/MIAFXPublisher.c "$SRC"/Shared/MIAFXIPC.c; do
        j=$((j+1))
        case "$f" in *.mm) mode=objcpp;; *.c) mode=c;; *) mode=objc;; esac
        compile_one "$f" "$objs/au-$j-$(basename "$f" | tr '.' '_').o" "$mode" "$arch" || die "编译失败：$f"
    done

    # 系统设置入口 bundle（承载完整调参 UI，无需独立 App）
    k=0
    for f in "$SRC"/MIAFXSettingsEntry/MIAFXEntryController.m \
             "$SRC"/MIAFXSettingsEntry/MIAFXRootViewController.m \
             "$SRC"/MIAFXSettingsEntry/MIAFXSettingsCatalog.m \
             "$SRC"/MIAFXSettingsEntry/MIAFXNumberControlCell.m \
             "$SRC"/MIAFXSettingsEntry/MIAFXPreviewView.m \
             "$SRC"/MIAFXSettingsEntry/MIAFXFilzaLauncher.m \
             "$SRC"/Shared/MIAFXPath.m "$SRC"/Shared/MIAFXDefaults.m \
             "$SRC"/Shared/MIAFXConfig.m "$SRC"/Shared/MIAFXLog.m "$SRC"/Shared/MIAFXSafe.m; do
        k=$((k+1))
        case "$f" in *.mm) mode=objcpp;; *) mode=objc;; esac
        compile_one "$f" "$objs/entry-$k-$(basename "$f" | tr '.' '_').o" "$mode" "$arch" || die "编译失败：$f"
    done
    compile_one "$SRC"/Shared/MIAFXIPC.c "$objs/entry-$((k+1))-MIAFXIPC_c.o" c "$arch" || die "编译失败：MIAFXIPC.c"

    # 补上 arm64e 的 PTRAUTH_ABI 版本位（Linux clang 不写，Apple ld64 会因此
    # 拒绝把 ABI 版本写进产物，iOS 14+ 会判定为旧版 arm64e 而拒绝加载）
    if [ "$arch" = "arm64e" ]; then
        python3 /opt/build/fix-arm64e-abi.py "$objs"/*.o | tail -1
    fi

    # ---------------- 链接
    log "链接 $arch"
    link_macho "$WORK/MIAFX-$arch.dylib" dylib "$arch" \
        "$objs"/sb-*.o \
        -lSystem -lobjc -lc++ \
        -framework Foundation -framework UIKit -framework QuartzCore \
        -framework AVFoundation -framework CoreMedia -framework CoreGraphics \
        -L"$RH" -lsubstrate -lroothide || die "链接 MIAFX.dylib 失败"

    link_macho "$WORK/MIAFXAudio-$arch.dylib" dylib "$arch" \
        "$objs"/au-*.o \
        -lSystem -lobjc -lc++ \
        -framework AudioToolbox -framework CoreAudio -framework CoreFoundation \
        -L"$RH" -lsubstrate || die "链接 MIAFXAudio.dylib 失败"

    link_macho "$WORK/MIAFXSettingsEntry-$arch" bundle "$arch" \
        "$objs"/entry-*.o \
        -lSystem -lobjc -lc++ \
        -framework Foundation -framework UIKit -framework QuartzCore \
        -framework CoreGraphics -framework UniformTypeIdentifiers \
        -framework Preferences -L"$RH" -lroothide || die "链接设置入口失败"
done

# ------------------------------------------------------------------ 合并架构
first_arch="$(echo "$ARCHS" | awk '{print $1}')"
mkdir -p "$STAGE"
log "输出产物"
for name in MIAFX.dylib MIAFXAudio.dylib MIAFXSettingsEntry; do
    case "$name" in
        *.*) base="${name%.*}"; ext=".${name##*.}" ;;
        *)   base="$name";      ext="" ;;
    esac
    if [ "$(echo "$ARCHS" | wc -w)" -gt 1 ]; then
        inputs=()
        for a in $ARCHS; do inputs+=("$WORK/$base-$a$ext"); done
        # fat 合并必须用 cctools 的 lipo；ld64 只接受单架构
        LIPO=/opt/build/toolchain/bin/aarch64-apple-darwin-lipo
        command -v "$LIPO" >/dev/null || LIPO=lipo
        "$LIPO" -create -output "$STAGE/$name" "${inputs[@]}" || die "lipo 合并 $name 失败"
    else
        cp "$WORK/$base-$first_arch$ext" "$STAGE/$name"
    fi
    printf '  %s\n' "$name"
done

# ------------------------------------------------------------------ 签名
log "ldid 签名"
sign() {
    local file="$1" ent="$2"
    if [ -n "$ent" ] && [ -f "$ent" ]; then
        "$LDID" -S"$ent" "$file" || die "签名失败：$file"
    else
        "$LDID" -S "$file" || die "签名失败：$file"
    fi
    printf '  已签名 %s\n' "$(basename "$file")"
}
sign "$STAGE/MIAFX.dylib" ""
sign "$STAGE/MIAFXAudio.dylib" ""
sign "$STAGE/MIAFXSettingsEntry" ""

log "完成：$STAGE"
ls -lh "$STAGE"
