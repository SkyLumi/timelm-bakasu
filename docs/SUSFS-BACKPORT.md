# Adding SUSFS to this 4.19 NonGKI kernel

Upstream states SUSFS is no longer supported on NonGKI kernels and that you must backport
patches from `gki-android12-5.10`. In practice `susfs4ksu` still carries a
`kernel-4.19` branch with a ready patch set. This document is the route I would take to
try it on the LGE `sm8250` tree, plus the parts that will bite you.

> Not tested end to end at the time of writing. Treat it as a starting point, not a
> guarantee. Keep a known good boot image to fall back to.

## 0. Risk

- The patch touches `fs/namei.c`, `fs/stat.c`, `fs/readdir.c`, `fs/namespace.c`,
  `fs/proc/task_mmu.c`, `kernel/kallsyms.c`, `include/linux/sched.h`, `fs/Makefile`.
- Mistakes there mean panics or bootloops. Always test with `fastboot boot` before flashing.
- Expect 2 to 4 build iterations.

## 1. Sources

```bash
git clone -b kernel-4.19 --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git susfs4ksu
```

Useful layout:

```
kernel_patches/50_add_susfs_in_kernel-4.19.patch
kernel_patches/fs/susfs.c
kernel_patches/fs/sus_su.c
kernel_patches/include/linux/susfs.h
kernel_patches/include/linux/susfs_def.h
kernel_patches/include/linux/sus_su.h
kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch   (not used with ReSukiSU)
ksu_module_susfs/                                      (module + prebuilt ksu_susfs_arm64)
```

`10_enable_susfs_for_ksu.patch` targets upstream KernelSU. ReSukiSU already ships the
KernelSU side (`CONFIG_KSU_SUSFS` with 10 options, `#include <linux/susfs.h>`), so only
the kernel side is needed here.

## 2. Copy files and apply the patch

```bash
S=~/timelm/susfs4ksu/kernel_patches
K=~/timelm/kernel

cp $S/fs/susfs.c   $K/fs/
cp $S/fs/sus_su.c  $K/fs/
cp $S/include/linux/susfs.h $S/include/linux/susfs_def.h $S/include/linux/sus_su.h $K/include/linux/

cd $K
patch -p1 --dry-run < $S/50_add_susfs_in_kernel-4.19.patch   # inspect first
git apply --3way --reject $S/50_add_susfs_in_kernel-4.19.patch
```

Likely conflicts on this tree:

| File | Reason |
|---|---|
| `fs/namei.c` | Lineage backports change function context |
| `fs/stat.c` | already carries `ksu_handle_stat` hooks |
| `fs/readdir.c` | `iterate_dir` context differs from upstream 4.19 |
| `fs/proc/task_mmu.c` | Qualcomm vendor modifications |
| `kernel/sys.c` | ReSukiSU already adds hooks there |

Resolve by re-inserting the `#include <linux/susfs.h>` and the `susfs_*` calls at the
equivalent places, not by copying line numbers. Then check:

```bash
grep -rn "<<<<<<<\|>>>>>>>" fs/ kernel/ include/ | head
find . -name "*.rej" | head
```

## 3. Config

```bash
scripts/config --file .config \
  -e KSU_SUSFS -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT \
  -e KSU_SUSFS_SPOOF_UNAME -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -e KSU_SUSFS_OPEN_REDIRECT -e KSU_SUSFS_SUS_MAP \
  -d KSU_SUSFS_ENABLE_LOG

make ARCH=arm64 olddefconfig
```

Notes:

- Leave `KSU_SUSFS_HAS_MAGIC_MOUNT` off unless your manager uses magic mount.
- `SUS_SU` is not supported on NonGKI, do not chase it.
- Enable `KSU_SUSFS_ENABLE_LOG` only while debugging.

## 4. Build and verify

```bash
KERNEL_DIR=~/timelm/kernel TOOLCHAIN=~/timelm/toolchain/clang-r563880c/bin \
  scripts/build.sh

strings out/arch/arm64/boot/Image | grep -m1 "Linux version 4.19.325"   # vermagic must stay identical
grep -c " ksu_" out/System.map
strings out/arch/arm64/boot/Image | grep -c susfs                        # must be > 0
```

Repack with a raw `Image` (see `scripts/repack.sh`), then:

```bash
fastboot boot boot-sukisu-susfs.img
adb shell su -c "cat /proc/susfs_version"
```

## 5. Userspace

```bash
cd ~/timelm/susfs4ksu
zip -r susfs4ksu-module.zip ksu_module_susfs     # includes ksu_susfs_arm64 prebuilt
adb push susfs4ksu-module.zip /sdcard/           # install via manager
```

Or push the tool directly to `/data/adb/ksu/bin/ksu_susfs` and use:

```bash
ksu_susfs show version
ksu_susfs add_sus_path /system/addon.d
ksu_susfs add_sus_mount /system/addon.d
ksu_susfs enable_spoof_uname
```

## 6. Common pitfalls

1. `fs/susfs.c` copied but `fs/Makefile` not patched: build fails with `undefined reference to susfs_*`.
2. `CONFIG_KPROBES=y` can interact badly with some SUSFS paths. If strange errors appear, retry without it.
3. A dirty git tree inside the source adds `+` to vermagic. Hardcode the suffix or move `out/` out of the tree.
4. Driver and manager builds must match (`ksud debug info`).
5. Do not stop `vendor.per_mgr`: it drives more than the modem.

## 7. If it works

Record the exact `ReSukiSU` and `susfs4ksu` commit hashes, export the final
`git diff` as `patches/0004-susfs-4.19.patch`, and attach `ksu_susfs show version`
output. That is what makes the experiment reproducible for the next person.
