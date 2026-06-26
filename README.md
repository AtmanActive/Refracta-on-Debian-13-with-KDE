# Refracta-on-Debian-13-with-KDE

Scripts to make [Refracta](https://sourceforge.net/projects/refracta/) work on Debian 13 (trixie) with KDE Plasma — pack a running operating system into a bootable ISO and install it on another machine.

## Background

The goal is to customize a Debian 13 + KDE Plasma desktop, then use Refracta to snapshot it into a live ISO and install that ISO on other machines (e.g. via VirtualBox for testing, then bare metal).

Two problems had to be solved:

1. **Refractainstaller only supports ext2/ext3/ext4.** There was no way to install onto btrfs, let alone btrfs with subvolumes — the installer would silently reformat a pre-created btrfs partition to ext4, destroying all subvolumes.

2. **The installed system would not boot under VirtualBox EFI.** Refractainstaller's default config does not create the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader, relying entirely on an NVRAM boot entry. VirtualBox's EFI NVRAM support is unreliable, and NVRAM does not travel with the disk — so the installed system could not boot.

These three files solve both problems and automate the setup.

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
3. **Sets `COMPRESS=gzip`** in `/etc/initramfs-tools/initramfs.conf` and rebuilds the initramfs for all kernels. (The default compression can cause boot issues with some live-boot configurations.)
4. **Uncomments `media_opt="--force-extra-removable"`** in `/etc/refractainstaller.conf`. This makes `grub-install` create the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader, fixing the VirtualBox EFI boot failure.

After this script completes, apply the btrfs patch (below) if you want btrfs support, then run the seed script (below), then run `refractasnapshot` to create the ISO.

### `btrfs-support-for-refractainstaller.patch`

**Patch for refractainstaller. Adds btrfs filesystem support (single partition + subvolumes).**

A standard unified diff that patches both the GUI and CLI versions of refractainstaller (`/usr/bin/refractainstaller-yad` and `/usr/bin/refractainstaller`).

```bash
sudo patch -p1 -d / < btrfs-support-for-refractainstaller.patch
```

Adds two new options to the filesystem selection menu:

| Option | Behaviour |
|---|---|
| **btrfs (single partition)** | Formats the root partition as btrfs. Single fstab entry, no subvolumes. The top-level btrfs volume (subvolid=5) is mounted as `/`. |
| **btrfs (with subvolumes)** | Formats as btrfs and creates five subvolumes, mounts each at its mount point before rsync, generates multi-entry fstab with `subvol=` options, and adds `rootflags=subvol=@rootfs` to the GRUB kernel command line. |

Default subvolumes created by the "with subvolumes" option:

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

### `disk_setup_for_btrfs_desktop.sh`

**Disk partitioning script. Run from the Refracta live ISO on the target machine before running refractainstaller.**

Wipes the target disk and creates a GPT partition table with btrfs subvolumes, ready for the "Do not format" installer path.

```bash
sudo bash disk_setup_for_btrfs_desktop.sh
```

Creates a three-partition layout on `/dev/nvme0n1` (configurable at the top of the script):

| Partition | Size | Type | FS | Mount |
|---|---|---|---|---|
| p1 | 1024 MiB | EF00 (EFI System) | FAT32 | `/boot/efi` |
| p2 | 1024 MiB | 8300 (Linux) | ext4 | `/boot` |
| p3 | ~253 GiB | 8300 (Linux) | btrfs | `/` (subvolumes) |

Five btrfs subvolumes are created on p3: `@rootfs`, `@home`, `@var`, `@tmp`, `@snapshots`.

After this script runs, launch `refractainstaller-gui` and select **"Do not format"** — the installer (with the btrfs patch applied) will auto-detect the existing subvolumes and mount them correctly.

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
│  2. sudo bash disk_setup_for_btrfs_desktop.sh           │
│  3. Run refractainstaller-gui                           │
│     → select "btrfs (with subvolumes)"                  │
│     → or use "Do not format" with pre-created layout    │
│  4. Reboot — system boots with EFI fallback bootloader  │
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

