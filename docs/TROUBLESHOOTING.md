# TROUBLESHOOTING — real-world cases on the LG V60 (timelm)

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

## 4. ⚠️ `mhi_deinit_free_irq` / `mhi_deinit_dev_ctxt` panic (modem)

Symptom: the phone runs for ~2–3 minutes, then reboots by itself,
`ro.boot.bootreason = kernel_panic`.

Cause: the **external modem SDX55M fails to boot** (easiest reproduction: **no SIM**),
then the MHI cleanup path dereferences resources that were never allocated:

```
Unable to handle kernel NULL pointer dereference at 0x00000004
pc : mhi_deinit_free_irq+0x54
 mhi_power_down → mhi_arch_esoc_ops_power_off → esoc_client_link_power_off
 esoc → mdm_subsys_retry_powerup_cleanup → mdm_handle_boot_fail → mdm_subsys_powerup
```

After the first guard was added, the panic **moved** to `mhi_deinit_dev_ctxt+0xec`
(NULL `mhi_ctxt`). Both are patched in `patches/0002-mhi-null-guards.patch`:

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

Result: the modem still fails (no cellular), but the **kernel no longer panics**.

Optional (saves CPU, stops retries): `stop vendor.mdm_helper` + `stop vendor.mdm_launcher`.
Do **not** stop `vendor.per_mgr` / `pm-service` — it also drives other subsystems.

## 5. `LGE Crash Handler: UEFI Crash` → `Enter Sahara Mode`

The kernel inside `boot.img` is **compressed**. LG XBL only accepts a **raw Image**.

Classic cause: `Image.gz` gzipped a second time, and `magiskboot` only unwraps one layer.
Check: `magiskboot unpack boot.img && file kernel` → must report
`Linux kernel ARM64 boot executable Image`.

## 6. Vermagic gains a trailing `+`

With `out/` inside the source tree, git considers the tree dirty → `setlocalversion`
appends `+`. Fix: hardcode the suffix (`patches/0003-setlocalversion-fixed.patch`), or move
`out/` outside the source tree / add it to `.git/info/exclude`.

## 7. `dmesg` is empty even as root (Android 16 / Lineage 23)

`klogctl` is restricted by SELinux. For crash forensics use **pstore**:

```bash
adb root    # Lineage userdebug
adb shell "cat /sys/fs/pstore/console-ramoops-0" > crash.txt
adb shell "cat /sys/fs/pstore/pmsg-ramoops-0" > pmsg.txt
adb shell getprop ro.boot.bootreason
```

`pstore` is **overwritten on every boot** — pull it immediately after a reboot, before
rebooting again.

## 8. `ro.product.model` reads `UNKNOWN`

Not a kernel issue: `system_ext`/`vendor_dlkm` props still report `LM-V600`, while
`ro.product.model`/`system`/`vendor` fall back to `UNKNOWN`. Cosmetic; fixable with
`resetprop ro.product.model LM-V600` from a module.
