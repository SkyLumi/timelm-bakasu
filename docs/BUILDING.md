# BUILDING — full guide

Tested on: Ubuntu 24.04, i3-4030U (4 threads), 8 GB RAM, 65 W charger plugged in the whole time ☕

## 1. Sources and toolchain

```bash
mkdir -p ~/timelm && cd ~/timelm

git clone --depth=1 -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_lge_sm8250 kernel

git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025     # KSU_VERSION 35252, UAPI 6

# Toolchain (must be r563880c / build 14054515)
mkdir -p toolchain && cd toolchain
curl -LO https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r563880c.tar.gz
tar xzf clang-r563880c.tar.gz && cd ..
```

> **Why the exact same toolchain?** Vermagic and module symbol CRCs must match the
> official Lineage build, otherwise `/vendor/lib/modules/*.ko` (WiFi, audio DLKMs)
> refuse to load.

## 2. Kernel configuration

The config is taken from the kernel **currently running on the device** (not a defconfig):

```bash
# from the stock Lineage boot.img
cd kernel
scripts/extract-ikconfig ../boot-stock.img > .config

# append KernelSU options
cat ../config/ksu.fragment >> .config

# drop LOCALVERSION_AUTO so the version suffix stays intact
scripts/config --file .config -d LOCALVERSION_AUTO

make ARCH=arm64 olddefconfig
```

Check the result:

```bash
grep -E "^CONFIG_KSU|^CONFIG_LOCALVERSION" .config
# CONFIG_KSU=y
# CONFIG_LOCALVERSION="-perf-g29902cf733dc"
```

## 3. ReSukiSU integration

```bash
ln -sfn ../ReSukiSU/kernel drivers/kernelsu
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
echo 'source "drivers/kernelsu/Kconfig"' >> drivers/Kconfig
```

Manual hooks are required (4.19 has no GKI tracepoints) — see
`patches/0001-lineage-ksu-integration.patch`:

| File | Hook |
|---|---|
| `fs/exec.c` | `ksu_handle_execveat()` + `ksu_handle_post_execveat()` |
| `fs/stat.c` | `ksu_handle_stat()` (stat, newfstatat) |
| `fs/open.c` | `ksu_handle_faccessat()` |
| `kernel/reboot.c` | `ksu_handle_sys_reboot()` |

## 4. Build

```bash
KERNEL_DIR=~/timelm/kernel TOOLCHAIN=~/timelm/toolchain/clang-r563880c/bin \
  ~/timelm/timelm-bakasu/scripts/build.sh
```

Output: `kernel/out/arch/arm64/boot/Image` (±48 MB) and `kernel/out/System.map`.

Checks:
- `strings Image | grep "Linux version"` → suffix **exactly** `4.19.325-cip133-st17-perf-g29902cf733dc`
- `grep -c " ksu_" out/System.map` → around **350**

## 5. Repack

```bash
STOCK_BOOT=~/timelm/boot-stock.img \
IMAGE=~/timelm/kernel/out/arch/arm64/boot/Image \
  ~/timelm/timelm-bakasu/scripts/repack.sh
```

⚠️ `repack.sh` will **reject** an `Image.gz`. This is intentional: LG XBL cannot jump
to a compressed kernel — the result is `LGE Crash Handler: UEFI Crash` followed by
`Enter Sahara Mode`.

## 6. Flash and verify

```bash
fastboot boot boot-sukisu.img
adb shell su -c "cat /proc/version"               # stock vermagic suffix
adb shell su -c "grep -c ' ksu_' /proc/kallsyms"  # ~350
adb shell su -c "/data/adb/ksud debug info"       # runtime_mode: built-in
```

Manager: use the **BakaSU nightly** build matching the driver (see TROUBLESHOOTING).
