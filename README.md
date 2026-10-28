# timelm-bakasu

**KernelSU (ReSukiSU/BakaSU) built into the kernel for the LG V60 ThinQ (`timelm`) on LineageOS 23.2 (Android 16, kernel 4.19)**

Built and tested against **LineageOS 23.2-20261018** (`timelm`), kernel commit [`29902cf733dc`](https://github.com/LineageOS/android_kernel_lge_sm8250/commit/29902cf733dc), vermagic `4.19.325-cip133-st17-perf-g29902cf733dc`.

This repository contains patches and scripts to build the LineageOS 23.2 kernel with **KernelSU in built-in mode** (not LKM) for the LG V60 (`L-51A`, `LM-V600EA/VM/TM/N`), optionally with a **SUSFS v2.3.0 backport for 4.19 NonGKI**.

> Status: **working**: `su` works, the BakaSU manager reports "Working (Built-in)". Both variants (KernelSU only, KernelSU + SUSFS v2.3.0) were flashed and verified on an `LM-V600VM`: modem boots, speaker tuning, model name and vendor modules match stock.

> ⚠️ **Do not validate a kernel with `fastboot boot` on this phone.** LG's bootloader drops most of the
> kernel command line on a RAM boot (all `androidboot.vendor.lge.*`, `androidboot.revision`, `lge.*`).
> Even the **stock** Lineage `boot.img` misbehaves that way: `ro.product.model = UNKNOWN`, quiet
> speaker, the SDX55 modem never finishes booting and keeps retrying (phone gets hot), and after the
> retries run out the esoc driver panics. Flash to the active slot instead and keep a backup of the
> stock `boot` partition. Details: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md#4-fastboot-boot-truncates-the-kernel-command-line).

---

## Why this repo exists

The `4.19` non-GKI kernel is **not supported** by SukiSU Ultra `main`. It requires API ≥ 5.4 (`fsnotify.handle_inode_event`, `seccomp.filter_count`, `selinux_state.policy`, etc.). What works on 4.19 is **ReSukiSU / BakaSU** (a fork) with **manual hooks**, because the tracepoint hook path is GKI 2.0 only.

SUSFS is officially no longer supported on NonGKI kernels, and its `kernel-4.19` branch (v1.5.5) is too old for current ReSukiSU. `patches/0004` is a manual backport of the `gki-android12-5.10` kernel side (v2.3.0) to this LGE 4.19 tree.

This repo stores the patches and the build recipe so nobody has to repeat the same iterations. 🙂

---

## Features

- KernelSU **built-in** (`CONFIG_KSU=y`), multi-manager support, matches **BakaSU nightly 35252**
- Two hook modes (a Kconfig `choice` in ReSukiSU, pick one):
  - **manual hooks** (`0001`): KernelSU only
  - **SUSFS inline hooks** (`0001` + `0004`): KernelSU + SUSFS v2.3.0, all 9 features
    (`SUS_PATH`, `SUS_MOUNT`, `SUS_KSTAT`, `SPOOF_UNAME`, `ENABLE_LOG`, `HIDE_KSU_SUSFS_SYMBOLS`,
    `SPOOF_CMDLINE_OR_BOOTCONFIG`, `OPEN_REDIRECT`, `SUS_MAP`)
- **Vermagic and module CRCs identical to stock** (`Module.symvers` unchanged, also with SUSFS) → vendor modules (`wlan.ko`, audio DLKMs, …) still load
- Optional **MHI NULL-deref guards** (`0002`), see [below](#patches)

---

## Requirements

- LG V60 (`timelm`), bootloader unlocked, **LineageOS 23.2-20261018** (or a nightly whose kernel is still `29902cf733dc`) installed; flash from a **stock Android 13** base first
  - check your build: `adb shell getprop ro.lineage.version` (e.g. `23.2-20261018-NIGHTLY-timelm`)
- Linux build host (tested on an i3-4030U / 8 GB RAM and a 16-thread desktop), ~30 GB disk
- Toolchain: **AOSP clang 21 r563880c** (build `14054515`) that must match the official Lineage build; otherwise vermagic/module CRCs drift. It was removed from AOSP `main`/`main-kernel` in April 2026; fetch it from the last commit that still has it (see [`docs/BUILDING.md`](docs/BUILDING.md#1-sources-and-toolchain))
- Stock `boot.img` of the same nightly: `https://mirrorbits.lineageos.org/full/timelm/20261018/boot.img` (sha256 `7ec2506aaeb896e41108ef60fccfd6aa70204a4631caf646e1d97f5f1e06cd38`)
- `magiskboot`, `python3`, `git`, `zip`

## Patches

| Patch | What | Needed |
|---|---|---|
| `0001-lineage-ksu-integration.patch` | `drivers/kernelsu` link + Kconfig/Makefile, manual hooks (`exec`, `stat`, `open`, `reboot`) | always |
| `0002-mhi-null-guards.patch` | NULL guards in the MHI cleanup path | optional |
| `0003-setlocalversion-fixed.patch` | keeps the stock `-g29902cf733dc` suffix | always |
| `0004-susfs-v2.3.0-4.19.patch` | SUSFS v2.3.0 kernel side backported to 4.19; replaces the manual hooks of `0001` with SUSFS inline hooks | SUSFS variant only |

`0002` only matters when the external modem fails to boot (in practice: after `fastboot boot`).
On a flashed kernel the guarded code never runs. Without it a failed modem boot oopses in the
cleanup path; with it the esoc driver retries and panics on purpose after the last attempt. Both
variants were verified **without** `0002`.

## Build (quick start)

```bash
# 1. Sources (pin the kernel commit of the 20261018 nightly)
git clone -b lineage-23.2 https://github.com/LineageOS/android_kernel_lge_sm8250 kernel
git -C kernel checkout 29902cf733dc
git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025        # -> KSU_VERSION 35252 / UAPI 6

# 2. Patches
cd kernel
git apply ../patches/0001-lineage-ksu-integration.patch
git apply ../patches/0003-setlocalversion-fixed.patch
git apply ../patches/0004-susfs-v2.3.0-4.19.patch      # SUSFS variant only

# 3. Config: ikconfig from the stock boot.img, then one fragment, in out/ (build.sh uses O=out)
mkdir -p out
scripts/extract-ikconfig ../boot-stock.img > out/.config
cat ../config/ksu.fragment   >> out/.config        # KernelSU only
# cat ../config/susfs.fragment >> out/.config      # or: KernelSU + SUSFS
scripts/config --file out/.config -d LOCALVERSION_AUTO
# with the r563880c clang in PATH; pass the full LLVM toolset, otherwise CONFIG_RELR is silently dropped
make O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- olddefconfig

# 4. Build
KERNEL_DIR=$PWD TOOLCHAIN=/path/to/clang-r563880c/bin ../scripts/build.sh   # Image + modules
cd .. && scripts/repack.sh                                                  # boot.img via magiskboot
```

Full instructions and environment variables: [`docs/BUILDING.md`](docs/BUILDING.md).
SUSFS port notes: [`docs/SUSFS-BACKPORT.md`](docs/SUSFS-BACKPORT.md).

## Flash

Back up the current `boot` first (needs root, e.g. `adb root` on Lineage userdebug):

```bash
adb shell getprop ro.boot.slot_suffix                                   # e.g. _b
adb exec-out "cat /dev/block/by-name/boot_b" > boot_b-backup.img
adb reboot bootloader
fastboot flash boot_b boot-sukisu.img
fastboot reboot
# to go back: fastboot flash boot_b boot_b-backup.img
```

Verify:

```bash
adb shell su -c "cat /proc/version"                # must carry the stock vermagic suffix
adb shell su -c "/data/adb/ksud debug info"        # version 35252, uapi_version 6, runtime built-in
adb shell su -c id                                 # uid=0(root) context=u:r:ksu:s0
adb shell getprop ro.product.model                 # LM-V600 (UNKNOWN means a truncated cmdline)
adb logcat -d -b kernel | grep -E "ESOC_BOOT_DONE|use cnt file"
#   esoc-mdm:ESOC_BOOT_DONE ...                    # modem is up
#   tfa98xx ...: use cnt file rev_no 12, fw_name tfa98xx.cnt   # normal speaker tuning
```

KernelSU only: `adb shell su -c "grep -c ' ksu_' /proc/kallsyms"` → ~350.
SUSFS: the symbols are hidden (count is 0); check with the `ksu_susfs` tool from `susfs4ksu`
(`ksu_susfs show version` → `v2.3.0`, `show variant` → `NON-GKI`).

## Important notes

- `su` from `adb shell` only works once UID `2000` (Shell) is allowlisted in the manager (Superuser → *show system apps* → **Shell**). Without it, the shell answers `su: inaccessible or not found`; that is **not** a broken root.
- The manager build **must** match the driver. Driver `35252` (UAPI 6) ↔ manager `35171` (UAPI 4) → "Manager update required" banner and no userspace (`ksud`) installed. Use the nightly build matching the commit.
- A Lineage OTA will overwrite `boot` → root is gone, reflash required. If the OTA moves the kernel to a new commit, the vermagic changes: rebuild (or module loading may break) instead of reusing this image.
- SUSFS spoofs `/proc/cmdline` for **every** process once a fake buffer is set. Keep the `androidboot.vendor.lge.*` entries in your fake cmdline file, or the symptoms of a truncated cmdline come back for anything that reads it later.

## Known issues (ROM-side, not kernel)

- **WiFi**: `cnss` fails to load `regdb.bin` (looked up in six paths, missing) → connection can be flaky. Not caused by this kernel.
- Widevine drops to L3, Dual Screen case unsupported (ROM limitations, not kernel).

Former entries that turned out to be caused by `fastboot boot` (see the warning above): `ro.product.model = UNKNOWN`, quiet speaker, modem failing to boot "without a SIM", and the phone heating up while idle. On a flashed kernel the modem boots with or without a SIM.

## Credits

- [LineageOS](https://github.com/LineageOS) for the `lge_sm8250` kernel and `timelm` device tree
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) / [BakaSU](https://github.com/Baka-SU/BakaSU) (the 4.19-compatible KernelSU fork)
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (SUSFS, `gki-android12-5.10` branch)
- [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk) (provides `magiskboot`)

## License

Kernel patches follow the license of their sources: **GPL-2.0**. Scripts in this repo: MIT.
