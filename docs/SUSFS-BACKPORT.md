# SUSFS v2.3.0 on this 4.19 NonGKI kernel

`patches/0004-susfs-v2.3.0-4.19.patch` backports the kernel side of
[susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) **`gki-android12-5.10` @ `eb95da0` (v2.3.0)**
to LineageOS `android_kernel_lge_sm8250` @ `29902cf733dc` (4.19.325), for ReSukiSU
`d5e9e025` (KSU_VERSION 35252).

Status: builds with `-Werror` (0 errors, 0 warnings), flashed and booted on an `LM-V600VM`.
`ksu_susfs show version` → `v2.3.0`, `show variant` → `NON-GKI`, all 9 features enabled.
The hiding rules themselves (module + detector apps) were **not** tested yet: SUSFS in the kernel
is only the mechanism, the paths/mounts to hide come from the userspace module.

## Why not the `kernel-4.19` branch

It is still v1.5.5 (Feb 2025). Current ReSukiSU only tracks the latest SUSFS ("we don't maintain
ANY backward compatibility for old version of susfs") and calls functions v1.5.5 does not have
(`susfs_add_sus_map`, `susfs_add_sus_path_loop`, `susfs_is_current_proc_umounted`, …), and it
checks for the `ksu_selinux_hide_running` hook in `security/selinux/hooks.c`.

## Apply

```bash
cd kernel
git apply ../patches/0001-lineage-ksu-integration.patch
git apply ../patches/0003-setlocalversion-fixed.patch
git apply ../patches/0004-susfs-v2.3.0-4.19.patch
cat ../config/susfs.fragment >> out/.config     # after extract-ikconfig, see BUILDING.md
```

`0004` is a diff on top of `0001` + `0003`. In ReSukiSU, `KSU_SUSFS` and `KSU_MANUAL_HOOK` are one
Kconfig `choice` (hooking method), so `0004` removes the manual hooks of `0001` from `exec.c`,
`open.c`, `stat.c`, `reboot.c` and puts the SUSFS inline hooks in their place. It also adds
`fs/susfs.c`, `include/linux/susfs.h` and `include/linux/susfs_def.h` (upstream files, plus the
4.19 changes listed below). `0002` is not needed.

The build log should show all seven hook checks:

```
-- BakaSU/susfs_feature_check: selinux_hide manual hook found
-- BakaSU/susfs_inline: ksu_handle_execveat found
-- BakaSU/susfs_inline: ksu_handle_faccessat found
-- BakaSU/susfs_inline: ksu_handle_input_handle_event found
-- BakaSU/susfs_inline: ksu_handle_setresuid found
-- BakaSU/susfs_inline: ksu_handle_stat found
-- BakaSU/susfs_inline: ksu_handle_sys_read found
-- BakaSU/susfs_inline: ksu_handle_sys_reboot found
-- SUSFS_VERSION: v2.3.0
```

## How it was ported

The 5.10 patch (129 hunks, 25 files) applies with `patch -F3` except 9 hunks, but **fuzz is not
trustworthy here**: several hunks landed in the wrong function (the post-exec hook inside
`set_binfmt()`, declarations inside a comment in `do_faccessat()`, `susfs_statfs_by_dentry()` inside
`vfs_statfs()`, `CL_COPY_MNT_NS` inside `current_chrooted()`). Every hunk was checked for the
function it was meant for, and these files were ported by hand from a clean copy:
`fs/exec.c`, `fs/stat.c`, `fs/namei.c`, `fs/open.c`, `fs/statfs.c`, `fs/proc/fd.c`,
`fs/proc/task_mmu.c`, `security/selinux/avc.c`, `fs/proc/cmdline.c`.

### 4.19 differences and what the port does

| Area | 5.10 | 4.19 port |
|---|---|---|
| `exec.c` | hooks in `do_execveat_common()` | hooks in `__do_execve_file()` |
| module preinit | PID 1 exec retry via `goto orig_flow` | **not hooked**; the retry would have to unwind `displaced`/`in_exec`/`pathname` state of 4.19 and a mistake bootloops. Modules still run from `post-fs-data` |
| `stat.c` | `vfs_fstat()`, `stat->mnt_id` | `vfs_statx_fd()`; `struct kstat` has no `mnt_id` (5.8+), so `SUS_KSTAT` only spoofs the fields 4.19 has |
| `namei.c` lookup | `lookup_fast()` returns a dentry, `try_to_unlazy()` | `lookup_fast()` returns int (0 = fall back to `lookup_slow()`), `unlazy_walk()`; `ND_STATE_*` kept in a new `nameidata.state` |
| open | `open_last_lookups()` + `do_open()` | `do_last()` does both; `ND_STATE_OPEN_LAST` is set in `do_last()` |
| `OPEN_REDIRECT` | re-walk inside `path_openat()` before `do_open()` | in `do_filp_open()`: if the opened inode is flagged, close it and open the redirected path (the pattern SUSFS 1.5.x used on 4.19). Not applied to `O_TMPFILE` |
| `/proc/bootconfig` spoof | `fs/proc/bootconfig.c` | NonGKI has no bootconfig: spoof in LG's `fs/proc/cmdline.c` (after its charger-mode fixup) |
| AVC log spoof | `avc_audit_post_callback()` | `avc_dump_query()`, where 4.19 prints `tcontext` |
| `/proc/<pid>/fdinfo` | adds `ino:` | 4.19 has no `ino:` line; spoofed output keeps the 4.19 format |
| `/proc/mounts`, `mountinfo` | `susfs_show_*()` copies of 5.10 | copies re-synced with Android 4.19, which prefers `->show_options2()` (sdcardfs) |
| `namespace.c` | `vfs_create_mount()`, `mnt_stuck_children` | this LGE tree has the `fs_context` backport (`vfs_create_mount()` exists); `susfs_alloc_*_vfsmnt()` mirror 4.19 `alloc_vfsmnt()` (`mnt.data = NULL`, `init_fs_pin()`) |
| `/proc/<pid>/map_files` | one loop | 4.19 counts and fills in two loops; `SUS_MAP` filter is in both |
| `smaps_rollup` / `pagemap` | mmap lock restart logic | plain loop on 4.19; `walk_page_range(start, end, &walk)` |
| `show_map_vma()` | `VMA_PAD_START()` (GKI VMA padding) | `vma->vm_end` |
| sdcard monitor (`susfs.c`) | `fsnotify_ops.handle_inode_event` | `->handle_event()` with a C-string file name |
| `readdir.c` | declarations at the top | 4.19 has `access_ok()` first; declarations moved up (`-Wdeclaration-after-statement`) |
| `susfs_def.h` | | `#include <linux/cred.h>` for `current_uid()` |

### Flags checked for collisions on 4.19

- `ND_FLAGS_LOOKUP_LAST 0x2000000` vs `LOOKUP_*` (max `0x8000`)
- `STATX_SUS_KSTAT 0x10000000`, `STATX_SUS_KSTAT_FUSE 0x20000000` vs `STATX_*` (cleared in `vfs_statx()` before reaching userspace)
- `VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT 0x80000000` vs `MNT_*` (max `0x8000000`)
- `CL_COPY_MNT_NS BIT(25)` vs `CL_*` (max `0x80`)

### KABI

No struct used by modules changes layout: `Module.symvers` of the SUSFS build has 0 changed CRCs
and 0 removed symbols compared to the KernelSU-only build, and the phone loads the same 34 vendor
modules as stock.

## Verification on the device

```bash
adb push susfs4ksu/ksu_module_susfs/tools/ksu_susfs_arm64 /data/local/tmp/ksu_susfs
adb shell su -c "chmod 755 /data/local/tmp/ksu_susfs"
adb shell su -c "/data/local/tmp/ksu_susfs show version"            # v2.3.0
adb shell su -c "/data/local/tmp/ksu_susfs show variant"            # NON-GKI
adb shell su -c "/data/local/tmp/ksu_susfs show enabled_features"   # 9 CONFIG_KSU_SUSFS_* lines
adb shell su -c "grep -c -E ' (ksu_|susfs_)' /proc/kallsyms"        # 0 (HIDE_KSU_SUSFS_SYMBOLS)
```

Also re-check what #4 of TROUBLESHOOTING lists (model, speaker cnt file, `ESOC_BOOT_DONE`): they
must look like stock.

## Userspace

Install the module from `susfs4ksu/ksu_module_susfs` (same `gki-android12-5.10` checkout) with the
manager. Its `post-fs-data.sh` sets the fake `/proc/cmdline` from a copy of the real one; that
spoof is global, so keep the `androidboot.vendor.lge.*` entries in it.

## Updating

When simonpunk updates `gki-android12-5.10`, ReSukiSU follows it and drops compatibility with the
old version. Re-port by diffing the new upstream patch against `eb95da0`, not by re-applying it
with fuzz.
