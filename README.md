# Refracta-on-Debian-13-with-KDE

Scripts to make [Refracta](https://sourceforge.net/projects/refracta/) work on Debian 13 (trixie) with KDE Plasma — pack a running operating system into a bootable ISO and install it on another machine.

## Background

The goal is to customize a Debian 13 + KDE Plasma desktop, then use Refracta to snapshot it into a live ISO and install that ISO on other machines (e.g. via VirtualBox for testing, then bare metal).

Two problems had to be solved:

1. **Refractainstaller only supports ext2/ext3/ext4.** There was no way to install onto btrfs, let alone btrfs with subvolumes — the installer would silently reformat a pre-created btrfs partition to ext4, destroying all subvolumes.

2. **The installed system would not boot under VirtualBox EFI.** Refractainstaller's default config does not create the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader, relying entirely on an NVRAM boot entry. VirtualBox's EFI NVRAM support is unreliable, and NVRAM does not travel with the disk — so the installed system could not boot. Additionally, the installer's EFI partition mounting logic had no error checking — if the ESP mount failed silently, `grub-install` would run with no ESP available and fail, but the error was non-obvious and the installer would continue.

These files solve both problems and automate the setup.

## Files

### `install_and_prepare_refracta_on_debian13.sh`

**One-time setup script. Run on the source machine (the one you'll snapshot).**

Downloads, installs, and configures all Refracta tools on a fresh Debian 13 x64 installation. Idempotent — safe to run multiple times; each step checks the current state and skips work already done.

```bash
sudo bash install_and_prepare_refracta_on_debian13.sh
```

What it does:

1. **Downloads** the five Refracta `.deb` packages from SourceForge.
2. **Installs** them via `apt-get install` (which resolves dependencies), plus `btrfs-progs` for btrfs support.
3. **Holds** `refractainstaller-base` and `refractainstaller-gui` (`apt-mark hold`). These packages carry the btrfs patch and are installed manually from SourceForge `.deb`s, so no apt repository provides them and a normal `apt upgrade` will never touch them. The hold is a safeguard against a future apt-driven reinstall/upgrade (e.g. if Refracta ever lands in Debian's repos) silently overwriting the patched `/usr/bin/refractainstaller{,-yad}` with a stock version.
4. **Sets `COMPRESS=gzip`** in `/etc/initramfs-tools/initramfs.conf` and rebuilds the initramfs for all kernels. (The default compression can cause boot issues with some live-boot configurations.)
5. **Uncomments `media_opt="--force-extra-removable"`** in `/etc/refractainstaller.conf`. This makes `grub-install` create the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader, fixing the VirtualBox EFI boot failure.

After this script completes, apply the btrfs patch (below) if you want btrfs support, then run the seed script (below), then run `refractasnapshot` to create the ISO.

### `btrfs-support-for-refractainstaller.patch`

**Patch for refractainstaller. Adds btrfs filesystem support, fixes EFI partition mounting, and adds dual logging.**

A standard unified diff that patches both the GUI and CLI versions of refractainstaller (`/usr/bin/refractainstaller-yad` and `/usr/bin/refractainstaller`).

```bash
sudo patch -p1 -d / < btrfs-support-for-refractainstaller.patch
```

The patch has evolved through nine versions:

#### v1 — btrfs filesystem support

Adds two new options to the filesystem selection menu:

| Option | Behaviour |
|---|---|
| **btrfs (single partition)** | Formats the root partition as btrfs. Single fstab entry, no subvolumes. The top-level btrfs volume (subvolid=5) is mounted as `/`. |
| **btrfs (with subvolumes)** | Formats as btrfs and creates five subvolumes, mounts each at its mount point before rsync, generates multi-entry fstab with `subvol=` options. |

Default subvolumes created by the "with subvolumes" option (this built-in set is the **fallback** only — as of v5 the real layout is learned from the disk; see below):

| Subvolume | Mount point |
|---|---|
| `@rootfs` | `/` |
| `@home` | `/home` |
| `@var` | `/var` |
| `@tmp` | `/tmp` |
| `@snapshots` | `/.snapshots` |

Additional behaviour:

- When "btrfs (with subvolumes)" is selected, the separate `/home` partition option is automatically disabled (with a user notification) because `/home` becomes a subvolume.
- When the "Do not format" option is used on a partition that is already btrfs, the patch auto-detects whether subvolumes exist (by checking for `@rootfs`) and sets the mode accordingly. This allows pre-formatting with a custom disk setup script and then running the installer with "Do not format" to use the existing layout.
- The `update-initramfs` condition is extended to rebuild when btrfs is selected, ensuring btrfs modules and tools are included in the initramfs.
- A runtime check for `btrfs-progs` (`mkfs.btrfs`) is performed with a user-friendly error message if missing.
- ext2/ext3/ext4 paths are unchanged — the patch only adds new branches.

#### v2 — btrfs bug fixes

Two bugs discovered during real installation testing:

- **Subvolume creation with `no_format=yes`**: v1 tried to create subvolumes even when "Do not format" was selected and the subvolumes already existed, causing a non-fatal "File exists" error. Fixed by moving subvolume creation inside the `no_format` check — subvolumes are now only created when actually formatting.
- **Duplicated `rootflags` in kernel command line**: v1 used `sed` to add `rootflags=subvol=@rootfs` to `GRUB_CMDLINE_LINUX_DEFAULT`, but `update-grub` (grub-mkconfig) already auto-detects btrfs subvolume roots and adds this parameter automatically. The `sed` caused the parameter to appear twice in the kernel command line. Fixed by removing the redundant `sed` — `update-grub` handles it.

#### v3 — EFI boot fixes + dual logging

Three categories of fixes discovered when the installed system still wouldn't boot despite v2:

**EFI partition mounting:**

The original installer had no error checking on the ESP mount. The exact sequence that broke: when using a separate `/boot` partition, rsync copies the live system's `/boot/efi/` directory (with bootloader files) onto the `/boot` partition. Later, `mkdir /target/boot/efi` fails silently (directory already exists from rsync), and `mount "$esp_dev" /target/boot/efi/` has no error checking — if it fails, `grub-install` runs with no ESP available and fails, but the installer continues (the user clicks "Continue" on the error dialog).

Fixes applied:

- `mount $boot_dev /target/boot` now has `check_exit` — failure is caught, not silent.
- `mkdir` changed to `mkdir -p` — no more silent failure when the `efi/` directory already exists from rsync.
- The ESP is explicitly unmounted from any existing mount point (e.g. the live system's `/boot/efi`) before being mounted at `/target/boot/efi`, preventing "device already mounted" failures.
- `mount "$esp_dev" /target/boot/efi/` now has `check_exit` — if it fails, the installer aborts with a clear error message instead of continuing to a broken `grub-install`.
- `install_grub()` verifies the ESP is actually mounted before running `grub-install` in EFI mode — aborts with a clear error if not.
- The `chroot /target mount $boot_dev /boot` in `install_grub()` is now non-fatal (`|| true`) since `/boot` may already be mounted from the fstab/ESP setup phase.

**Dual logging:**

The installer's error log (`/var/log/refractainstaller.log`) lives on the live system's filesystem. When `grub-install` fails, the error goes to the live system's log — but the only log that survives after reboot is the one rsync'd to the target disk, which is a snapshot from before `grub-install` ran. The actual error is lost.

Fixes applied:

- After rsync completes, a background `tail -n +1 -F` process mirrors the installer's error log to `/target/var/log/refractainstaller.log` in real-time. Both the live system and the target disk have byte-for-byte identical logs at every point during the install.
- `clean_log()` (GUI only) now sanitizes plaintext passwords in both log copies.
- At the end of the install, the tail process is stopped and a final `cp` sync is performed.
- If the install crashes or the user examines either disk, both logs contain the same information.

#### v4 — findmnt fix for nested mount verification

Discovered during a real install test: the ESP mount verification added in v3 used `df | grep -q "/target/boot/efi"` to check if the ESP was mounted. However, `df` without arguments only shows top-level mount points — it does not list nested mounts. Since `/target/boot/efi` is mounted **under** `/target/boot` (which is under `/target`), `df` collapses it and the grep fails — even when the ESP is correctly mounted. This caused the installer to abort with "EFI partition is not mounted" despite the mount being perfectly fine.

Fix applied:

- Replaced all `df | grep` ESP verification checks with `findmnt`, which reliably detects nested mounts. This affects three checks per script: the ESP pre-unmount check, the post-mount verification, and the `install_grub()` pre-flight check.

#### v5 — learn the subvolume layout from the disk + NoCoW swapfile

Up to v4 the subvolume scheme was hard-coded in the installer (`@rootfs @home @var @tmp @snapshots`). That meant any disk created with a different layout (e.g. `disk_setup_for_btrfs_desktop_subvolumes.sh`, which uses `@var_log @var_cache @libvirt_images @swap …`) would have its extra subvolumes **silently ignored** — their contents would land inside `@rootfs` instead of on their own subvolume. v5 removes the hard-coding entirely.

**The installer now learns the layout from the disk:**

- The disk-setup script writes a manifest at the btrfs **top level (subvolid=5)** called `.refracta-btrfs-layout`, with one TAB-separated `<subvolume><TAB><mountpoint>` line per subvolume.
- A new `load_btrfs_layout()` function mounts subvolid=5 and:
  1. reads the manifest if present (**authoritative** — any layout, any subvolume names);
  2. otherwise **discovers** the existing subvolumes via `btrfs subvolume list` and guesses mountpoints by convention (`btrfs_guess_mount`, e.g. `@var_log → /var/log`, `@libvirt_images → /var/lib/libvirt/images`);
  3. sorts entries by mountpoint depth so **parents mount before children**;
  4. derives the **root subvolume** (whichever maps to `/`) instead of assuming the name `@rootfs`.
- The installer's own "btrfs (with subvolumes)" format menu still uses the built-in fallback arrays, but now also **writes the manifest** into the freshly-created filesystem so it can be re-learned on a later reinstall.

Why a manifest rather than inferring from names? A btrfs subvolume stores no mountpoint metadata, and names alone are ambiguous — `@libvirt_images` cannot be mapped to `/var/lib/libvirt/images` by any naming rule, and `@snapshots → /.snapshots`, `@swap`, and `@rootfs → /` are all special cases. The manifest makes the disk-setup script the single source of truth and the installer fully layout-agnostic. (Name-convention discovery is kept only as a best-effort fallback for disks that have no manifest.)

**btrfs swapfile fix:**

A btrfs swapfile must be NoCoW or `swapon` fails with "swapfile has holes". The installer's original `dd`-based swapfile creation produced a CoW file on btrfs and would not activate. v5:

- creates the swapfile with `chattr +C` on an empty file **before** writing any data, for both plain btrfs and subvolume layouts;
- when the layout has a dedicated `@swap` subvolume, creates the swapfile **inside it** (e.g. `/swap/swapfile`), keeping it out of root snapshots, and points the fstab swap entry at the real path.

#### v6 — EFI + separate `/boot` grub fix + RAM-sized swap

Found during a real "Do not format" btrfs-subvolumes install (which otherwise verified perfectly — manifest learning, all 8 subvolumes mounted, fstab, NoCoW swapfile).

**`grub-install: cannot find EFI directory` (EFI + separate `/boot`):**

With an EFI install that uses a separate `/boot` partition, the ESP-setup phase mounts `$boot_dev` at `/target/boot` and then the ESP at `/target/boot/efi` (a child mount under `/boot`). `install_grub()` then ran `chroot /target mount $boot_dev /boot` **again**, stacking a second `/boot` mount that **shadowed** the ESP — so inside the chroot `/boot/efi` was an empty dir on the fresh `/boot` partition, not the FAT ESP, and `grub-install` failed. This is a pre-existing upstream bug (not btrfs-related); our earlier `|| true` made the remount non-fatal but didn't stop the shadowing.

Fix: a `findmnt /target/boot` guard skips the redundant chroot remount when `/boot` is already mounted (the EFI path), while still mounting it for the BIOS / no-ESP path:

```bash
if [[ -n $boot_dev ]] ; then
    if ! findmnt /target/boot >/dev/null 2>&1 ; then
        chroot /target mount $boot_dev /boot 2>/dev/null || true
    fi
fi
```

**RAM-sized swapfile:**

The stock swapfile default is 256 MiB (`swapfile_count=262144`), which rounds to **0 GiB** in `free -g` and is useless on a desktop. The swapfile is now sized to **match the target machine's RAM** (rounded up to a whole GiB), auto-detected from `/proc/meminfo` at install time — large enough to be useful and to support hibernation. This applies to **every filesystem** (ext2/3/4 and btrfs), not just btrfs; it falls back to the configured size if RAM can't be read. On btrfs the swapfile is additionally made NoCoW (see above). (`chmod` now precedes `mkswap`, dropping the harmless "insecure permissions" warning.) Actually hibernating to the swapfile also needs `resume=`/`resume_offset=` kernel parameters — wired up in v7 below.

#### v7 — hibernation (resume from swap), all scenarios

v6 sized swap large enough for hibernation; v7 configures the system to actually resume from it. `configure_resume()` handles every swap scenario:

| Scenario | `resume=` | `resume_offset=` |
|---|---|---|
| swapfile on btrfs (incl. `@swap` subvolume) | UUID of the btrfs filesystem | `btrfs inspect-internal map-swapfile -r` |
| swapfile on ext2/3/4 | UUID of the root filesystem | first physical block from `filefrag` |
| existing swap partition | UUID of the swap partition | (none) |

For each, it writes `RESUME=UUID=<dev>` to `/etc/initramfs-tools/conf.d/resume` and appends `resume=UUID=<dev> [resume_offset=N]` to `GRUB_CMDLINE_LINUX_DEFAULT`, then `update-grub` + `update-initramfs` pick them up (the initramfs rebuild now also triggers when resume is configured, so it works on plain ext4 installs too). A swapfile install only enables resume if the offset was successfully obtained, and the whole thing is **skipped for encrypted root** (resuming from encrypted swap needs additional setup).

> **VirtualBox caveat:** S4/hibernation generally does **not** work under VirtualBox (its EFI/ACPI doesn't reliably trigger the kernel's resume). Everything is configured correctly, but test actual hibernate/restore on **bare metal**.

#### v8 — in-tool manifest help (discoverable without this README)

The manifest-driven flow is now explained from inside the installer, so a user who has never seen this README can understand and use it:

- **CLI:** `refractainstaller --btrfs-manifest` prints an explanation of the flow, an example `.refracta-btrfs-layout`, and a copy-pasteable recipe that creates the partitions' subvolumes + a valid (real-TAB) manifest. It's also listed in `refractainstaller --help`.
- **GUI:** an **"Explain btrfs subvolumes"** button on the Partitioning page (next to *Run GParted*) shows the same text in a scrollable window. That page now loops, so closing the help returns you to it.

Both share the same wording, and the recipe shown was verified to parse correctly through the installer's own manifest reader.

#### v9 — guided disk setup + disk-state first screen (GUI)

So you no longer have to run a disk-prep script separately, the GUI can build the disk itself — and it now states its destructive potential up front.

- **Disk-state first screen:** before anything else, `refractainstaller-gui` shows a disk inventory (`lsblk`), detects and labels the **live boot medium**, and warns that some choices erase a whole disk — then Continue/Exit.
- **"Auto-create btrfs layout" button** on the Partitioning page (single disk): lists eligible whole disks (**excluding the live medium and any mounted disk**), requires you to **type the device path** to confirm, then partitions ESP + `/boot` + btrfs(subvolumes) and writes the manifest — after which the install continues non-interactively over the "Do not format" path (the manifest is learned). Requires a UEFI boot; not combined with encryption.
- **Shared library `btrfs-disk-lib.sh`** (installed to `/usr/lib/refractainstaller/`): the single source of truth for the layout + partition/manifest logic, used by both the guided GUI mode and the standalone `disk_setup_for_btrfs_desktop_subvolumes.sh`. Change the layout in one place.

The CLI installer is unchanged in v9 (guided mode is GUI-only); manual partitioning and the existing "Do not format" path are untouched — guided mode is purely additive and opt-in.

### `btrfs-disk-lib.sh`

Shared library defining `REFRACTA_BTRFS_LAYOUT` (the 8-subvolume layout), the manifest filename, and the functions that partition a disk, create the subvolumes, and write the manifest. The patch installs it to `/usr/lib/refractainstaller/btrfs-disk-lib.sh`; the standalone subvolumes script sources it (falling back to a copy beside the script). Edit the layout here and both the installer's guided mode and the standalone script follow.

### `disk_setup_for_btrfs_desktop_plain.sh` / `disk_setup_for_btrfs_desktop_subvolumes.sh`

**Disk partitioning scripts. Run from the Refracta live ISO on the target machine before running refractainstaller.** Pick one:

- `disk_setup_for_btrfs_desktop_plain.sh` — plain btrfs root, no subvolumes.
- `disk_setup_for_btrfs_desktop_subvolumes.sh` — btrfs with subvolumes for effective snapshots, **and writes the layout manifest** the installer learns from.

Both wipe the target disk and create a GPT partition table, ready for the "Do not format" installer path.

```bash
sudo bash disk_setup_for_btrfs_desktop_subvolumes.sh   # or _plain.sh
```

Both create the same three-partition layout on `/dev/nvme0n1` (configurable at the top of the script):

| Partition | Size | Type | FS | Mount |
|---|---|---|---|---|
| p1 | 1024 MiB | EF00 (EFI System) | FAT32 | `/boot/efi` |
| p2 | 1024 MiB | 8300 (Linux) | ext4 | `/boot` |
| p3 | ~253 GiB | 8300 (Linux) | btrfs | `/` (plain, or subvolumes) |

The **subvolumes** script defines its layout once (a single `subvol:mountpoint` array) and creates these subvolumes on p3, then records them in the `.refracta-btrfs-layout` manifest at the btrfs top level:

| Subvolume | Mount point |
|---|---|
| `@rootfs` | `/` |
| `@home` | `/home` |
| `@var_log` | `/var/log` |
| `@var_cache` | `/var/cache` |
| `@libvirt_images` | `/var/lib/libvirt/images` |
| `@swap` | `/swap` (NoCoW swapfile created here by the installer) |
| `@tmp` | `/tmp` |
| `@snapshots` | `/.snapshots` |

To change the layout, just edit the `BTRFS_LAYOUT` array at the top of the subvolumes script — the installer learns whatever you put there, with no code changes. After the script runs, launch `refractainstaller-gui` and select **"Do not format"** — the installer reads the manifest and mounts every subvolume at its recorded mountpoint, writes the matching fstab, and puts the swapfile in `@swap`.

### `refracta_seed_home_environment_before_iso_creation.sh`

**Seed script. Run as your regular user (not root) before taking a snapshot.**

Copies your current user's full KDE Plasma 6 configuration, application settings, and dotfiles into `/etc/skel` so that the resulting ISO boots as a near-identical clone of your running desktop. When the live system (or a newly installed system) creates a new user, it will inherit all your settings.

```bash
bash refracta_seed_home_environment_before_iso_creation.sh
```

What it copies into `/etc/skel`:

- Shell dotfiles (`.bashrc`, `.zshrc`, `.profile`, etc.)
- KDE Plasma 6 core config (`kdeglobals`, `kwinrc`, `plasmarc`, shortcuts, activities, power management, etc.)
- KDE application data (`dolphin`, `konsole`, `kate`, `spectacle`, `okular`, color schemes, icons, fonts, etc.)
- All other `~/.config/` application configs (Firefox, VSCode, terminals, editors, etc.)
- `~/.local/bin/` custom binaries
- GTK 3/4 integration configs
- Autostart entries

What it intentionally excludes:

- `~/.cache/` (regenerated at runtime)
- `~/.local/share/Trash/`, `thumbnails/`, `baloo/`, `akonadi/`
- `~/.local/share/kwalletd/` (encrypted passwords — security)
- `~/.config/pulse/`, `dconf/` (runtime/session-specific)
- `*.lock`, `*.pid`, `*.socket` files

Ownership of `/etc/skel` is set to `root:root` after copying. The live system re-chowns to the new user automatically.

## Workflow

```
┌─────────────────────────────────────────────────────────┐
│  SOURCE MACHINE (the desktop you want to clone)         │
│                                                         │
│  1. sudo bash install_and_prepare_refracta_on_debian13  │
│  2. sudo patch -p1 -d / < btrfs-support-...patch        │
│  3. bash refracta_seed_home_environment_...sh           │
│  4. sudo refractasnapshot   →  produces custom ISO      │
└─────────────────────────────────────────────────────────┘
                          │ ISO
                          ▼
┌─────────────────────────────────────────────────────────┐
│  TARGET MACHINE (VirtualBox or bare metal)              │
│                                                         │
│  1. Boot from the ISO                                   │
│  2. Run refractainstaller-gui                           │
│     → first screen shows disk state + warning           │
│     → Partitioning page: "Auto-create btrfs layout"     │
│       builds ESP+/boot+subvolumes+manifest for you,     │
│       OR prep manually (GParted / disk_setup_*.sh) and  │
│       use "Do not format" so it learns the layout       │
│  3. Reboot — system boots with EFI fallback bootloader  │
└─────────────────────────────────────────────────────────┘
```

## Requirements

- Debian 13 (trixie) x64
- KDE Plasma 6 (for the seed script to be useful)
- Root access (for install script and patch)
- `wget`, `patch`, `initramfs-tools` (all standard on Debian)

## Refracta Versions

| Package | Version | Source |
|---|---|---|
| refractasnapshot-base | 10.4.3 | SourceForge |
| refractasnapshot-gui | 10.4.1 | SourceForge |
| refractainstaller-base | 9.6.6 | SourceForge |
| refractainstaller-gui | 9.6.6 | SourceForge |
| refracta2usb | 2.4.3 | SourceForge |

> **Note:** The snapshot base (10.4.3) and gui (10.4.1) version numbers differ intentionally. Per the maintainer's note: *"Use latest available version of -gui with latest version of -base, even if numbers are different."*

## License

MIT — see [LICENSE](LICENSE).

The Refracta patch is submitted upstream to the Refracta maintainer (fsmithred) for potential inclusion in a future release. Refracta itself is GPL-3.

