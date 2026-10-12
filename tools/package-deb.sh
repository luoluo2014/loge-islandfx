#!/usr/bin/env bash
# 落格Loge·灵动岛 2.0 —— 把编译产物组装成 RootHide 布局的 deb。
# 路径一律使用「逻辑路径」：RootHide 的 dpkg 安装时自动重定位到 jbroot 下，
# 源码与包内都不出现硬编码的越狱根路径。
set -euo pipefail

SRC="${SRC:-/workspace/LogeIsland}"
STAGE="${STAGE:-/opt/build/logx-stage}"
OUT="${OUT:-/workspace}"
PREFIX="${PREFIX:-com.loge.islandfx}"
VERSION="${VERSION:-2.0.0}"
ROOT="${ROOT:-/opt/build/logx-debroot}"
ARCH_TAG="${ARCH_TAG:-arm64e}"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m错误：%s\033[0m\n' "$*" >&2; exit 1; }

for f in LogeIslandFX.dylib LogeIslandPrefs; do
    [ -f "$STAGE/$f" ] || die "缺少产物：$STAGE/$f"
done

rm -rf "$ROOT"
mkdir -p "$ROOT/DEBIAN"
mkdir -p "$ROOT/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$ROOT/Library/PreferenceBundles/LogeIslandPrefs.bundle"

log "写入 DEBIAN"
cp "$SRC/control" "$ROOT/DEBIAN/control"
cp "$SRC/layout/DEBIAN/postinst" "$ROOT/DEBIAN/postinst"
cp "$SRC/layout/DEBIAN/postrm" "$ROOT/DEBIAN/postrm"
chmod 0755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"
chmod 0644 "$ROOT/DEBIAN/control"

log "写入 tweak 与过滤器"
cp "$STAGE/LogeIslandFX.dylib" "$ROOT/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.dylib"
cp "$SRC/LogeIslandFX/LogeIslandFX.plist" "$ROOT/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.plist"
chmod 0755 "$ROOT/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.dylib"
chmod 0644 "$ROOT/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.plist"

log "写入系统设置入口 bundle"
BUNDLE="$ROOT/Library/PreferenceBundles/LogeIslandPrefs.bundle"
cp "$STAGE/LogeIslandPrefs" "$BUNDLE/LogeIslandPrefs"
cp "$SRC/LogeIslandPrefs/Resources/Info.plist" "$BUNDLE/Info.plist"
mkdir -p "$BUNDLE/Resources"
cp "$SRC/LogeIslandPrefs/Resources/Root.plist" "$BUNDLE/Resources/Root.plist"
for png in icon@2x.png icon@3x.png header.png; do
    cp "$SRC/LogeIslandPrefs/Resources/$png" "$BUNDLE/Resources/$png"
done
chmod 0755 "$BUNDLE/LogeIslandPrefs"
chmod 0644 "$BUNDLE/Info.plist" "$BUNDLE/Resources/"*

mkdir -p "$ROOT/Library/PreferenceLoader/Preferences"
cp "$SRC/LogeIslandPrefs/entry.plist" "$ROOT/Library/PreferenceLoader/Preferences/LogeIsland.plist"
chmod 0644 "$ROOT/Library/PreferenceLoader/Preferences/LogeIsland.plist"

log "写入素材目录"
mkdir -p "$ROOT/var/mobile/Library/LogeIsland"
for d in Videos Logs; do
    mkdir -p "$ROOT/var/mobile/Library/LogeIsland/$d"
done
chmod 0755 "$ROOT/var/mobile/Library/LogeIsland" "$ROOT/var/mobile/Library/LogeIsland/Videos" "$ROOT/var/mobile/Library/LogeIsland/Logs"

log "打包"
DEB="$OUT/${PREFIX}_${VERSION}_iphoneos-${ARCH_TAG}.deb"
rm -f "$DEB"
dpkg-deb -Zxz --root-owner-group -b "$ROOT" "$DEB" 2>&1 | tail -3
ls -lh "$DEB"

log "校验包内容"
dpkg-deb -c "$DEB" | awk '{print $1, $6, $7, $8}' | sed -n '1,60p'
echo "---- control ----"
dpkg-deb -I "$DEB" | sed -n '1,20p'
