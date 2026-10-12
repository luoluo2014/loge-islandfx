#!/usr/bin/env python3
"""
fix-arm64e-ptrauth.py —— 给 arm64e 类元数据指针补上 PAC 认证签名。

背景
----
Linux 的 clang 18 不支持 ptrauth（__has_feature(ptrauth_calls)==false），
编出的 arm64e 类元数据指针（isa/superclass/bits/classlist/classrefs）是无签名
的裸地址。而最终 Mach-O 又带着 PTRAUTH_ABI 位（fix-arm64e-abi.py 补的），
iOS 14+ 的 ObjC 运行时会对这些指针做 PAC 认证（readClass→getSuperclass 的
autda），无签名指针在 FPAC 硬件上直接触发 SIGBUS（地址 0xdac11a30 一类）。

本脚本只处理「类指针」，它们的签名参数是固定的：
    key        = 2 (ptrauth_key_asda / process-independent-data)
    addrDiv    = 1 (多样性=指针槽地址)
    discriminator = 0x6AE1

方法列表指针（0xC310）由 ld64 的 ObjC pass 自己补（本工具链已正确产出），
protocol/ivar/property/name/cache 指针要么是 PtrauthRaw（透传不认证）、要么是
普通数据指针，都不需要签名——故本脚本绝不碰它们。

只改 chained fixup 链上指定位置的 8 字节值：置 auth/key/addrDiv/diversity 位，
保留 next/bind/target/ordinal，链结构不变。改完必须重新 ldid 签名。
"""
import struct
import sys

DISCRIMINATOR = 0x6AE1
KEY_ASDA = 2

def parse_macho(path):
    data = open(path, 'rb').read()
    assert struct.unpack('<I', data[:4])[0] == 0xFEEDFACF, '非 64 位 Mach-O'
    ncmds = struct.unpack('<I', data[16:20])[0]
    off, secs = 32, {}
    for _ in range(ncmds):
        cmd, size = struct.unpack('<II', data[off:off+8])
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[off+8:off+24].rstrip(b'\0').decode()
            nsects = struct.unpack('<I', data[off+64:off+68])[0]
            so = off + 72
            for i in range(nsects):
                s = data[so+i*80:so+(i+1)*80]
                name = s[:16].rstrip(b'\0').decode()
                addr, sz = struct.unpack('<QQ', s[32:48])
                fo = struct.unpack('<I', s[48:52])[0]
                secs[(segname, name)] = (addr, sz, fo)
        off += size
    return bytearray(data), secs

def next_bits(v):
    return (v >> 51) & 0x7FF

def sign_rebase(v):
    target = v & 0xFFFFFFFF
    nxt = next_bits(v)
    return ((1 << 63) | (nxt << 51) | (KEY_ASDA << 49) | (1 << 48)
            | (DISCRIMINATOR << 32) | target)

def sign_bind(v):
    ordinal = v & 0xFFFFFF
    nxt = next_bits(v)
    return ((1 << 63) | (1 << 62) | (nxt << 51) | (KEY_ASDA << 49)
            | (1 << 48) | (DISCRIMINATOR << 32) | ordinal)

def sign(v):
    return sign_bind(v) if ((v >> 62) & 1) else sign_rebase(v)

def patch(data, fileoff, value):
    struct.pack_into('<Q', data, fileoff, value)

def main(path):
    data, secs = parse_macho(path)
    stats = {'classlist': 0, 'class_obj': 0, 'classrefs': 0, 'superrefs': 0}

    def find(secname):
        for (seg, name), (a, sz, fo) in secs.items():
            if name == secname:
                return (a, sz, fo)
        return None

    # 1) __objc_classlist：全是类指针（rebase）
    cl = find('__objc_classlist')
    if cl:
        a, sz, fo = cl
        for i in range(sz // 8):
            off = fo + i * 8
            v = struct.unpack_from('<Q', data, off)[0]
            patch(data, off, sign_rebase(v))
            stats['classlist'] += 1

    # 2) __objc_data：类对象（40 字节一条，类+元类交替）
    #    +0 isa(rebase) +8 superclass(bind) +16 cache(plain,跳过) +24 mask(跳过) +32 bits(rebase)
    od = find('__objc_data')
    if od:
        a, sz, fo = od
        for i in range(sz // 40):
            base = fo + i * 40
            for field_off, kind in ((0, 'rebase'), (8, 'auto'), (32, 'rebase')):
                off = base + field_off
                v = struct.unpack_from('<Q', data, off)[0]
                nv = sign_rebase(v) if kind == 'rebase' else sign(v)
                patch(data, off, nv)
                stats['class_obj'] += 1

    # 3) __objc_classrefs / __objc_superrefs：类引用（bind 或 rebase 都有）
    for secname, key in (('__objc_classrefs', 'classrefs'), ('__objc_superrefs', 'superrefs')):
        r = find(secname)
        if r:
            a, sz, fo = r
            for i in range(sz // 8):
                off = fo + i * 8
                v = struct.unpack_from('<Q', data, off)[0]
                patch(data, off, sign(v))
                stats[key] += 1

    open(path, 'wb').write(data)
    print('  classlist: %d' % stats['classlist'])
    print('  类对象字段(isa/super/bits): %d' % stats['class_obj'])
    print('  classrefs: %d' % stats['classrefs'])
    print('  superrefs: %d' % stats['superrefs'])
    print('  discriminator=0x%04X key=%d(ASDA) addrDiv=1' % (DISCRIMINATOR, KEY_ASDA))

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for p in sys.argv[1:]:
        print('==> %s' % p)
        main(p)
