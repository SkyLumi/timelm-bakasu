# timelm-bakasu

**KernelSU (ReSukiSU/BakaSU) built into the kernel for the LG V60 ThinQ (`timelm`) on LineageOS 23.2 (Android 16, kernel 4.19)**

Built and tested against **LineageOS 23.2-20261018** (`timelm`), kernel commit [`29902cf733dc`](https://github.com/LineageOS/android_kernel_lge_sm8250/commit/29902cf733dc), vermagic `4.19.325-cip133-st17-perf-g29902cf733dc`.

This repository contains patches and scripts to build the LineageOS 23.2 kernel with **KernelSU in built-in mode** (not LKM) for the LG V60 (`L-51A`, `LM-V600EA/VM/TM/N`), plus the technical notes on an `MHI`/modem bug that makes rebuilt kernels reboot on their own.

> Status: **working**: `su` works, the BakaSU manager reports "Working (Built-in)", and the MHI panic triggered by a failed modem boot is patched (see [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)).

---

## Why this repo exists

The `4.19` non-GKI kernel is **not supported** by SukiSU Ultra `main`. It requires API ≥ 5.4 (`fsnotify.handle_inode_event`, `seccomp.filter_count`, `selinux_state.policy`, etc.). What works on 4.19 is **ReSukiSU / BakaSU** (a fork) with **manual hooks**, because the tracepoint hook path is GKI 2.0 only.

After the kernel booted, a second problem appeared: the phone would **panic and reboot by itself**, with no obvious cause. It turned out to be the **Qualcomm MHI driver error path**: when the external modem (SDX55M) fails to power up (for example, **no SIM inserted**), `mhi_deinit_free_irq()` / `mhi_deinit_dev_ctxt()` dereference resources that were never allocated. Panic.

This repo stores the patches and the build recipe so nobody has to repeat the same seven iterations. 🙂

---

## Features

- KernelSU **built-in** (`CONFIG_KSU=y`) with **manual hooks** (4.19 compatible)
- Multi-manager support, matches **BakaSU nightly 35252**
- **Vermagic identical to stock** (`4.19.325-cip133-st17-perf-g29902cf733dc`) → vendor modules (`wlan.ko`, audio DLKMs, …) still load
- **SUSFS is not enabled** in this build (`CONFIG_KSU_SUSFS` off); KernelSU alone is built in. Notes on backporting it: [`docs/SUSFS-BACKPORT.md`](docs/SUSFS-BACKPORT.md)
- **MHI/modem NULL-deref fix** (two guards) → the modem may fail, the phone no longer panics
- Repack script uses a **raw `Image`** (LG XBL refuses a compressed kernel → `UEFI Crash` / `Sahara Mode`)

---

## Requirements

- LG V60 (`timelm`), bootloader unlocked, **LineageOS 23.2-20261018** (or a nightly whose kernel is still `29902cf733dc`) installed; flash from a **stock Android 13** base first
  - check your build: `adb shell getprop ro.lineage.version` (e.g. `23.2-20261018-NIGHTLY-timelm`)
- Linux build host (tested on an i3-4030U, 8 GB RAM; patience required 🙂), ~30 GB disk
- Toolchain: **AOSP clang 21 r563880c** (build `14054515`) that must match the official Lineage build; otherwise vermagic/module CRCs drift
- `magiskboot`, `python3`, `git`, `zip`

## Build (quick start)

```bash
# 1. Sources
git clone --depth=1 -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_lge_sm8250 kernel
git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025        # -> KSU_VERSION 35252 / UAPI 6

# 2. Patches
cd kernel
git apply ../patches/0001-lineage-ksu-integration.patch
git apply ../patches/0002-mhi-null-guards.patch
git apply ../patches/0003-setlocalversion-fixed.patch

# 3. Config (ikconfig from the stock boot.img, plus the KSU fragment)
scripts/extract-ikconfig boot-stock.img > .config
cat ../config/ksu.fragment >> .config
make ARCH=arm64 olddefconfig

# 4. Build
./../scripts/build.sh          # Image + modules
./../scripts/repack.sh         # boot.img via magiskboot, raw Image
```

Full instructions and environment variables: [`docs/BUILDING.md`](docs/BUILDING.md).

## Flash

```bash
fastboot boot boot-sukisu.img          # test first, writes nothing
fastboot flash boot boot-sukisu.img    # once you are confident
```

Verify:

```bash
adb shell su -c "cat /proc/version"                # must carry the stock vermagic suffix
adb shell su -c "grep -c ' ksu_' /proc/kallsyms"   # ~350 symbols
adb shell su -c "/data/adb/ksud debug info"        # version 35252, uapi_version 6, runtime built-in
adb shell su -c id                                 # uid=0(root) context=u:r:ksu:s0
```

## Important notes

- `su` from `adb shell` only works once UID `2000` (Shell) is allowlisted in the manager (Superuser → *show system apps* → **Shell**). Without it, the shell answers `su: inaccessible or not found`; that is **not** a broken root.
- The manager build **must** match the driver. Driver `35252` (UAPI 6) ↔ manager `35171` (UAPI 4) → "Manager update required" banner and no userspace (`ksud`) installed. Use the nightly build matching the commit.
- A Lineage OTA will overwrite `boot` → root is gone, reflash required. If the OTA moves the kernel to a new commit, the vermagic changes: rebuild (or module loading may break) instead of reusing this image.

## Known issues (ROM-side, not kernel)

- **WiFi**: `cnss` fails to load `regdb.bin` (looked up in six paths, missing) → connection can be flaky. Not caused by this kernel.
- **`ro.product.model` = `UNKNOWN`** on some builds (while `system_ext`/`vendor_dlkm` still report `LM-V600`). Cosmetic; fixable with `resetprop`.
- **No SIM**: the external modem fails to boot, harmless now (patched), but no cellular at all.
- Widevine drops to L3, Dual Screen case unsupported (ROM limitations, not kernel).

## Credits

- [LineageOS](https://github.com/LineageOS) for the `lge_sm8250` kernel and `timelm` device tree
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) / [BakaSU](https://github.com/Baka-SU/BakaSU) (the 4.19-compatible KernelSU fork)
- [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk) (provides `magiskboot`)

## License

Kernel patches follow the license of their sources: **GPL-2.0**. Scripts in this repo: MIT.
