# timelm-bakasu v1.0.0

First public release — **KernelSU (ReSukiSU/BakaSU) built into the kernel** for the **LG V60 ThinQ (`timelm`)** running **LineageOS 23.2-20261018** (Android 16, kernel 4.19.325-cip133-st17, kernel commit `29902cf733dc`).

## Asset

| File | Description |
|---|---|
| `timelm-bakasu-v1.0.0.zip` | contains `boot-sukisu-v1.img` (ready to flash) |

- Kernel string: `4.19.325-cip133-st17-perf-g29902cf733dc` — **vermagic identical to LineageOS 23.2-20261018**, so vendor modules (`wlan.ko`, audio DLKMs) load normally
- Built from `LineageOS/android_kernel_lge_sm8250` @ `29902cf733dc` (branch `lineage-23.2`)
- KernelSU: built-in (`CONFIG_KSU=y`), manual hooks, `KSU_VERSION 35252` / UAPI 6
- Manager: **BakaSU nightly 35252** (matching driver — `35171` will show "Manager update required")
- SHA256 (`boot-sukisu-v1.img`): `0917428cc22a256d3d171343d3f8c128d670001ec3fc984367cd94ef51ce7d95`
- SHA256 (`timelm-bakasu-v1.0.0.zip`): `9fcd27a828e3fe7374f85ce938416a3332392d0523a7480be6e7974a89d0631b`

## What's inside

- KernelSU built-in for kernel 4.19 non-GKI (ReSukiSU/BakaSU `d5e9e025`)
- **MHI/modem NULL-deref fix** — two guards in the Qualcomm MHI error path. Without them, a modem that fails to boot (e.g. **no SIM**) panics the kernel: `mhi_deinit_free_irq+0x54` and then `mhi_deinit_dev_ctxt+0xec`
- Raw `Image` repack (LG XBL refuses compressed kernels → `UEFI Crash` / `Sahara Mode`)

## Installation

Requirements: bootloader unlocked, **LineageOS 23.2-20261018** installed (`adb shell getprop ro.lineage.version`), **stock Android 13 base** before flashing the ROM, `fastboot`.

```bash
unzip timelm-bakasu-v1.0.0.zip
fastboot boot boot-sukisu-v1.img          # test first — writes nothing
# if it boots and root works:
fastboot flash boot boot-sukisu-v1.img
```

Then install the matching manager:
`https://nightly.link/Baka-SU/BakaSU/workflows/build-manager/main/Manager-release.zip` → `BakaSU_*_35252-arm64-v8a-release.apk`

Grant shell root once (needed for `adb shell su`):
BakaSU → **Superuser** → show system apps → group **Shell** (uid 2000) → enable.

## Verification

```bash
adb shell su -c "cat /proc/version"                # stock vermagic suffix
adb shell su -c "grep -c ' ksu_' /proc/kallsyms"   # ~350
adb shell su -c "/data/adb/ksud debug info"        # 35252 / uapi 6 / built-in
adb shell su -c id                                 # uid=0(root) context=u:r:ksu:s0
```

## Known issues

- No SIM → external modem (SDX55M) cannot boot: no cellular service (no panic anymore, that's the point of the fix)
- WiFi may be flaky: ROM-side `regdb.bin` missing, `cnss` fails to load BDF
- `ro.product.model` may read `UNKNOWN` — cosmetic, `resetprop` fixable
- Lineage OTA overwrites `boot` → root lost, reflash

## Notes

- Tested on `LM-V600VM` with LineageOS 23.2, kernel verified stable after the patch
- Boot image is unsigned/patched — **flashing is at your own risk**
- Kernel sources: [LineageOS/android_kernel_lge_sm8250](https://github.com/LineageOS/android_kernel_lge_sm8250) (GPL-2.0); patches in this repo
