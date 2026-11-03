#!/usr/bin/env bash
# Pack a T509 boot.img with the exact stock header and Samsung marker.
# Usage: t509/pack-boot.sh [Image] [output.img]
#
# The stock ramdisk and stock DTB in t509/boot/ are kept unchanged; only the
# kernel Image is replaced. This is the verified first-boot-test layout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${1:-$ROOT/out/arch/arm64/boot/Image}"
OUT="${2:-$ROOT/out/boot-t509.img}"

RAMDISK="$ROOT/t509/boot/ramdisk"
DTB="$ROOT/t509/boot/dtb"
MKBOOTIMG="$ROOT/t509/mkbootimg/mkbootimg.py"
PARTITION_SIZE="${PARTITION_SIZE:-67108864}" # 64 MiB, mmcblk0p40

die() { echo "error: $*" >&2; exit 1; }

[ -f "$KERNEL" ] || die "kernel Image not found: $KERNEL"
[ -f "$RAMDISK" ] || die "stock ramdisk not found: $RAMDISK"
[ -f "$DTB" ] || die "stock dtb not found: $DTB"
[ -f "$MKBOOTIMG" ] || die "mkbootimg not found: $MKBOOTIMG"
[ "$PARTITION_SIZE" -ge 16777216 ] || die "PARTITION_SIZE looks too small: $PARTITION_SIZE"

# ARM64 Image magic is at offset 0x38: 41 52 4d 64 ("ARMd").
python3 - "$KERNEL" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
b = p.read_bytes()[:0x40]
if len(b) < 0x3c or b[0x38:0x3c] != b'ARMd':
    sys.exit(f"not an ARM64 Image (magic at 0x38 is {b[0x38:0x3c].hex()!r})")
print(f"kernel: {p} ({p.stat().st_size} bytes, ARM64 Image)")
PY

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$MKBOOTIMG" \
  --header_version 2 \
  --os_version 11.0.0 \
  --os_patch_level 2024-10 \
  --kernel "$KERNEL" \
  --ramdisk "$RAMDISK" \
  --dtb "$DTB" \
  --pagesize 0x00000800 \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --second_offset 0x00000000 \
  --tags_offset 0x00000100 \
  --dtb_offset 0x0000000001f00000 \
  --board SRPVF15B003 \
  --cmdline "console=ttyS1,115200n8" \
  -o "$TMP/boot.img"

mkdir -p "$(dirname "$OUT")"
python3 - "$TMP/boot.img" "$PARTITION_SIZE" "$OUT" <<'PY'
import hashlib
import sys
from pathlib import Path

img = Path(sys.argv[1]).read_bytes()
partition_size = int(sys.argv[2], 0)
out = Path(sys.argv[3])

marker = b'SEANDROIDENFORCE'
if len(img) + len(marker) > partition_size:
    sys.exit(f"image too large: {len(img) + len(marker)} > partition {partition_size}")

padded = img + marker
padded += b'\x00' * (partition_size - len(padded))
out.write_bytes(padded)

print(f"out:    {out}")
print(f"size:   {len(padded)} bytes (partition {partition_size})")
print(f"sha256: {hashlib.sha256(padded).hexdigest()}")
PY
