# BUILDING: full guide

Tested on: Ubuntu 24.04, i3-4030U (4 threads), 8 GB RAM, 65 W charger plugged in the whole time ☕,
and on a 16-thread Ubuntu 24.04 desktop.

Target ROM: **LineageOS 23.2-20261018** (`timelm`); kernel commit `29902cf733dc` → vermagic `4.19.325-cip133-st17-perf-g29902cf733dc`.

## 1. Sources and toolchain

```bash
mkdir -p ~/timelm && cd ~/timelm

# branch lineage-23.2; pin the kernel commit used by the 20261018 nightly
git clone -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_lge_sm8250 kernel
git -C kernel checkout 29902cf733dc
# shallow alternative: a fetch needs the full sha, the short one is refused by the server
#   git -C kernel fetch --depth=1 origin 29902cf733dcb4d0558ad5bd8c2eb8ba6e2077d2

git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025     # KSU_VERSION 35252, UAPI 6

# stock boot.img of the same nightly (config source + repack base)
curl -L -o boot-stock.img https://mirrorbits.lineageos.org/full/timelm/20261018/boot.img
echo "7ec2506aaeb896e41108ef60fccfd6aa70204a4631caf646e1d97f5f1e06cd38  boot-stock.img" | sha256sum -c
```

### Toolchain (must be r563880c / build 14054515)

`clang-r563880c` was removed from AOSP `prebuilts/clang/host/linux-x86` (`main` and `main-kernel`)
in April 2026, so `+archive/refs/heads/main/clang-r563880c.tar.gz` now returns HTTP 400 and a
sparse checkout of `main-kernel` comes back empty. Fetch it from `69c39c2c`, the last
`main-kernel` commit before the removal (partial clone, ~3.7 GB):

```bash
git init clang21 && cd clang21
git remote add origin https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86.git
git sparse-checkout set --no-cone /clang-r563880c/
git fetch --filter=blob:none --depth=1 origin 69c39c2ca6a2ab22eedc95f903a1e53c386a4e8c
git checkout FETCH_HEAD
./clang-r563880c/bin/clang --version   # Android (14054515, ...) clang version 21.0.0 ... r563880c
cd ..
```

> **Why the exact same toolchain?** Vermagic and module symbol CRCs must match the
> official Lineage build, otherwise `/vendor/lib/modules/*.ko` (WiFi, audio DLKMs)
> refuse to load.

`gcc-aarch64-linux-gnu` and `gcc-arm-linux-gnueabi` (Ubuntu packages) provide the
`CROSS_COMPILE` binutils prefixes used by the build.

## 2. Patches

```bash
cd ~/timelm/kernel
git apply ../timelm-bakasu/patches/0001-lineage-ksu-integration.patch
git apply ../timelm-bakasu/patches/0003-setlocalversion-fixed.patch
# optional: git apply ../timelm-bakasu/patches/0002-mhi-null-guards.patch
# SUSFS variant only:
git apply ../timelm-bakasu/patches/0004-susfs-v2.3.0-4.19.patch
```

`0001` already links `drivers/kernelsu` → `../ReSukiSU/kernel` and adds the
`obj-$(CONFIG_KSU)` / `source "drivers/kernelsu/Kconfig"` lines. Do **not** add them again by hand.

Hooks used by each variant:

| File | KernelSU only (`0001`, manual hooks) | SUSFS (`0004`, inline hooks) |
|---|---|---|
| `fs/exec.c` | `ksu_handle_execveat()` + `ksu_handle_post_execveat()` | `ksu_handle_execveat[_sucompat]()` + post hook |
| `fs/stat.c` | `ksu_handle_stat()` | `ksu_handle_stat()`, `ksu_handle_vfs_fstat()` |
| `fs/open.c` | `ksu_handle_faccessat()` | `ksu_handle_faccessat()` |
| `kernel/reboot.c` | `ksu_handle_sys_reboot()` | `ksu_handle_sys_reboot()` |
| `kernel/sys.c`, `fs/read_write.c`, `drivers/input/input.c` | LSM / input-handler auto hooks | `ksu_handle_setresuid()`, `ksu_handle_sys_read()`, `ksu_handle_input_handle_event()` |

