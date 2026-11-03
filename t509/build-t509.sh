#!/usr/bin/env bash
# Build the T509 (SM-T509 / gta4lve) stock Samsung kernel Image.
#
# Default: GCC 10.3 (works with the -Werror removal already applied to the
# top-level Makefile).
# Clang:   USE_CLANG=1 ./t509/build-t509.sh
#
# The exact vendor toolchain was Clang r383902 + AOSP GCC 4.9 binutils. The
# script uses the GCC 10.3 binutils with Clang, which is sufficient for the
# kernel Image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/../.." && pwd)"

JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-$ROOT/out}"
DEFCONFIG="${DEFCONFIG:-gta4lve_eur_open_defconfig}"

HOST="$WORKSPACE/tools/host"
GCC="$WORKSPACE/tools/toolchain/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin"
CLANG="$WORKSPACE/tools/toolchain/clang-r383902/bin"

[ -x "$GCC/aarch64-none-linux-gnu-gcc" ] || {
  echo "error: GCC 10.3 toolchain not found at $GCC" >&2
  echo "       set GCC to the directory containing aarch64-none-linux-gnu-gcc" >&2
  exit 1
}

export ARCH=arm64
export CROSS_COMPILE="$GCC/aarch64-none-linux-gnu-"
export PATH="$HOST/bin:$GCC:$PATH"
export LD_LIBRARY_PATH="$HOST/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CPATH="$HOST/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$HOST/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"

MAKE_ARGS=()
if [ "${USE_CLANG:-0}" = "1" ]; then
  [ -x "$CLANG/clang" ] || {
    echo "error: Clang r383902 not found at $CLANG" >&2
    exit 1
  }
  MAKE_ARGS=(
    CC="$CLANG/clang"
    LD="$GCC/aarch64-none-linux-gnu-ld"
    CLANG_TRIPLE=aarch64-none-linux-gnu-
  )
  echo "==> using Clang r383902 + GCC 10.3 binutils"
else
  echo "==> using GCC 10.3"
fi

echo "==> defconfig: $DEFCONFIG"
make -C "$ROOT" O="$OUT" "${MAKE_ARGS[@]}" "$DEFCONFIG"

echo "==> building Image (-j$JOBS)"
make -C "$ROOT" O="$OUT" -j"$JOBS" "${MAKE_ARGS[@]}" \
  HOSTLDFLAGS="-L$HOST/lib" Image

ls -lh "$OUT/arch/arm64/boot/Image"
echo "==> done: $OUT/arch/arm64/boot/Image"
