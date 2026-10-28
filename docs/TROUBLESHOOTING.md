# TROUBLESHOOTING: real-world cases on the LG V60 (timelm)

Everything below actually happened while building this kernel. Hopefully it saves you time.

---

## 1. SukiSU Ultra `main` fails to compile on 4.19

It requires API ≥ 5.4: `fsnotify handle_inode_event`, `seccomp.filter_count`,
`selinux_state.policy`, `iopoll`, `remap_file_range`, `uapi/linux/mount.h`.

→ Use **ReSukiSU / BakaSU** (a fork) which has the `KSU_COMPAT_USE_SELINUX_STATE` guard.

## 2. `su: inaccessible or not found` even though the manager says "Working (Built-in)"

Most common cause: **UID 2000 (Shell) is not allowlisted**.

The kernel only trusts processes in the `u:r:ksu:s0` domain. `adb root` runs in
`u:r:su:s0` → still rejected. This is **not** a sign of broken root.

Fix: manager → **Superuser** → show system apps → group **Shell** → enable.
Verify: `adb shell su -c id` → `uid=0(root) context=u:r:ksu:s0`.

## 3. "Manager update required" banner (UAPI mismatch)

`KSU_VERSION = 30000 + git rev-list-count + 700`.
Example: `git describe` = `v4.2.0-rc3-81-gd5e9e025` → 35171 + 81 = **35252**, while the
published rc3 manager is **35171** → UAPI 6 vs 4 → userspace (`ksud`) is never installed.

Fix: use a manager build that matches the driver. GitHub releases of
`ReSukiSU/BakaSU` stop at `rc3 (35171)`; build `35252` comes from the nightly channel:

```
https://nightly.link/Baka-SU/BakaSU/workflows/build-manager/main/Manager-release.zip
```

Check with: `ksud debug info` → `version: 35252`, `uapi_version: 6`.

## 4. `fastboot boot` truncates the kernel command line

Symptoms after `fastboot boot <img>` (any image, **including the stock Lineage `boot.img`**):

