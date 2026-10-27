# timelm-kernelsu

**KernelSU (ReSukiSU/BakaSU) built-in untuk LG V60 ThinQ — `timelm` — di LineageOS 23.2 (Android 16, kernel 4.19)**

Repo ini berisi patch + skrip untuk membangun kernel LineageOS 23.2 dengan **KernelSU mode built-in** (bukan LKM), khusus untuk LG V60 (`L-51A`, `LM-V600EA/VM/TM/N`) dan **catatan teknis** soal bug `MHI`/modem yang bikin HP reboot sendiri di kernel hasil rebuild.

> Status: **berfungsi** — root (`su`) jalan, manager BakaSU mendeteksi "Working (Built-in)", dan panic MHI yang muncul saat modem gagal boot sudah ditambal (lihat [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)).

---

## Kenapa repo ini ada

Kernel `4.19` non-GKI **tidak didukung** SukiSU Ultra `main` (butuh API ≥ 5.4: `fsnotify.handle_inode_event`, `seccomp.filter_count`, `selinux_state.policy`, dll). Yang jalan di 4.19 adalah **ReSukiSU / BakaSU** (fork-nya), dengan **manual hooks** karena hook tracepoint hanya untuk GKI 2.0.

Setelah kernel berhasil boot, muncul masalah kedua yang tidak jelas asalnya: HP **panic dan reboot sendiri**. Ternyata bukan KernelSU, tapi **bug error-path driver MHI Qualcomm**: kalau modem eksternal (SDX55M) gagal power-up — misalnya **tidak ada SIM** — `mhi_deinit_free_irq()` / `mhi_deinit_dev_ctxt()` men-dereference pointer yang belum dialokasi. Panic.

Repo ini menyimpan patch + cara build supaya orang lain tidak mengulang 7 iterasi yang sama. 🙂

---

## Fitur

- KernelSU **built-in** (`CONFIG_KSU=y`), **manual hooks** (4.19 compatible)
- Multi-manager support, cocok dengan **BakaSU nightly 35252**
- **Vermagic identik stock** (`4.19.325-cip133-st17-perf-g29902cf733dc`) → modul vendor (`wlan.ko`, audio DLKM, dll) tetap bisa load
- Tambalan bug **MHI/modem NULL-deref** (2 guard) → modem boleh gagal, HP tidak panic
- Skrip repack memakai **Image mentah** (LG XBL menolak kernel terkompresi → `UEFI Crash` / `Sahara Mode`)

---

## Persyaratan

- LG V60 (`timelm`) dengan bootloader unlocked, LineageOS 23.2 terpasang, **stock Android 13 base** sebelum flash ROM
- Linux build host (diuji di i3-4030U, 8 GB RAM — sabar ya 🙂), ~30 GB disk
- Toolchain: **AOSP clang 21 r563880c** (build `14054515`) — **harus** sama dengan build Lineage resmi, kalau tidak vermagic/CRC modul bisa beda
- `magiskboot`, `python3`, `git`, `zip`

## Build (ringkas)

```bash
# 1. Sumber
git clone --depth=1 -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_lge_sm8250 kernel
git clone https://github.com/ReSukiSU/ReSukiSU.git kernel/ReSukiSU
git -C kernel/ReSukiSU checkout d5e9e025        # = versi 35252 / UAPI 6

# 2. Patch
cd kernel
git apply ../patches/0001-lineage-ksu-integration.patch
git apply ../patches/0002-mhi-null-guards.patch
git apply ../patches/0003-setlocalversion-fixed.patch

# 3. Config (ambil ikconfig dari boot.img stock, lalu tambah fragment KSU)
scripts/extract-ikconfig boot-stock.img > .config
cat ../config/ksu.fragment >> .config
make ARCH=arm64 olddefconfig

# 4. Build
./../scripts/build.sh          # Image + modules
./../scripts/repack.sh         # boot.img (magiskboot, Image mentah)
```

Detail lengkap + variabel lingkungan: [`docs/BUILDING.md`](docs/BUILDING.md).

## Flash

```bash
fastboot boot boot-sukisu.img     # tes dulu, tidak menulis partisi
fastboot flash boot boot-sukisu.img   # kalau sudah yakin
```

Verifikasi:

```bash
adb shell su -c "cat /proc/version"          # harus memuat suffix vermagic stock
adb shell su -c "grep -c ' ksu_' /proc/kallsyms"   # ~350 simbol
adb shell su -c "/data/adb/ksud debug info"  # version 35252, uapi_version 6, runtime built-in
adb shell su -c id                           # uid=0(root) context=u:r:ksu:s0
```

## Catatan penting

- `su` dari `adb shell` **hanya jalan** setelah UID `2000` (Shell) di-allowlist di manager (Superuser → *show system apps* → **Shell**). Tanpa itu, shell menjawab `su: inaccessible or not found` — itu **bukan** tanda root rusak.
- Manager **wajib** build yang cocok dengan driver. Driver `35252` (UAPI 6) ↔ manager `35171` (UAPI 4) → banner "Manager update required" dan userspace (`ksud`) tidak terpasang. Pakai build nightly yang sesuai commit.
- OTA Lineage akan menimpa `boot` → root hilang, harus reflash.

## Known issues (ROM-side, bukan kernel)

- **WiFi**: `cnss` gagal load `regdb.bin` (dicari di 6 path, tidak ada) → koneksi bisa rewel. Bukan efek kernel.
- **`ro.product.model` = `UNKNOWN`** pada sebagian build (prop `system_ext`/`vendor_dlkm` masih `LM-V600`). Kosmetik; bisa ditambal `resetprop`.
- **Tanpa SIM**: modem eksternal gagal boot, aman (sudah ditambal) tapi tidak ada seluler sama sekali.
- Widevine turun ke L3, Dual Screen case tidak didukung (keterbatasan ROM, bukan kernel).

## Kredit

- [LineageOS](https://github.com/LineageOS) — kernel `lge_sm8250`, device tree `timelm`
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) / [BakaSU](https://github.com/Baka-SU/BakaSU) — KernelSU fork yang kompatibel 4.19
- [topjohnwu/Magisk](https://github.com/topjohnwu/Magisk) — `magiskboot`

## Lisensi

Patch kernel mengikuti lisensi sumbernya: **GPL-2.0**. Skrip di repo ini: MIT.
