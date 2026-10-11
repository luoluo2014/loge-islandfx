#!/usr/bin/env bash
# 把编译产物组装成 RootHide 布局的 deb。
# 路径一律使用「逻辑路径」：RootHide 的 dpkg 在安装时会自动重定位到 jbroot 下，
# 源码与包内都不出现硬编码的越狱根路径。
set -euo pipefail

SRC="${SRC:-/workspace/MIAFX}"
STAGE="${STAGE:-/opt/build/stage}"
OUT="${OUT:-/workspace}"
PREFIX="${PREFIX:-com.loge.islandfx}"
VERSION="${VERSION:-0.1.0}"
ROOT="${ROOT:-/opt/build/debroot}"
ARCH_TAG="${ARCH_TAG:-arm64e}"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m错误：%s\033[0m\n' "$*" >&2; exit 1; }

for f in MIAFX.dylib MIAFXAudio.dylib MIAFXSettingsEntry; do
    [ -f "$STAGE/$f" ] || die "缺少产物：$STAGE/$f"
done

rm -rf "$ROOT"
mkdir -p "$ROOT/DEBIAN"
mkdir -p "$ROOT/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$ROOT/Library/PreferenceBundles/MIAFXSettingsEntry.bundle"

log "写入 DEBIAN"
cp "$SRC/control" "$ROOT/DEBIAN/control"
cp "$SRC/layout/DEBIAN/postinst" "$ROOT/DEBIAN/postinst"
cp "$SRC/layout/DEBIAN/postrm" "$ROOT/DEBIAN/postrm"
chmod 0755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"
chmod 0644 "$ROOT/DEBIAN/control"

log "写入 tweak 与过滤器"
cp "$STAGE/MIAFX.dylib" "$ROOT/Library/MobileSubstrate/DynamicLibraries/MIAFX.dylib"
cp "$SRC/MIAFX/MIAFX.plist" "$ROOT/Library/MobileSubstrate/DynamicLibraries/MIAFX.plist"
cp "$STAGE/MIAFXAudio.dylib" "$ROOT/Library/MobileSubstrate/DynamicLibraries/MIAFXAudio.dylib"
cp "$SRC/MIAFXAudio/MIAFXAudio.plist" "$ROOT/Library/MobileSubstrate/DynamicLibraries/MIAFXAudio.plist"
chmod 0755 "$ROOT/Library/MobileSubstrate/DynamicLibraries/"*.dylib
chmod 0644 "$ROOT/Library/MobileSubstrate/DynamicLibraries/"*.plist

log "写入系统设置入口"
cp "$STAGE/MIAFXSettingsEntry" "$ROOT/Library/PreferenceBundles/MIAFXSettingsEntry.bundle/MIAFXSettingsEntry"
cp "$SRC/MIAFXSettingsEntry/Info.plist" "$ROOT/Library/PreferenceBundles/MIAFXSettingsEntry.bundle/Info.plist"
chmod 0755 "$ROOT/Library/PreferenceBundles/MIAFXSettingsEntry.bundle/MIAFXSettingsEntry"
chmod 0644 "$ROOT/Library/PreferenceBundles/MIAFXSettingsEntry.bundle/Info.plist"

mkdir -p "$ROOT/Library/PreferenceLoader/Preferences"
cp "$SRC/layout/Library/PreferenceLoader/Preferences/MIAFX.plist" "$ROOT/Library/PreferenceLoader/Preferences/MIAFX.plist"
chmod 0644 "$ROOT/Library/PreferenceLoader/Preferences/MIAFX.plist"

log "写入素材目录"
mkdir -p "$ROOT/var/mobile/Library/LogeIsland"
for d in Videos Masks CustomOrbits Presets Logs; do
    mkdir -p "$ROOT/var/mobile/Library/LogeIsland/$d"
done
chmod 0755 "$ROOT/var/mobile/Library/LogeIsland"

log "打包"
DEB="$OUT/${PREFIX}_${VERSION}_iphoneos-${ARCH_TAG}.deb"
rm -f "$DEB"
dpkg-deb -Zxz --root-owner-group -b "$ROOT" "$DEB" 2>&1 | tail -3
ls -lh "$DEB"

log "校验包内容"
dpkg-deb -c "$DEB" | awk '{print $1, $6, $7, $8}' | sed -n '1,60p'
echo "---- control ----"
dpkg-deb -I "$DEB" | sed -n '1,20p'
