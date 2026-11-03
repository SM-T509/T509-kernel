#!/usr/bin/env bash
# Verify a packed T509 boot.img against the stock header and payloads.
# Usage: t509/verify-boot.sh [out/boot-t509.img]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${1:-$ROOT/out/boot-t509.img}"

STOCK_HEADER="$ROOT/t509/boot/stock-header.bin"
STOCK_RAMDISK="$ROOT/t509/boot/ramdisk"
STOCK_DTB="$ROOT/t509/boot/dtb"
UNPACK="$ROOT/t509/mkbootimg/unpack_bootimg.py"
PARTITION_SIZE="${PARTITION_SIZE:-67108864}"

die() { echo "error: $*" >&2; exit 1; }
[ -f "$IMG" ] || die "image not found: $IMG"
[ -f "$STOCK_HEADER" ] || die "stock header not found: $STOCK_HEADER"
[ -f "$STOCK_RAMDISK" ] || die "stock ramdisk not found: $STOCK_RAMDISK"
[ -f "$STOCK_DTB" ] || die "stock dtb not found: $STOCK_DTB"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$UNPACK" --boot_img "$IMG" --out "$TMP" >/dev/null

echo "=== header / layout ==="
python3 - "$IMG" "$STOCK_HEADER" "$TMP" "$PARTITION_SIZE" <<'PY'
import hashlib
import struct
import sys
from pathlib import Path

img = Path(sys.argv[1]).read_bytes()
stock = Path(sys.argv[2]).read_bytes()
tmp = Path(sys.argv[3])
partition_size = int(sys.argv[4], 0)

def hdr(b):
    if b[:8] != b'ANDROID!':
        raise SystemExit('bad ANDROID! magic')
    kernel_size, kernel_addr = struct.unpack_from('<II', b, 8)
    ramdisk_size, ramdisk_addr = struct.unpack_from('<II', b, 16)
    second_size, second_addr = struct.unpack_from('<II', b, 24)
    tags_addr, page_size = struct.unpack_from('<II', b, 32)
    header_version, os_version = struct.unpack_from('<II', b, 40)
    name = b[48:64].split(b'\x00', 1)[0].decode('ascii', 'replace')
    cmdline = b[64:576].split(b'\x00', 1)[0].decode('ascii', 'replace')
    extra = b[608:1632].split(b'\x00', 1)[0].decode('ascii', 'replace')
    rec_size, rec_off = struct.unpack_from('<IQ', b, 1632)
    header_size, dtb_size = struct.unpack_from('<II', b, 1644)
    dtb_addr, = struct.unpack_from('<Q', b, 1652)
    return dict(kernel_size=kernel_size, kernel_addr=kernel_addr,
                ramdisk_size=ramdisk_size, ramdisk_addr=ramdisk_addr,
                second_size=second_size, second_addr=second_addr,
                tags_addr=tags_addr, page_size=page_size,
                header_version=header_version, os_version=os_version,
                name=name, cmdline=cmdline, extra=extra,
                rec_size=rec_size, rec_off=rec_off,
                header_size=header_size, dtb_size=dtb_size, dtb_addr=dtb_addr)

h = hdr(img)
sh = hdr(stock)
keys = ['kernel_addr', 'ramdisk_addr', 'second_addr', 'tags_addr', 'page_size',
        'header_version', 'os_version', 'name', 'cmdline', 'extra',
        'rec_size', 'rec_off', 'header_size', 'dtb_addr']
bad = 0
for k in keys:
    flag = 'OK' if h[k] == sh[k] else 'DIFF'
    if h[k] != sh[k]:
        bad += 1
    print(f'{k:16} {flag:4} new={h[k]!r} stock={sh[k]!r}')

def ru(n, p): return (n + p - 1) // p * p
std_size = h['page_size'] + ru(h['kernel_size'], h['page_size']) + ru(h['ramdisk_size'], h['page_size']) + ru(h['dtb_size'], h['page_size'])
print(f'std_size        {std_size} bytes')
print(f'partition       {len(img)} bytes (expected {partition_size})')
print(f'marker          {img[std_size:std_size+16]!r}')
print(f'kernel sha256   {hashlib.sha256((tmp/"kernel").read_bytes()).hexdigest()}')
print(f'ramdisk sha256  {hashlib.sha256((tmp/"ramdisk").read_bytes()).hexdigest()}')
print(f'dtb sha256      {hashlib.sha256((tmp/"dtb").read_bytes()).hexdigest()}')

if bad:
    raise SystemExit(f'{bad} header field(s) differ from stock')
if len(img) != partition_size:
    raise SystemExit(f'image size {len(img)} != partition {partition_size}')
if img[std_size:std_size+16] != b'SEANDROIDENFORCE':
    raise SystemExit('missing SEANDROIDENFORCE marker')
PY

echo "=== compare payloads to stock ==="
for f in ramdisk dtb; do
  if cmp -s "$TMP/$f" "$ROOT/t509/boot/$f"; then
    echo "$f: identical to stock"
  else
    echo "$f: DIFFERS from stock" >&2
    exit 1
  fi
done
echo "kernel: $(stat -c%s "$TMP/kernel") bytes, magic=$(python3 -c "print(open('$TMP/kernel','rb').read()[0x38:0x3c])")"
