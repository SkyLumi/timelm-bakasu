#!/usr/bin/env bash
# Build Image + modules for timelm (LineageOS 23.2, kernel 4.19) with KernelSU built-in.
#
# Environment:
#   KERNEL_DIR : kernel source directory (default: ../kernel)
#   TOOLCHAIN  : clang bin directory (default: ~/toolchain/clang-r563880c/bin)
#   JOBS       : parallel jobs (default: nproc)
#   OUT        : build directory (default: out)
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

echo "== KernelSU version =="
git -C ReSukiSU describe --tags 2>/dev/null || true

echo "== removing generated version files =="
rm -f "$OUT"/include/config/kernel.release \
      "$OUT"/include/generated/utsrelease.h \
      "$OUT"/include/generated/compile.h \
      "$OUT"/init/version.o

echo "== building Image ($(date -u)) =="
"${MK[@]}" Image

echo "== kernel version string =="
# grep -m1 exits early and strings gets SIGPIPE; with pipefail that would end the script (exit 141)
strings -a "$OUT/arch/arm64/boot/Image" | grep -m1 "Linux version 4.19.325" || true

echo "== ksu symbol count =="
grep -c " ksu_" "$OUT/System.map" || true
if grep -q "^CONFIG_KSU_SUSFS=y" "$OUT/.config"; then
	echo "== susfs symbol count =="
	grep -c " susfs_" "$OUT/System.map" || true
fi

echo "== building modules =="
"${MK[@]}" modules

echo "== done $(date -u) =="
echo "Image : $K/$OUT/arch/arm64/boot/Image"
echo "Next  : scripts/repack.sh"
