#!/usr/bin/env bash
# Repack Image -> boot.img using magiskboot.
#
# IMPORTANT (LG): XBL refuses a compressed kernel. The "kernel" file inside the
# repack directory MUST be a raw Image (output of 'make Image'), not Image.gz.
#
# Environment:
#   STOCK_BOOT : stock Lineage boot.img (default: ../boot-stock.img)
#   IMAGE      : raw Image from the build (default: ../kernel/out/arch/arm64/boot/Image)
#   MAGISKBOOT : path to magiskboot (default: ./magiskboot)
#   OUTIMG     : output file name (default: boot-sukisu.img)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOCK="${STOCK_BOOT:-$ROOT/boot-stock.img}"
IMAGE="${IMAGE:-$ROOT/kernel/out/arch/arm64/boot/Image}"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/magiskboot}"
OUTIMG="${OUTIMG:-boot-sukisu.img}"

[ -f "$STOCK" ] || { echo "!! stock boot.img not found: $STOCK"; exit 1; }
[ -f "$IMAGE" ] || { echo "!! Image not found: $IMAGE"; exit 1; }

file "$IMAGE" | grep -qi "Linux kernel ARM64 boot executable Image" \
  || { echo "!! $IMAGE is not a raw Image (do not use Image.gz)"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== unpacking stock boot.img =="
( cd "$work" && "$MAGISKBOOT" unpack "$STOCK" >/dev/null )

echo "== preparing repack directory =="
mkdir -p "$work/repack"
cp "$work/ramdisk.cpio" "$work/dtb" "$work/repack/"
cp "$IMAGE" "$work/repack/kernel"

echo "== repacking =="
( cd "$work/repack" && "$MAGISKBOOT" repack "$STOCK" "$ROOT/$OUTIMG" )

echo "== output =="
ls -l "$ROOT/$OUTIMG"
sha256sum "$ROOT/$OUTIMG"
echo
echo "Test  : fastboot boot $OUTIMG"
echo "Commit: fastboot flash boot $OUTIMG"