ReSukiSU checks the SUSFS hooks at build time (`-- BakaSU/susfs_inline: ... found`).

## 3. Kernel configuration

The config is taken from the kernel **currently running on the device** (not a defconfig).
`build.sh` builds with `O=out`, so the config goes into `out/.config`; a `.config` in the source
root makes kbuild stop with "source tree is not clean".

```bash
cd ~/timelm/kernel
mkdir -p out
scripts/extract-ikconfig ../boot-stock.img > out/.config

cat ../timelm-bakasu/config/ksu.fragment   >> out/.config   # KernelSU only
# cat ../timelm-bakasu/config/susfs.fragment >> out/.config # KernelSU + SUSFS

# drop LOCALVERSION_AUTO so the version suffix stays intact
scripts/config --file out/.config -d LOCALVERSION_AUTO

export PATH=~/timelm/clang21/clang-r563880c/bin:$PATH
make O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- olddefconfig
```

Use the same tool variables as `build.sh`: `CONFIG_TOOLS_SUPPORT_RELR` / `CONFIG_RELR` (both `y`
in stock) are detected from the toolchain and silently drop out if, for example, `NM`/`OBJCOPY`
are left at the binutils defaults.

Check the result:

```bash
grep -E "^CONFIG_KSU|^# CONFIG_KSU_MANUAL|^CONFIG_LOCALVERSION" out/.config
# CONFIG_KSU=y
# CONFIG_KSU_MANUAL_HOOK=y          (KernelSU only)  /  CONFIG_KSU_SUSFS=y + 9 SUSFS options
# CONFIG_LOCALVERSION="-perf"       (the -g29902cf733dc part comes from 0003)
```

## 4. Build

```bash
KERNEL_DIR=~/timelm/kernel TOOLCHAIN=~/timelm/clang21/clang-r563880c/bin \
  ~/timelm/timelm-bakasu/scripts/build.sh
```

Output: `kernel/out/arch/arm64/boot/Image` (±46 MB, ±48 MB with SUSFS), `kernel/out/System.map`
and the modules.

Checks:
- `strings Image | grep "Linux version"` → suffix **exactly** `4.19.325-cip133-st17-perf-g29902cf733dc`
- `grep -c " ksu_" out/System.map` → around **350** (KernelSU only) or **340** (SUSFS)
- SUSFS: `grep -c " susfs_" out/System.map` → around 90, and the build log shows `-- SUSFS_VERSION: v2.3.0`
- optional KABI check: `out/Module.symvers` of both variants has the same CRCs as a KernelSU-only build

## 5. Repack

```bash
STOCK_BOOT=~/timelm/boot-stock.img \
IMAGE=~/timelm/kernel/out/arch/arm64/boot/Image \
MAGISKBOOT=~/timelm/magiskboot \
  ~/timelm/timelm-bakasu/scripts/repack.sh
```

Feed `repack.sh` the **raw** `Image`. `magiskboot` compresses it back to the format of the stock
kernel (gzip), exactly like the stock `boot.img`. What LG XBL refuses is a kernel that ends up
compressed twice (`Image.gz` given to `magiskboot`): `LGE Crash Handler: UEFI Crash` followed by
`Enter Sahara Mode`.

## 6. Flash and verify

`fastboot boot` is **not** a valid test on this phone: the bootloader truncates the kernel command
line on a RAM boot (see TROUBLESHOOTING #4). Back up and flash the active slot instead:

```bash
adb root
adb shell getprop ro.boot.slot_suffix                         # e.g. _b
adb exec-out "cat /dev/block/by-name/boot_b" > boot_b-backup.img
adb reboot bootloader
fastboot flash boot_b boot-sukisu.img && fastboot reboot

adb shell su -c "cat /proc/version"               # stock vermagic suffix
adb shell su -c "/data/adb/ksud debug info"       # runtime_mode: built-in
adb shell getprop ro.product.model                # LM-V600
adb logcat -d -b kernel | grep -E "ESOC_BOOT_DONE|use cnt file"
```

Manager: use the **BakaSU nightly** build matching the driver (see TROUBLESHOOTING).
