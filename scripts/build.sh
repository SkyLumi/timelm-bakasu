#!/usr/bin/env bash
# Build Image + modules untuk timelm (LineageOS 23.2, kernel 4.19) + KernelSU built-in.
#
# Env:
#   KERNEL_DIR   : direktori source kernel (default: ../kernel)
#   TOOLCHAIN    : bin clang (default: ~/toolchain/clang-r563880c/bin)
#   JOBS         : -j (default: nproc)
#   OUT          : build dir (default: out)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${KERNEL_DIR:-$ROOT/kernel}"
TC="${TOOLCHAIN:-$HOME/toolchain/clang-r563880c/bin}"
JOBS="${JOBS:-$(nproc)}"
OUT="${OUT:-out}"

export PATH="$TC:/usr/bin:/bin:/usr/sbin:/sbin"
export ARCH=arm64
cd "$K"

MK=(make -j"$JOBS" O="$OUT" ARCH=arm64
    CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-)

echo "== KSU version =="
git -C ReSukiSU describe --tags 2>/dev/null || true

echo "== hapus generated version =="
rm -f "$OUT"/include/config/kernel.release \
      "$OUT"/include/generated/utsrelease.h \
      "$OUT"/include/generated/compile.h \
      "$OUT"/init/version.o

echo "== build Image ($(date -u)) =="
"${MK[@]}" Image

echo "== cek versi =="
strings -a "$OUT/arch/arm64/boot/Image" | grep -m1 "Linux version 4.19.325"

echo "== jumlah simbol ksu =="
grep -c " ksu_" "$OUT/System.map" || true

echo "== modules =="
"${MK[@]}" modules

echo "== selesai $(date -u) =="
echo "Image : $K/$OUT/arch/arm64/boot/Image"
echo "Lanjut: scripts/repack.sh"
