# TROUBLESHOOTING — kasus nyata di LG V60 (timelm)

Semua ini kejadian beneran waktu nge-build; semoga nghemat waktu kamu.

---

## 1. SukiSU Ultra `main` gagal compile di 4.19

Butuh API ≥ 5.4: `fsnotify handle_inode_event`, `seccomp.filter_count`,
`selinux_state.policy`, `iopoll`, `remap_file_range`, `uapi/linux/mount.h`.

→ Pakai **ReSukiSU / BakaSU** (fork) yang punya guard `KSU_COMPAT_USE_SELINUX_STATE`.

## 2. `su: inaccessible or not found` padahal "Working (Built-in)"

Penyebab paling umum: **UID 2000 (Shell) belum di-allowlist**.

Kernel cuma "percaya" proses di domain `u:r:ksu:s0`. `adb root` jalan di `u:r:su:s0`
→ tetap ditolak. Ini **bukan** tanda root rusak.

Perbaikan: manager → **Superuser** → tampilkan system apps → grup **Shell** → enable.
Tes: `adb shell su -c id` → `uid=0(root) context=u:r:ksu:s0`.

## 3. Banner "Manager update required" (UAPI mismatch)

`KSU_VERSION = 30000 + git rev-list-count + 700`.
Contoh: `git describe` = `v4.2.0-rc3-81-gd5e9e025` → 35171 + 81 = **35252**, sedangkan
manager rilis rc3 = **35171** → UAPI 6 vs 4 → userspace (`ksud`) tidak dipasang.

Solusi: pakai manager build yang cocok. Rilis GitHub `ReSukiSU/BakaSU` hanya sampai
`rc3 (35171)`; build `35252` diambil dari nightly:

```
https://nightly.link/Baka-SU/BakaSU/workflows/build-manager/main/Manager-release.zip
```

Cek: `ksud debug info` → `version: 35252`, `uapi_version: 6`.

## 4. ⚠️ Panic `mhi_deinit_free_irq` / `mhi_deinit_dev_ctxt` (modem)

Gejala: HP jalan ±2–3 menit lalu reboot sendiri, `ro.boot.bootreason = kernel_panic`.

Penyebab: **modem eksternal SDX55M gagal boot** (paling gampang direproduksi: **tanpa SIM**),
lalu jalur cleanup MHI men-dereference resource yang tidak pernah dialokasi:

```
Unable to handle kernel NULL pointer dereference at 0x00000004
pc : mhi_deinit_free_irq+0x54
 mhi_power_down → mhi_arch_esoc_ops_power_off → esoc_client_link_power_off
 esoc → mdm_subsys_retry_powerup_cleanup → mdm_handle_boot_fail → mdm_subsys_powerup
```

Setelah guard pertama dipasang, panic **bergeser** ke `mhi_deinit_dev_ctxt+0xec` (NULL `mhi_ctxt`).
Keduanya sudah ditambal di `patches/0002-mhi-null-guards.patch`:

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

Hasil: modem tetap gagal (tidak ada seluler), tapi **kernel tidak panic**.

Opsional (hemat CPU, hilangkan retry): `stop vendor.mdm_helper` + `stop vendor.mdm_launcher`
(service `vendor.per_mgr` / `pm-service` **jangan** dimatikan — dia juga mengatur subsistem lain).

## 5. `LGE Crash Handler: UEFI Crash` → `Enter Sahara Mode`

Kernel di `boot.img` **terkompresi**. LG XBL hanya mau **Image mentah**.

Penyebab klasik: `Image.gz` di-gzip dua kali, lalu `magiskboot` cuma mengurai satu lapis.
Cek: `magiskboot unpack boot.img && file kernel` → harus
`Linux kernel ARM64 boot executable Image`.

## 6. Vermagic berubah jadi ada `+`

`out/` di dalam source membuat git tree dianggap dirty → `setlocalversion` menambah `+`.
Solusi: hardcode suffix (`patches/0003-setlocalversion-fixed.patch`) atau taruh `out/`
di luar source / `.git/info/exclude`.

## 7. `dmesg` kosong walau root (Android 16 / Lineage 23)

`klogctl` dibatasi SELinux. Untuk forensik crash pakai **pstore**:

```bash
adb root    # Lineage userdebug
adb shell "cat /sys/fs/pstore/console-ramoops-0" > crash.txt
adb shell "cat /sys/fs/pstore/pmsg-ramoops-0" > pmsg.txt
adb shell getprop ro.boot.bootreason
```

`pstore` **tertimpa setiap boot** — tarik segera setelah reboot, sebelum reboot lagi.

## 8. `ro.product.model` = `UNKNOWN`

Bukan kernel: prop `system_ext`/`vendor_dlkm` tetap `LM-V600`, sementara
`ro.product.model`/`system`/`vendor` jatuh ke `UNKNOWN`. Kosmetik; bisa ditambal
`resetprop ro.product.model LM-V600` lewat module.
