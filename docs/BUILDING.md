# BUILDING — panduan lengkap

Diuji di: Ubuntu 24.04, i3-4030U (4 thread), 8 GB RAM, adaptor 65 W nyala terus ☕

## 1. Sumber daya

```bash
mkdir -p ~/timelm && cd ~/timelm

git clone --depth=1 -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_lge_sm8250 kernel

git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025     # KSU_VERSION 35252, UAPI 6

# Toolchain (harus r563880c / build 14054515)
mkdir -p toolchain && cd toolchain
curl -LO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r563880c.tar.gz
tar xzf clang-r563880c.tar.gz && cd ..
```

> **Kenapa toolchain harus sama?** Vermagic dan CRC simbol modul harus identik dengan
> build Lineage resmi, kalau tidak `/vendor/lib/modules/*.ko` (WiFi, audio DLKM) menolak load.

## 2. Config kernel

Config diambil dari **kernel yang sedang jalan di HP** (bukan defconfig):

```bash
# dari boot.img stock Lineage
cd kernel
scripts/extract-ikconfig ../boot-stock.img > .config

# tambahkan opsi KSU
cat ../config/ksu.fragment >> .config

# buang LOCALVERSION_AUTO supaya suffix versi tidak berubah
scripts/config --file .config -d LOCALVERSION_AUTO

make ARCH=arm64 olddefconfig
```

Cek hasilnya:

```bash
grep -E "^CONFIG_KSU|^CONFIG_LOCALVERSION" .config
# CONFIG_KSU=y
# CONFIG_LOCALVERSION="-perf-g29902cf733dc"
```

## 3. Integrasi ReSukiSU

```bash
ln -sfn ../ReSukiSU/kernel drivers/kernelsu
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
```

Manual hooks (4.19 tidak punya tracepoint GKI) — lihat `patches/0001-lineage-ksu-integration.patch`:

| File | Hook |
|---|---|
| `fs/exec.c` | `ksu_handle_execveat()` + `ksu_handle_post_execveat()` |
| `fs/stat.c` | `ksu_handle_stat()` (stat, newfstatat) |
| `fs/open.c` | `ksu_handle_faccessat()` |
| `kernel/reboot.c` | `ksu_handle_sys_reboot()` |

## 4. Build

```bash
KERNEL_DIR=~/timelm/kernel TOOLCHAIN=~/timelm/toolchain/clang-r563880c/bin \
  ~/timelm/timelm-kernelsu/scripts/build.sh
```

Hasil: `kernel/out/arch/arm64/boot/Image` (±48 MB) dan `kernel/out/System.map`.

Cek:
- `strings Image | grep "Linux version"` → suffix **persis** `4.19.325-cip133-st17-perf-g29902cf733dc`
- `grep -c " ksu_" out/System.map` → sekitar **350**

## 5. Repack

```bash
STOCK_BOOT=~/timelm/boot-stock.img \
IMAGE=~/timelm/kernel/out/arch/arm64/boot/Image \
  ~/timelm/timelm-kernelsu/scripts/repack.sh
```

⚠️ `repack.sh` akan **menolak** input `Image.gz`. Ini disengaja: LG XBL tidak bisa
melompat ke kernel terkompresi — hasilnya `LGE Crash Handler: UEFI Crash` lalu `Enter Sahara Mode`.

## 6. Flash & verifikasi

```bash
fastboot boot boot-sukisu.img
adb shell su -c "cat /proc/version"              # suffix vermagic stock
adb shell su -c "grep -c ' ksu_' /proc/kallsyms" # ~350
adb shell su -c "/data/adb/ksud debug info"      # runtime_mode: built-in
```

Manager: pakai **BakaSU nightly** yang build-nya cocok (lihat TROUBLESHOOTING).
