#!/usr/bin/env bash
# 落格Loge·灵动岛 2.0 —— deb 交付前三重校验：
#   1) 架构：dylib/bundle 必须都是 arm64e（PAC）
#   2) 中文：ObjC 字面量由本工具链以 UTF-16LE 存入 __ustring（CFString flags
#      标注 Unicode，运行时 CoreFoundation 正确解码，与 1.4.x 同款机制），
#      因此不能用 UTF-8 grep 校验，必须解码 __ustring 后比对关键文案
#   3) 符号：hook 私有类/通知名必须在二进制里
#   4) 布局：plist/权限位/资源文件齐备
set -euo pipefail

DEB="${1:-/workspace/com.loge.islandfx_2.0.0_iphoneos-arm64e.deb}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31m校验失败：%s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$DEB" ] || die "找不到 deb：$DEB"

log "解包 $DEB"
dpkg-deb -x "$DEB" "$WORK/root"
R="$WORK/root"
DYLIB="$R/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.dylib"
BUNDLE="$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/LogeIslandPrefs"

for f in "$DYLIB" "$BUNDLE" \
         "$R/Library/MobileSubstrate/DynamicLibraries/LogeIslandFX.plist" \
         "$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/Info.plist" \
         "$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/Resources/Root.plist" \
         "$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/Resources/icon@2x.png" \
         "$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/Resources/header.png" \
         "$R/Library/PreferenceLoader/Preferences/LogeIsland.plist" \
         "$R/var/mobile/Library/LogeIsland/Videos" \
         "$R/var/mobile/Library/LogeIsland/Logs"; do
    [ -e "$f" ] || die "缺少文件：$f"
done

log "1) 架构校验"
arch_info() {
    if command -v lipo >/dev/null 2>&1; then
        lipo -info "$1" 2>/dev/null || file -b "$1"
    else
        file -b "$1"
    fi
}
for f in "$DYLIB" "$BUNDLE"; do
    info="$(arch_info "$f")"
    echo "  $(basename "$f"): $info"
    echo "$info" | grep -q "arm64e" || die "$(basename "$f") 不是 arm64e"
done

log "2) 中文文案校验（UTF-16LE 解码 + plist）"
python3 - "$DYLIB" "$BUNDLE" "$R/Library/PreferenceBundles/LogeIslandPrefs.bundle/Resources/Root.plist" <<'PYEOF' || die "中文文案校验未通过"
import struct, re, sys

def sections(path):
    data = open(path, 'rb').read()
    ncmds = struct.unpack('<I', data[16:20])[0]
    off, secs = 32, {}
    for _ in range(ncmds):
        cmd, size = struct.unpack('<II', data[off:off+8])
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack('<I', data[off+64:off+68])[0]
            so = off + 72
            for i in range(nsects):
                s = data[so+i*80:so+(i+1)*80]
                name = s[:16].rstrip(b'\0').decode()
                addr, sz = struct.unpack('<QQ', s[32:48])
                fo = struct.unpack('<I', s[48:52])[0]
                secs[name] = (addr, sz, fo)
        off += size
    return data, secs

def chinese_strings(path):
    data, secs = sections(path)
    out = []
    for name, enc in [('__ustring', 'utf-16-le'), ('__cstring', 'utf-8')]:
        if name not in secs: continue
        _, sz, fo = secs[name]
        txt = data[fo:fo+sz].decode(enc, errors='replace')
        out += [f for f in txt.split('\x00') if re.search(r'[\u4e00-\u9fff]', f)]
    return out

checks = [
    (sys.argv[1], ['投递引擎启动', '崩溃循环保护', '已按设置端请求删除素材', '诊断日志']),
    (sys.argv[2], ['注销重启', '紧凑背景视频', '展开背景视频', '从相册添加视频', '相册']),
]
ok = True
for path, keys in checks:
    frags = chinese_strings(path)
    text = '\n'.join(frags)
    print(f'  {path.split("/")[-1]}: {len(frags)} 条中文')
    for k in keys:
        hit = k in text
        ok &= hit
        print(f'    [{"✓" if hit else "✗"}] {k}')

# plist 文案（UTF-8 资源，独立校验）
import plistlib
plist_path = sys.argv[3]
pl = plistlib.load(open(plist_path, 'rb'))
plist_text = plistlib.dumps(pl).decode('utf-8', 'replace')
for k in ['启用背景视频', '紧凑状态', '展开状态', '填充模式', '圆角模式', '注销重启', '诊断日志', '水平偏移', '垂直偏移', '圆角半径']:
    hit = k in plist_text
    ok &= hit
    print(f'    [{"✓" if hit else "✗"}] Root.plist: {k}')

sys.exit(0 if ok else 1)
PYEOF

log "3) 关键符号校验"
strings -a "$DYLIB" > "$WORK/strings.txt"
for sym in _SPIslandRenderSurface _sp_display_tick SBSystemApertureContainerView com.loge.islandfx.reload; do
    grep -q -- "$sym" "$WORK/strings.txt" || die "dylib 缺少符号：$sym"
    echo "  [✓] $sym"
done

log "4) 权限与安装脚本"
[ -x "$DYLIB" ] || die "dylib 缺少可执行位"
[ -x "$BUNDLE" ] || die "bundle 二进制缺少可执行位"
# 控制区要用 -e 单独解出（-x 只解数据区）
dpkg-deb -e "$DEB" "$WORK/ctrl"
for s in control postinst postrm; do
    f="$WORK/ctrl/$s"
    [ -f "$f" ] || die "缺少控制文件：$s"
done
for s in postinst postrm; do
    [ -x "$WORK/ctrl/$s" ] || die "$s 缺少可执行位"
done
echo "  [✓] DEBIAN 权限正常（postinst/postrm 0755）"

log "全部校验通过"
