#!/usr/bin/env bash
# 落格Loge·灵动岛 2.0 —— Linux 交叉编译脚本（不依赖 Theos 的 Darwin 工具链）
#
# 用法：
#   ./linux-cross-build.sh            # 编译 arm64e（默认）
#   ARCHS="arm64e arm64" ./linux-cross-build.sh
#
# 依赖：clang（支持 arm64e-apple-ios）、Apple ld64（cctools-port 自编译）、
#       iPhoneOS17.1.sdk、Theos（Logos 预处理 + 私有框架头）、RootHide lib、ldid。
set -euo pipefail

SDK="${SDK:-/opt/build/iPhoneOS17.1.sdk}"
THEOS="${THEOS:-/opt/build/theos}"
RH="${RH:-/opt/build/rhlib/iphone/roothide}"
SRC="${SRC:-/workspace/LogeIsland}"
WORK="${WORK:-/opt/build/logx-work}"
STAGE="${STAGE:-/opt/build/logx-stage}"
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
# 因此先探测再决定是否带上。
if $CC -x objective-c -fsyntax-only -fno-ptrauth-objc-class-ro /dev/null >/dev/null 2>&1; then
    PTRAUTH_FLAG="-fno-ptrauth-objc-class-ro"
else
    PTRAUTH_FLAG=""
fi

COMMON_INC="-I$SRC/LogeIslandFX -I$SRC/Shared -I$SRC/LogeIslandPrefs -I$SRC/LogeIslandPrefs/CustomCells -I$THEOS/vendor/include -I/opt/build/inc"

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
perl "$LOGOS" "$SRC/LogeIslandFX/LogeIslandFX.xm" > "$WORK/logos/LogeIslandFX.mm" || die "Logos 处理失败：LogeIslandFX.xm"
printf '  LogeIslandFX.xm -> LogeIslandFX.mm (%s 行)\n' "$(wc -l < "$WORK/logos/LogeIslandFX.mm" | tr -d ' ')"

compile_one() {
    local src="$1" out="$2" mode="$3" arch="$4"
    local triple="arm64-apple-ios$MINVER"
    [ "$arch" = "arm64e" ] && triple="arm64e-apple-ios$MINVER"

    local flags="-target $triple -miphoneos-version-min=$MINVER -isysroot $SDK"
    flags="$flags -isystem $SDK/usr/include/c++/v1 -isystem $SDK/usr/include"
    flags="$flags $COMMON_INC"
    flags="$flags -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -Wno-unused-variable"
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
    # link_macho <输出> <类型 dylib|bundle> <arch...> <obj...>
    local out="$1"; shift
    local kind="$1"; shift
    local archs="$1"; shift
    # install_name 必须是合并后的最终文件名（去掉 -arm64e 之类的架构后缀）。
    local idname="$(basename "$out" | sed -E 's/-(arm64e|arm64)(\.|$)/\2/')"
    local cmd=("$LD" "-syslibroot" "$SDK" "-o" "$out")
    cmd+=("-F$SDK/System/Library/Frameworks" "-F$SDK/System/Library/PrivateFrameworks")
    for a in $archs; do cmd+=("-arch" "$a"); done
    for a in $archs; do
        local ver="$MINVER"; [ "$a" = "arm64e" ] && ver="$MINVER"
        cmd+=("-platform_version" "ios" "$ver" "$ver")
    done
    case "$kind" in
        dylib)  cmd+=("-dylib" "-install_name" "/Library/MobileSubstrate/DynamicLibraries/$idname" "-undefined" "dynamic_lookup");;
        bundle) cmd+=("-bundle" "-undefined" "dynamic_lookup");;
        *) die "未知产物类型：$kind" ;;
    esac
    cmd+=("$@")
    "${cmd[@]}"
}

# ------------------------------------------------------------------ 编译
for arch in $ARCHS; do
    log "编译 $arch"
    objs="$WORK/objs-$arch"
    mkdir -p "$objs"

    # SpringBoard tweak（灵动岛渲染 + 视频引擎 + boot guard）
    i=0
    for f in "$WORK/logos/LogeIslandFX.mm" \
             "$SRC"/LogeIslandFX/LOGXVideoBackground.m \
             "$SRC"/Shared/LOGXConfig.m "$SRC"/Shared/LOGXPath.m "$SRC"/Shared/LOGXLog.m; do
        i=$((i+1))
        case "$f" in *.mm) mode=objcpp;; *) mode=objc;; esac
        compile_one "$f" "$objs/sb-$i-$(basename "$f" | tr '.' '_').o" "$mode" "$arch" || die "编译失败：$f"
    done

    # 系统设置入口 bundle（清爽调参 UI，无独立 App）
    k=0
    for f in "$SRC"/LogeIslandPrefs/LOGXRootListController.m \
             "$SRC"/LogeIslandPrefs/LOGXVideoPickerController.m \
             "$SRC"/LogeIslandPrefs/LOGXLogController.m \
             "$SRC"/LogeIslandPrefs/CustomCells/LOGXToggleCell.m \
             "$SRC"/LogeIslandPrefs/CustomCells/LOGXSegmentCell.m \
             "$SRC"/LogeIslandPrefs/CustomCells/LOGXSliderCell.m \
             "$SRC"/LogeIslandPrefs/CustomCells/LOGXVideoCell.m \
             "$SRC"/LogeIslandPrefs/CustomCells/LOGXHeaderCell.m \
             "$SRC"/Shared/LOGXConfig.m "$SRC"/Shared/LOGXPath.m "$SRC"/Shared/LOGXLog.m; do
        k=$((k+1))
        case "$f" in *.mm) mode=objcpp;; *) mode=objc;; esac
        compile_one "$f" "$objs/entry-$k-$(basename "$f" | tr '.' '_').o" "$mode" "$arch" || die "编译失败：$f"
    done

    # 补上 arm64e 的 PTRAUTH_ABI 版本位（Linux clang 不写，Apple ld64 会因此
    # 拒绝把 ABI 版本写进产物，iOS 14+ 会判定为旧版 arm64e 而拒绝加载）
    if [ "$arch" = "arm64e" ]; then
        python3 /opt/build/fix-arm64e-abi.py "$objs"/*.o | tail -1
    fi

    # ---------------- 链接
    log "链接 $arch"
    link_macho "$WORK/LogeIslandFX-$arch.dylib" dylib "$arch" \
        "$objs"/sb-*.o \
        -lSystem -lobjc -lc++ \
        -framework Foundation -framework UIKit -framework QuartzCore \
        -framework AVFoundation -framework CoreMedia -framework CoreGraphics \
        -L"$RH" -lsubstrate -lroothide || die "链接 LogeIslandFX.dylib 失败"

    link_macho "$WORK/LogeIslandPrefs-$arch" bundle "$arch" \
        "$objs"/entry-*.o \
        -lSystem -lobjc -lc++ \
        -framework Foundation -framework UIKit -framework QuartzCore \
        -framework CoreGraphics -framework UniformTypeIdentifiers -framework PhotosUI \
        -framework Preferences -L"$RH" -lroothide || die "链接 LogeIslandPrefs 失败"
done

# ------------------------------------------------------------------ 合并架构
first_arch="$(echo "$ARCHS" | awk '{print $1}')"
log "输出产物"
for name in LogeIslandFX.dylib LogeIslandPrefs; do
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
sign "$STAGE/LogeIslandFX.dylib" ""
sign "$STAGE/LogeIslandPrefs" ""

log "完成：$STAGE"
ls -lh "$STAGE"