- `ro.product.model` = `UNKNOWN`
- the speaker is noticeably quieter
- the phone gets warm while idle
- no cellular; the external modem (SDX55M) never finishes booting
- after a few minutes: reboot / panic (see #5)

Cause: on a RAM boot LG's bootloader passes a cut-down command line, 35 entries instead of 72.
Everything from `androidboot.vendor.lge.*`, `androidboot.revision=`, `androidboot.product.*` and
`lge.*` is gone (even `slub_debug=FZPU` loses its value). Compare:

```bash
adb shell 'cat /proc/cmdline | tr " " "\n" | wc -l'                       # 72 flashed, 35 RAM boot
adb shell 'cat /proc/cmdline | tr " " "\n" | grep -c androidboot.vendor.lge'
```

What depends on those entries:

| Consumer | Entry | Without it |
|---|---|---|
| `init_lge_kona.cpp` (vendor init) | `androidboot.vendor.lge.product.model` | `ro.product.model = UNKNOWN` |
| `tfa98xx.c` (TFA9878 speaker amp) | `androidboot.revision` (12 on retail) | revision 0 ≤ 7 → loads `tfa98xx_reva.cnt` (early-board tuning) instead of `tfa98xx.cnt` |
| fuel gauge / charger (`extension-fg-gen4.c`, `smb5-lib.c`) | `androidboot.vendor.lge.battid`, `plmn`, `hw.revision` | default battery/charger profile |
| SDX55 modem boot | `lge.*` / `sku_carrier` (most likely) | SBL1 completes, `ESOC_BOOT_DONE` never arrives |

Kernel log of the failing modem on a RAM boot:

```
esoc-mdm:Boot trial: 0
esoc sbl : B - ... SBL1, End
esoc-mdm:ESOC_BOOT_FAIL: Send notification: ESOC_INVALID_STATE
esoc-mdm:Doing cold reset by power-down and warm reset
esoc-mdm:Boot trial: 1
[E][mhi_init_pci_dev] Failed to enable MSI, ret:-28
```

Each trial powers the modem and its PCIe link up again (roughly every 100 s), which is the idle
heat. `mdm_helper` configures 5 trials (`Num PON tries configured to 5`); once they are used up,
`mdm_handle_boot_fail()` switches to `BOOT_FAIL_ACTION_PANIC` and calls
`panic("Panic requested on external modem boot failure")` (from the driver code; the test was
stopped at trial 2).

On a **flashed** kernel (stock or ours) the same phone shows 72 entries, `LM-V600`,
`use cnt file rev_no 12, fw_name tfa98xx.cnt`, and `ESOC_BOOT_DONE` ~3.5 s after the first trial,
with or without a SIM.

Fix: never judge audio, thermals, modem or props from a `fastboot boot`. Back up `boot_<slot>`
and flash (see BUILDING.md §6).

## 5. ⚠️ `mhi_deinit_free_irq` / `mhi_deinit_dev_ctxt` panic (modem)

Symptom: the phone runs for ~2-3 minutes, then reboots by itself;
`ro.boot.bootreason = kernel_panic`.

Cause: the **external modem SDX55M fails to boot** (in practice: #4, a `fastboot boot`; it was
first attributed to a missing SIM, which is wrong), then the MHI cleanup path dereferences
resources that were never allocated:

```
Unable to handle kernel NULL pointer dereference at 0x00000004
pc : mhi_deinit_free_irq+0x54
 mhi_power_down → mhi_arch_esoc_ops_power_off → esoc_client_link_power_off
 esoc → mdm_subsys_retry_powerup_cleanup → mdm_handle_boot_fail → mdm_subsys_powerup
```

After the first guard was added, the panic **moved** to `mhi_deinit_dev_ctxt+0xec`
(NULL `mhi_ctxt`). Both are guarded in `patches/0002-mhi-null-guards.patch`:

```c
void mhi_deinit_free_irq(struct mhi_controller *mhi_cntrl)
{
	if (!mhi_cntrl->irq)
		return;
	...
}

void mhi_deinit_dev_ctxt(struct mhi_controller *mhi_cntrl)
{
	if (!mhi_ctxt || !mhi_cntrl->mhi_cmd || !mhi_cntrl->mhi_event)
		return;
	...
}
```

With the guards the oops is gone, but the retries cannot succeed (`Failed to enable MSI, ret:-28`)
and the esoc driver still panics on purpose after the last trial. On a flashed kernel the modem
boots and this path never runs, so `0002` is optional; both published variants were verified
without it.

Do **not** stop `vendor.mdm_helper` / `vendor.mdm_launcher` / `vendor.per_mgr` as a workaround:
the first two are what brings the modem up, `per_mgr` drives other subsystems too.

## 6. `LGE Crash Handler: UEFI Crash` → `Enter Sahara Mode`

The kernel inside `boot.img` is compressed **twice**.

Classic cause: `Image.gz` handed to `magiskboot`, which gzips it again on repack and only unwraps
one layer. Give `repack.sh` the raw `Image`; `magiskboot` recompresses it to the stock format
(gzip, same as the stock `boot.img`). Check: `magiskboot unpack -n boot.img && file kernel` →
`gzip compressed data, ..., original size ...` matching the size of your raw `Image`.

## 7. Vermagic gains a trailing `+`

With `out/` inside the source tree, git considers the tree dirty → `setlocalversion`
appends `+`. Fix: hardcode the suffix (`patches/0003-setlocalversion-fixed.patch`), or move
`out/` outside the source tree / add it to `.git/info/exclude`.

## 8. `dmesg` is empty even as root (Android 16 / Lineage 23)

`klogctl` is restricted by SELinux (also for `su -c dmesg` in the `ksu` domain). The kernel log
is still available through logd: `adb logcat -d -b kernel`. For crash forensics use **pstore**:

```bash
adb root    # Lineage userdebug
adb shell "cat /sys/fs/pstore/console-ramoops-0" > crash.txt
adb shell "cat /sys/fs/pstore/pmsg-ramoops-0" > pmsg.txt
adb shell getprop ro.boot.bootreason
```

`pstore` is **overwritten on every boot**; pull it immediately after a reboot, before
rebooting again.

## 9. `ro.product.model` reads `UNKNOWN`

Not a kernel issue: vendor init builds the model from `androidboot.vendor.lge.product.model` on
`/proc/cmdline` and writes `UNKNOWN` when it is missing. That happens after a `fastboot boot`
(see #4). On a flashed kernel it reads `LM-V600`; no `resetprop` needed.

## 10. SUSFS on this NonGKI kernel

Upstream note (BakaSU/SUSFS): *"SUSFS is no longer supported for NonGKI kernels. If you want to
use SUSFS on a NonGKI kernel, manually backport the patches from the `gki-android12-5.10`
branch."* The `kernel-4.19` branch of `susfs4ksu` is still v1.5.5 (Feb 2025) and lacks what
ReSukiSU `d5e9e025` calls (`susfs_add_sus_map`, `susfs_add_sus_path_loop`, …).

`patches/0004-susfs-v2.3.0-4.19.patch` is that backport (v2.3.0). Notes, limitations and how it
was verified: [`SUSFS-BACKPORT.md`](SUSFS-BACKPORT.md).

- `KSU_SUSFS` and `KSU_MANUAL_HOOK` are one Kconfig `choice`; `0004` replaces the manual hooks of
  `0001` with the SUSFS inline hooks. Use `config/susfs.fragment`.
- SUSFS spoofs `/proc/cmdline` for every process once a fake buffer is set (the official module
  copies the real cmdline and edits bootloader entries). Keep the `androidboot.vendor.lge.*`
  entries in the fake file, or #4 comes back for anything reading the cmdline afterwards.
- SUSFS only hides; it is not a replacement for a valid keybox / Play Integrity setup.
