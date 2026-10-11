#!/usr/bin/env python3
"""
fix-arm64e-abi.py —— 补齐 arm64e 目标文件的 PTRAUTH_ABI 版本位。

背景
----
Linux 上的 clang 为 `-target arm64e-apple-ios*` 只写出 `cpusubtype = 2`
（CPU_SUBTYPE_ARM64E），却不带 `CPU_SUBTYPE_PTRAUTH_ABI`（0x80000000）。
Apple clang 写的是 `0x80000002`。缺失该位时：

  1. Apple ld64 会警告 "object file built with an incompatible arm64e ABI"，
     并且**不会**把 arm64e ABI 版本写进最终产物；
  2. 最终 Mach-O 的 cpusubtype 能力位为 0，属于 iOS 13 时代的旧 arm64e，
     iOS 14 及以后（含 17.1）的 dyld / 内核会拒绝加载。

本脚本把 MH_OBJECT（单架构 .o）的 cpusubtype 低位保留、高位补上 0x80000000，
等价于 Apple clang 的行为。只改 Mach-O 头 4 个字节，不动任何代码段，
因此不影响校验和以外的语义（ld64 会从 .o 重新计算所有重定位）。

用法：fix-arm64e-abi.py <file.o> [<file.o> ...]
"""
import struct
import sys

MAGIC_64 = 0xFEEDFACF
MAGIC_32 = 0xFEEDFACE
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 2
CPU_SUBTYPE_PTRAUTH_ABI = 0x80000000


def patch(path: str) -> str:
    with open(path, "r+b") as fh:
        head = fh.read(8)
        if len(head) < 8:
            return "跳过（太短）"
        magic = struct.unpack_from("<I", head, 0)[0]
        if magic not in (MAGIC_64, MAGIC_32):
            return "跳过（非 Mach-O）"
        cputype = struct.unpack_from("<i", head, 4)[0]
        if cputype != CPU_TYPE_ARM64:
            return "跳过（非 arm64）"
        # cpusubtype 紧跟在 cputype 之后（偏移 8）
        more = fh.read(4)
        subtype = struct.unpack_from("<i", more, 0)[0]
        if (subtype & ~0xFF000000) != CPU_SUBTYPE_ARM64E:
            return "跳过（非 arm64e，subtype=%d）" % subtype
        if subtype & CPU_SUBTYPE_PTRAUTH_ABI:
            return "已有 ABI 位"
        new = (subtype | CPU_SUBTYPE_PTRAUTH_ABI) & 0xFFFFFFFF
        fh.seek(8)
        fh.write(struct.pack("<I", new))
        return "cpusubtype 0x%08x -> 0x%08x" % (subtype & 0xFFFFFFFF, new)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    changed = 0
    for p in sys.argv[1:]:
        try:
            res = patch(p)
        except OSError as exc:
            print("%s: 打开失败 %s" % (p, exc))
            continue
        if res.startswith("cpusubtype"):
            changed += 1
        print("%s: %s" % (p, res))
    print("共修补 %d 个目标文件" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
