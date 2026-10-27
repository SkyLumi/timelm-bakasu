#!/usr/bin/env bash
# Repack Image -> boot.img dengan magiskboot.
#
# PENTING (LG): XBL menolak kernel terkompresi. File "kernel" di folder repack
# HARUS Image mentah (hasil 'make Image'), bukan Image.gz.
#
# Env:
#   STOCK_BOOT : boot.img stock Lineage (default: ../boot-stock.img)
#   IMAGE      : Image hasil build (default: ../kernel/out/arch/arm64/boot/Image)
#   KERNEL_DIR : source kernel (untuk ambil ramdisk.cpio + dtb via unpack)
#   MAGISKBOOT : path magiskboot (default: ./magiskboot)
#   OUTIMG     : nama output (default: boot-sukisu.img)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOCK="${STOCK_BOOT:-$ROOT/boot-stock.img}"
IMAGE="${IMAGE:-$ROOT/kernel/out/arch/arm64/boot/Image}"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/magiskboot}"
OUTIMG="${OUTIMG:-boot-sukisu.img}"

[ -f "$STOCK" ]   || { echo "!! stock boot.img tidak ada: $STOCK"; exit 1; }
[ -f "$IMAGE" ]   || { echo "!! Image tidak ada: $IMAGE"; exit 1; }

file "$IMAGE" | grep -qi "Linux kernel ARM64 boot executable Image" \
  || { echo "!! $IMAGE bukan Image mentah (jangan pakai Image.gz)"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== unpack stock =="
( cd "$work" && "$MAGISKBOOT" unpack "$STOCK" >/dev/null )

echo "== siapkan repack =="
mkdir -p "$work/repack"
cp "$work/ramdisk.cpio" "$work/dtb" "$work/repack/"
cp "$IMAGE" "$work/repack/kernel"

echo "== repack =="
( cd "$work/repack" && "$MAGISKBOOT" repack "$STOCK" "$ROOT/$OUTIMG" )

echo "== hasil =="
ls -l "$ROOT/$OUTIMG"
sha256sum "$ROOT/$OUTIMG"
echo
echo "Tes  : fastboot boot $OUTIMG"
echo "Simpan: fastboot flash boot $OUTIMG"
