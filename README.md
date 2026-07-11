# Debian 13 to ISO and back
### ( Refracta-on-Debian-13-with-KDE )

Scripts to make [Refracta Tools](https://sourceforge.net/projects/refracta/files/tools/) work on [Debian 13 (trixie)](https://www.debian.org/) with [KDE Plasma](https://kde.org/plasma-desktop/).
Pack a running operating system into a bootable ISO and install it on another machine.

## Purpose

The goal is to allow continuous customization of a Debian 13 + KDE Plasma desktop, while hopping from one machine to the next, including the Live ISO mode.
This enables your operating system to remain yours, no matter how often you change hardware, or even ad-hoc from the Live CD/USB.
Refracta Tools is the software developed to snapshot a running operating system into a live ISO and install that ISO on other machines.

<details>
<summary>But, for Refracta Installer, two problems had to be solved:</summary>

1. **Refractainstaller v9.6.6 only supports ext2/ext3/ext4.** There was no way to install onto btrfs, let alone btrfs with subvolumes, the installer would silently reformat a pre-created btrfs partition to ext4, destroying all subvolumes.

2. **The installed system would not boot under VirtualBox EFI.** Refractainstaller's default config does not create the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader, relying entirely on an NVRAM boot entry. Additionally, the installer's EFI partition mounting logic had no error checking. If the ESP mount failed silently, `grub-install` would run with no ESP available and fail, but the error was non-obvious and the installer would continue.

This repository solves both problems and automates the whole flow: install and configure Refracta, patch the installer for btrfs (with subvolumes, RAM-sized swap, and hibernation), seed your desktop configuration into the ISO, and install onto btrfs on the target machine. Fully automated onto a blank disk, or with full manual control.

</details>

## How to use

<details>
<summary><b>Prerequisites (informational)</b></summary>

- **Debian 13 (trixie) x64** with **KDE Plasma 6**. The desktop only matters for the seed script — everything else works on any Debian 13.
- **Root access** — the install script, the patch, and the target-side disk setup all write to system locations.
- **Bootstrap tools**, already present on a standard Debian install, used to run the setup itself:
  - `wget` — Step 1 downloads the Refracta `.deb`s with it.
  - `patch` — applies `btrfs-support-for-refractainstaller.patch` (Step 2).
  - `sudo`, and `initramfs-tools` (`update-initramfs`) — the latter rebuilds the initramfs for gzip compression and hibernation resume.
- **Disk & filesystem tools for the btrfs workflow.** A base Debian system already ships the core utilities the installer leans on — `util-linux` (`lsblk`, `findmnt`, `blkid`, `wipefs`, `mkswap`), `e2fsprogs` (`mkfs.ext4`, `filefrag`, `chattr`), `coreutils`, `sed`, `grep`, and `grub` — and running Step 1's `apt-get install` on the Refracta `.deb`s automatically pulls in their declared dependencies: `rsync`, `squashfs-tools`, `xorriso`, `mawk`/`gawk`, `yad`, `gparted`, `xterm`, `live-boot`, `syslinux`/`isolinux`, and (as Recommends) `dosfstools` and `cryptsetup`. What Refracta does **not** declare — but the automated/guided btrfs disk setup and the standalone `disk_setup_*.sh` scripts need — are:
  - **`gdisk`** (`sgdisk`) — wipes and GPT-partitions the target disk. This is the one true gap: it is **not a dependency of any Refracta package**, so on a stock system you must install it explicitly (`sudo apt-get install gdisk`).
  - **`btrfs-progs`** (`mkfs.btrfs`, `btrfs`) — creates the btrfs filesystem and subvolumes and maps the swapfile for hibernation resume.
  - **`parted`** (`partprobe`) — re-reads the partition table after `sgdisk`. Usually already present on a KDE desktop (pulled in by `udisks2`), but not guaranteed on a minimal base.
  - **`dosfstools`** (`mkfs.fat`) — formats the EFI System Partition. A Refracta *Recommends*, so present unless you install with `--no-install-recommends`.

  > Step 1's `install_and_prepare_refracta_on_debian13.sh` now installs `btrfs-progs`, `gdisk`, `parted`, and `dosfstools` for you, so you don't have to add them by hand — they are listed here so the requirement is explicit and so a minimal (non-desktop) base still works.

</details>

### On the source machine (the desktop you want to clone)

#### Preparation (one time)

**Preparation Step 1: Install and configure Refracta.**

```bash
sudo bash install_and_prepare_refracta_on_debian13.sh
```

A one-time, idempotent setup script (safe to re-run, each step checks state and skips work already done). 

<details>

1. **Downloads** the five Refracta `.deb` packages from SourceForge.
2. **Installs** them via `apt-get install` (which resolves dependencies), plus `btrfs-progs`.
3. **Holds** `refractainstaller-base` and `refractainstaller-gui` (`apt-mark hold`). These packages carry the btrfs patch and are installed manually from SourceForge `.deb`s, so no apt repository provides them and a normal `apt upgrade` will never touch them. The hold is a safeguard against a future apt-driven reinstall/upgrade (e.g. if Refracta ever lands in Debian's repos) silently overwriting the patched `/usr/bin/refractainstaller{,-yad}` with a stock version.
4. **Sets `COMPRESS=gzip`** in `/etc/initramfs-tools/initramfs.conf` and rebuilds the initramfs for all kernels. (The default compression can cause boot issues with some live-boot configurations.)
5. **Uncomments `media_opt="--force-extra-removable"`** in `/etc/refractainstaller.conf`, so `grub-install` creates the `\EFI\BOOT\BOOTX64.EFI` fallback bootloader — fixing the VirtualBox EFI boot failure.
</details>

**Preparation Step 2: Apply the patches.**

```bash
# btrfs support for refractainstaller (v9.6.6 → v9.6.6.15)
sudo patch -p1 -d / < btrfs-support-for-refractainstaller.patch

# default "seed /etc/skel + UEFI" snapshot mode for refractasnapshot
sudo patch -p1 -d / < skel-seed-for-refractasnapshot.patch
```

Two standard unified diffs.

<details>

**`btrfs-support-for-refractainstaller.patch`** patches both installers (`/usr/bin/refractainstaller-yad` and `/usr/bin/refractainstaller`) and installs the shared library `/usr/lib/refractainstaller/btrfs-disk-lib.sh`. It adds btrfs (plain and with subvolumes) support, layout-manifest learning, RAM-sized NoCoW swap, hibernation resume, EFI boot fixes, the guided/automated disk setup, (v11) ISO-timestamped install logging with a per-dialog open/close trail, (v12) a consolidated automated flow that asks every question up front so the long copy runs unattended, (v13) the same up-front hostname/username/password collection extended to custom mode (only the bootloader dialog stays in the tail there), (v14) a fix for desktop autologin on SDDM (KDE Plasma) — the installer can finally disable it — plus an autologin question in automated mode, and (v15) the same SDDM autologin fix ported to the CLI installer.

**`skel-seed-for-refractasnapshot.patch`** patches both snapshot tools (`/usr/bin/refractasnapshot` and `/usr/bin/refractasnapshot-gui`) and installs the shared library `/usr/lib/refractasnapshot/skel-seed-lib.sh`. It adds a new **default** snapshot mode that seeds `/etc/skel` from your desktop and builds a UEFI ISO in one step (see below).

See the [Developers](#developers) section for the full version history.
</details>

Alternatively, skip the `patch` commands and copy the pre-patched binaries into place: the installer from `refractainstaller_patched/9.6.6.15/` → `/usr/bin/`, and the snapshot tools from `refractasnapshot_patched/10.4.3.1/` → `/usr/bin/` (plus its `skel-seed-lib.sh` → `/usr/lib/refractasnapshot/`), making the binaries executable.

## Usage (every time you want to pack an ISO)

**Just run refractasnapshot and take the default mode.**

<details>
<summary><b>What gets seeded into /etc/skel (and how to seed it separately)</b></summary>

The **default mode — "Snapshot now: UEFI + seed /etc/skel from your desktop"** — does everything in one/two clicks: it seeds `/etc/skel` from your desktop user's home (so the ISO boots as a near-identical clone of your running desktop, and every new live/installed user inherits your setup), forces a UEFI-bootable image, and skips the free-space report and distro-name prompts. The classic **"Create a snapshot"** task is still there (item `1`) for the full interactive flow without seeding.

Seeded: shell dotfiles (`.bashrc`, `.zshrc`, `.profile`, …); KDE Plasma 6 core config (`kdeglobals`, `kwinrc`, `plasmarc`, shortcuts, activities, power management, …); KDE application data (`dolphin`, `konsole`, `kate`, `spectacle`, `okular`, color schemes, icons, fonts, …); all other `~/.config/` app configs (Firefox, VSCode, terminals, editors, …); `~/.local/bin/` custom binaries; GTK 3/4 integration; autostart entries.

Excluded: `~/.cache/`; `~/.local/share/Trash/`, `thumbnails/`, `baloo/`, `akonadi/`; `~/.local/share/kwalletd/` (encrypted passwords — security); `~/.config/pulse/`, `dconf/` (runtime/session-specific); `*.lock`, `*.pid`, `*.socket`. Ownership of `/etc/skel` is reset to `root:root` afterwards; the live system re-chowns to the new user automatically.

To seed `/etc/skel` **separately** — e.g. to review it before snapshotting — run this **as your regular user (not root)**:

```bash
bash refracta_seed_home_environment_before_iso_creation.sh
```

The standalone script and the snapshot's built-in mode share the same library (`skel-seed-lib.sh`), so they seed identically. Edit the arrays there to change what gets seeded.

</details>

Produces the custom bootable ISO in `$snapshot_dir` (default `/home/snapshot`).

<hr>

### On the target machine

1. **Boot from the ISO.**
2. **Run `refractainstaller-gui`.** 

<details>
It opens with a disk-state screen (inventory via `lsblk`, live-medium detection, and a destructive-action warning), then asks how you want to install:

- **Automated btrfs install**: for a machine with a **blank disk**. Skips both the expert-options screen and the partitioning screen: it auto-selects the disk (one blank disk → used automatically; several disks but one blank → that one; more than one blank → you pick), asks for a single confirmation, then wipes it and builds EFI + `/boot` + btrfs-with-subvolumes + manifest and installs. Requires a UEFI boot.
- **Custom: all options** full expert options, manual partitioning or the "Do not format" path, plus the Partitioning page's *Auto-create btrfs layout* and *Explain btrfs subvolumes* buttons.
</details>

3. **Reboot.**

### Option 2: preparing the disk manually

<details>

If you want to lay out the disk yourself before installing (instead of the Automated mode), you can use GParted, or, run one of these scripts, then choose **"Do not format"** in the installer:

```bash
sudo bash disk_setup_for_btrfs_desktop_subvolumes.sh   # btrfs with subvolumes (+ manifest)
sudo bash disk_setup_for_btrfs_desktop_plain.sh        # plain btrfs root, no subvolumes
```

Both wipe the target disk and create the same GPT layout on `/dev/nvme0n1` (configurable at the top of the script):

| Partition | Size | Type | FS | Mount |
|---|---|---|---|---|
| p1 | 1024 MiB | EF00 (EFI System) | FAT32 | `/boot/efi` |
| p2 | 1024 MiB | 8300 (Linux) | ext4 | `/boot` |
| p3 | ~rest | 8300 (Linux) | btrfs | `/` (plain, or subvolumes) |

The **subvolumes** script creates these subvolumes on p3 and records them in a `.refracta-btrfs-layout` manifest at the btrfs top level (subvolid=5):

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

When you then select **"Do not format"**, the installer reads the manifest and mounts every subvolume at its recorded mountpoint, writes the matching fstab, creates the NoCoW swapfile in `@swap`, and configures hibernation. To change the layout, edit the `REFRACTA_BTRFS_LAYOUT` array in `btrfs-disk-lib.sh`. The installer learns whatever you put there, with no code changes (see [Developers](#developers)).

</details>

<hr>

### Workflow at a glance

```
┌─────────────────────────────────────────────────────────┐
│  SOURCE MACHINE (the desktop you want to clone)         │
|                                                         |
│  ONCE:                                                  │
│  1. sudo bash install_and_prepare_refracta_on_debian13  │
│  2. sudo patch -p1 -d / < btrfs-support-...patch        │
│  3. sudo patch -p1 -d / < skel-seed-...patch            │
│                                                         │
│  REPEAT WHEN MAKING ISO:                                │
│  • sudo refractasnapshot  → default "seed /etc/skel +   │
│    UEFI" mode → custom ISO in one/two clicks            │
└─────────────────────────────────────────────────────────┘
                          │ ISO
                          ▼
┌─────────────────────────────────────────────────────────┐
│  TARGET MACHINE (VirtualBox or bare metal)              │
│                                                         │
│  1. Boot from the ISO                                   │
│  2. Run refractainstaller-gui                           │
│     → disk-state screen (inventory + warning)           │
│     → "Automated btrfs install" (blank disk): picks a   │
│       blank disk + builds everything, no more questions │
│     → or "Custom - all options": manual / Do not format │
│       (GParted, disk_setup_*.sh, Auto-create button)    │
│  3. Reboot — system boots with EFI fallback bootloader  │
└─────────────────────────────────────────────────────────┘
```

<hr>

## Developers

### Repository layout

| Path | What it is |
|---|---|
| `btrfs-support-for-refractainstaller.patch` | The patch. Applied against the **pristine** 9.6.6 scripts (not the installed copies, which can be stale). Patches `refractainstaller-yad` + `refractainstaller` and creates the shared library. |
| `btrfs-disk-lib.sh` | **Single source of truth** for the layout. Defines `REFRACTA_BTRFS_LAYOUT` (the 8-subvolume array), the manifest filename, and the functions that partition a disk, format it, create the subvolumes, and write the manifest. The patch installs it to `/usr/lib/refractainstaller/btrfs-disk-lib.sh`; the standalone subvolumes script sources it (falling back to a copy beside itself). Edit the layout here and both the installer's guided mode and the standalone script follow. |
| `disk_setup_for_btrfs_desktop_{subvolumes,plain}.sh` | Standalone disk-prep scripts for the "Custom" path. The subvolumes one is a thin CLI wrapper around the shared library. |
| `refractainstaller_patched/<build>/` | Archived copies of the patched binaries per build (e.g. `9.6.6.15/`), including `btrfs-disk-lib.sh`. |
| `skel-seed-for-refractasnapshot.patch` | The patch that folds `/etc/skel` seeding into refractasnapshot. Applied against the **pristine** 10.4.3/10.4.1 scripts. Patches `refractasnapshot` + `refractasnapshot-gui` and creates the shared library. |
| `skel-seed-lib.sh` | **Single source of truth** for `/etc/skel` seeding. Defines the dotfile / config / app-data arrays and the copy logic. The patch installs it to `/usr/lib/refractasnapshot/skel-seed-lib.sh`; the standalone seed script sources it (falling back to a copy beside itself). Edit the arrays here and the snapshot tools + the standalone script all follow. |
| `refractasnapshot_patched/<build>/` | Archived copies of the patched snapshot binaries per build (e.g. `10.4.3.1/` = base 10.4.3 + gui 10.4.1 patched), including `skel-seed-lib.sh`. |
| `install_and_prepare_refracta_on_debian13.sh` | Source-machine setup (see Usage). |
| `refracta_seed_home_environment_before_iso_creation.sh` | Standalone `/etc/skel` seeder — now a thin CLI wrapper around `skel-seed-lib.sh` (the snapshot tools' default mode does the same thing). |

**Manifest, not name inference:** a btrfs subvolume stores no mountpoint metadata, and names alone are ambiguous — `@libvirt_images` cannot be mapped to `/var/lib/libvirt/images` by any naming rule, and `@snapshots → /.snapshots`, `@swap`, and `@rootfs → /` are all special cases. The manifest (`.refracta-btrfs-layout`, TAB-separated `<subvolume><TAB><mountpoint>` lines) makes the disk-setup step the single source of truth and the installer fully layout-agnostic. Name-convention discovery is kept only as a best-effort fallback for disks that have no manifest.

### refractasnapshot: the "seed /etc/skel + UEFI" default mode

`skel-seed-for-refractasnapshot.patch` folds the standalone seed step into both snapshot tools, mirroring how `btrfs-disk-lib.sh` was folded into refractainstaller.

- **`skel-seed-lib.sh`** (installed to `/usr/lib/refractasnapshot/`) is the single source of truth for *what* gets seeded (dotfiles + KDE/Plasma config + `~/.local/share` app data + a bulk `~/.config` sync with exclusions) and the copy logic. Sourcing it only defines functions; `refracta_seed_skel <home>` does the work and never calls `exit`. Both the snapshot tools and the standalone `refracta_seed_home_environment_before_iso_creation.sh` source it — edit the arrays once and all three follow.
- **Privilege bridge:** writing `/etc/skel` needs root, but reading the config needs the desktop user. `refractasnapshot` already runs as root, so `_skel_as_root` runs commands directly and `refracta_skel_source_home` resolves the desktop user's home even under root (`SUDO_USER` → `PKEXEC_UID` → the uid-1000 user). The standalone script runs as the user and elevates writes with `sudo`. Either way the final `chown -R root:root /etc/skel` fixes ownership; the live system re-chowns per new user.
- **New default task** (CLI item `0` / pre-selected first GUI row): forces `make_efi=yes` (re-running `check_grub`, which only ever *downgrades*, so it still degrades safely to a BIOS ISO if grub-efi/dosfstools are missing), seeds `/etc/skel` **before** the filesystem is copied (so it lands in the ISO), and runs a "fast" path that skips the free-space report and distro-name prompt — hence one/two clicks. The task-1 body is factored into `run_create_snapshot[_gui]()` so the default and classic modes share one code path via the `seed_skel` / `fast_mode` flags. Tasks 2–6 are untouched.

### Patch version history

The btrfs patch evolved through ten versions. Each drawer expands to the full technical write-up.

<details>
<summary><b>v1 — btrfs filesystem support</b></summary>

Adds two new options to the filesystem selection menu:

| Option | Behaviour |
|---|---|
| **btrfs (single partition)** | Formats the root partition as btrfs. Single fstab entry, no subvolumes. The top-level btrfs volume (subvolid=5) is mounted as `/`. |
| **btrfs (with subvolumes)** | Formats as btrfs and creates five subvolumes, mounts each at its mount point before rsync, generates multi-entry fstab with `subvol=` options. |

Default subvolumes created by the "with subvolumes" option (this built-in set is the **fallback** only — as of v5 the real layout is learned from the disk):

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

</details>

<details>
<summary><b>v2 — btrfs bug fixes</b></summary>

Two bugs discovered during real installation testing:

- **Subvolume creation with `no_format=yes`**: v1 tried to create subvolumes even when "Do not format" was selected and the subvolumes already existed, causing a non-fatal "File exists" error. Fixed by moving subvolume creation inside the `no_format` check — subvolumes are now only created when actually formatting.
- **Duplicated `rootflags` in kernel command line**: v1 used `sed` to add `rootflags=subvol=@rootfs` to `GRUB_CMDLINE_LINUX_DEFAULT`, but `update-grub` (grub-mkconfig) already auto-detects btrfs subvolume roots and adds this parameter automatically. The `sed` caused the parameter to appear twice in the kernel command line. Fixed by removing the redundant `sed` — `update-grub` handles it.

</details>

<details>
<summary><b>v3 — EFI boot fixes + dual logging</b></summary>

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

</details>

<details>
<summary><b>v4 — findmnt fix for nested mount verification</b></summary>

Discovered during a real install test: the ESP mount verification added in v3 used `df | grep -q "/target/boot/efi"` to check if the ESP was mounted. However, `df` without arguments only shows top-level mount points — it does not list nested mounts. Since `/target/boot/efi` is mounted **under** `/target/boot` (which is under `/target`), `df` collapses it and the grep fails — even when the ESP is correctly mounted. This caused the installer to abort with "EFI partition is not mounted" despite the mount being perfectly fine.

Fix applied:

- Replaced all `df | grep` ESP verification checks with `findmnt`, which reliably detects nested mounts. This affects three checks per script: the ESP pre-unmount check, the post-mount verification, and the `install_grub()` pre-flight check.

</details>

<details>
<summary><b>v5 — learn the subvolume layout from the disk + NoCoW swapfile</b></summary>

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

</details>

<details>
<summary><b>v6 — EFI + separate <code>/boot</code> grub fix + RAM-sized swap</b></summary>

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

The stock swapfile default is 256 MiB (`swapfile_count=262144`), which rounds to **0 GiB** in `free -g` and is useless on a desktop. The swapfile is now sized to **match the target machine's RAM** (rounded up to a whole GiB), auto-detected from `/proc/meminfo` at install time — large enough to be useful and to support hibernation. This applies to **every filesystem** (ext2/3/4 and btrfs), not just btrfs; it falls back to the configured size if RAM can't be read. On btrfs the swapfile is additionally made NoCoW (see above). (`chmod` now precedes `mkswap`, dropping the harmless "insecure permissions" warning.) Actually hibernating to the swapfile also needs `resume=`/`resume_offset=` kernel parameters — wired up in v7.

</details>

<details>
<summary><b>v7 — hibernation (resume from swap), all scenarios</b></summary>

v6 sized swap large enough for hibernation; v7 configures the system to actually resume from it. `configure_resume()` handles every swap scenario:

| Scenario | `resume=` | `resume_offset=` |
|---|---|---|
| swapfile on btrfs (incl. `@swap` subvolume) | UUID of the btrfs filesystem | `btrfs inspect-internal map-swapfile -r` |
| swapfile on ext2/3/4 | UUID of the root filesystem | first physical block from `filefrag` |
| existing swap partition | UUID of the swap partition | (none) |

For each, it writes `RESUME=UUID=<dev>` to `/etc/initramfs-tools/conf.d/resume` and appends `resume=UUID=<dev> [resume_offset=N]` to `GRUB_CMDLINE_LINUX_DEFAULT`, then `update-grub` + `update-initramfs` pick them up (the initramfs rebuild now also triggers when resume is configured, so it works on plain ext4 installs too). A swapfile install only enables resume if the offset was successfully obtained, and the whole thing is **skipped for encrypted root** (resuming from encrypted swap needs additional setup).

> **VirtualBox caveat:** S4/hibernation generally does **not** work under VirtualBox (its EFI/ACPI doesn't reliably trigger the kernel's resume). Everything is configured correctly, but test actual hibernate/restore on **bare metal**.

</details>

<details>
<summary><b>v8 — in-tool manifest help (discoverable without this README)</b></summary>

The manifest-driven flow is now explained from inside the installer, so a user who has never seen this README can understand and use it:

- **CLI:** `refractainstaller --btrfs-manifest` prints an explanation of the flow, an example `.refracta-btrfs-layout`, and a copy-pasteable recipe that creates the partitions' subvolumes + a valid (real-TAB) manifest. It's also listed in `refractainstaller --help`.
- **GUI:** an **"Explain btrfs subvolumes"** button on the Partitioning page (next to *Run GParted*) shows the same text in a scrollable window. That page now loops, so closing the help returns you to it.

Both share the same wording, and the recipe shown was verified to parse correctly through the installer's own manifest reader.

</details>

<details>
<summary><b>v9 — guided disk setup + disk-state first screen (GUI)</b></summary>

So you no longer have to run a disk-prep script separately, the GUI can build the disk itself — and it now states its destructive potential up front.

- **Disk-state first screen:** before anything else, `refractainstaller-gui` shows a disk inventory (`lsblk`), detects and labels the **live boot medium**, and warns that some choices erase a whole disk — then Continue/Exit.
- **"Auto-create btrfs layout" button** on the Partitioning page (single disk): lists eligible whole disks (**excluding the live medium and any mounted disk**), requires you to **type the device path** to confirm, then partitions ESP + `/boot` + btrfs(subvolumes) and writes the manifest — after which the install continues non-interactively over the "Do not format" path (the manifest is learned). Requires a UEFI boot; not combined with encryption.
- **Shared library `btrfs-disk-lib.sh`** (installed to `/usr/lib/refractainstaller/`): the single source of truth for the layout + partition/manifest logic, used by both the guided GUI mode and the standalone `disk_setup_for_btrfs_desktop_subvolumes.sh`. Change the layout in one place.

The CLI installer is unchanged in v9 (guided mode is GUI-only); manual partitioning and the existing "Do not format" path are untouched — guided mode is purely additive and opt-in.

</details>

<details>
<summary><b>v10 — intro mode-fork: automated vs custom (GUI)</b></summary>

To make the guided/expert division obvious, `refractainstaller-gui` now asks, right after the greeting, **how** you want to install:

- **Automated btrfs install** — for a machine with a **blank disk**. It skips **both** the expert-options screen and the Partitioning screen: it auto-selects the disk (one blank disk → used automatically; several disks but one blank → that one; more than one blank → you pick from the blank ones), asks for a single confirmation, then wipes it and builds EFI + `/boot` + btrfs-subvolumes + manifest and installs. A "blank disk" = no partitions, no partition table, no filesystem signature; the live medium and mounted disks are always excluded. Requires a UEFI boot (refuses otherwise), and the "create an EFI partition" notice is suppressed since the setup creates the ESP itself.
- **Custom — all options** — the installer behaves exactly as before (full expert options, manual partitioning or "Do not format", and the Partitioning page's *Auto-create btrfs layout* / *Explain btrfs subvolumes* buttons).

Also: **guided btrfs now refuses to combine with encryption** — if encryption (root or `/home`) is selected and you then trigger a guided btrfs setup, the installer stops with an explanation rather than building an inconsistent (non-LUKS) layout. Internally, the automated and Partitioning-page guided paths share one `_guided_set_vars()` so the variable contract lives in a single place. (CLI and `btrfs-disk-lib.sh` are unchanged in v10.)

</details>

<details>
<summary><b>v11 — ISO-timestamped install log + per-dialog markers (GUI)</b></summary>

Groundwork for a bigger UX change: the GUI installer currently interleaves questions with long operations (options/disk/boot up front, then a long file copy, then hostname/username/passwords), so you can't walk away — you get asked more questions after the wait. Before reworking that, v11 makes the timing **measurable from the log alone**. No install behaviour changes; only logging is added.

- **Every trace line is ISO-8601 timestamped.** A `_iso_now` helper (bash builtin `printf` time format — no external process per line) drives `PS4='+ $(_iso_now) '`, so the whole `set -x` trace — the bulk of `/var/log/refractainstaller.log` — now shows *when* each step ran. The long waits are visible as the gaps between timestamps.
- **Every dialog is logged when it opens and closes.** All dialogs go through `yad`, and nothing calls it by full path, so a single `yad()` wrapper logs, per dialog:
  - `<ISO>  DIALOG open  kind=<list|form|entry|progress|…> title=<title>`
  - `<ISO>  DIALOG close kind=… title=… exit=<button code> duration=<n>s`

  The wrapper runs the real binary via `command yad`, so it never disturbs yad's stdout (callers capture it with `$(…)`) or its exit status (callers test `$?`). Because the progress bars for cleanup/rsync/swapfile are also just `yad`, their open→close duration shows exactly how long those operations took.

Inspect a run with `grep DIALOG /var/log/refractainstaller.log` to get the whole decision-and-wait timeline. (CLI and `btrfs-disk-lib.sh` are unchanged in v11.)

</details>

<details>
<summary><b>v12 — automated mode asks everything up front, then runs unattended (GUI)</b></summary>

The payoff of v11's logging. A real automated run's log showed the problem plainly: after the up-front option/disk dialogs, the installer does a **~3.5-minute rsync copy** and only *then* asks the bootloader question, the hostname/username, and the password(s) — so you return to more prompts and more waiting. (One test run sat idle for 78 minutes on the post-copy "Install Bootloader" dialog because the tester had stepped away.)

v12 consolidates all of that for the **Automated btrfs install** path (`auto_mode`) only — **custom mode is unchanged**:

- The **hostname/username and password dialog(s) are asked before the copy**, in one collect phase placed just before the Summary — so the Summary is the true final "last chance" gate. The answers are remembered and applied unattended in the install tail.
- The post-copy **"Install Bootloader" dialog is skipped**: automated mode already promises no expert questions, so GRUB is always installed.
- After you click *Proceed* on the Summary, the rest — locale, copy, swap, GRUB, user config, passwords — runs with **no further prompts**. You can walk away and come back to a finished install.

Mechanics: the six dialog/collection helpers (`clean_log`, `pass_error`, `configure_pass`, `username_dialog`, `fix_hostname`, `test_hostname`) are relocated *verbatim* to above the Summary (bash needs a function defined before it's called, and these previously lived only in the post-copy tail). Passwords are collected with `set -x` paused, so the plain text never reaches the log; the collect phase deliberately does **not** run `clean_log` (its `sed -i` swaps the log's inode and would detach the redirected stderr, silencing the rest of the install) and re-attaches stderr afterwards as a safety net. (CLI and `btrfs-disk-lib.sh` are unchanged in v12.)

*Validated on real hardware:* an automated run's log showed every dialog collapsed into one up-front window (mode → layout → subvolumes → hostname/username → user password → Summary), then a fully unattended tail (cleanup → copy → swap → GRUB → password applied → done), no post-copy prompts, and the installed login worked.

</details>

<details>
<summary><b>v13 — custom mode also asks hostname/username/passwords up front (GUI)</b></summary>

v12 fixed the walk-away problem for automated installs; v13 brings the same up-front collection to the **Custom - all options** path. Previously custom mode still interleaved: after the copy it asked the bootloader question, *then* the hostname/username, *then* the password(s).

v13 makes the v12 collect phase run for **both** modes — the hostname/username and password dialog(s) are asked before the copy in custom mode too. After you click *Proceed* on the Summary, the only remaining custom-mode prompt is the **"Install Bootloader" dialog**, which is deliberately left in the tail: two of its options — *Chroot* (opens an xterm inside the copied `/target`) and *Copy files* (copies grub packages into `/target`) — need the populated `/target` and can't run before the copy. Automated mode still skips the bootloader dialog entirely (always installs GRUB), exactly as in v12.

Mechanics: the `if [[ $auto_mode = "yes" ]]` gate around the v12 collect phase is removed so it runs unconditionally; the now-redundant tail `username_dialog` and hostname-legality (`test_hostname`) calls are dropped; and `set_rootpass`/`set_userpass` always apply the pre-collected password (the `auto_mode` branch is collapsed away). The password/logging safety (xtrace paused during collection, no up-front `clean_log`, stderr re-attached) is inherited unchanged from v12. Not touched: the LUKS passphrase (encrypted installs) and optional filesystem-label prompts still fire after *Proceed* but before the copy — they were already pre-copy and are config-specific. (CLI and `btrfs-disk-lib.sh` are unchanged in v13.)

</details>

<details>
<summary><b>v14 — fix desktop autologin on SDDM (KDE Plasma) + ask in automated mode (GUI)</b></summary>

A real automated install on Debian 13 + KDE Plasma always booted straight into the desktop with autologin, no matter what — and older tests showed that even ticking *"Disable automatic login to desktop"* in custom mode didn't stop it. **Root cause: neither installer had any support for SDDM**, the display manager KDE Plasma uses on Debian 13 (`grep -c sddm` was `0` in both).

The live autologin is created by Debian live-config's `/lib/live/config/0085-sddm`, which writes `/etc/sddm.conf`:

```ini
[Autologin]
User=<liveuser>
Session=plasma.desktop
```

That file is part of the running live filesystem, so the installer's rsync copies it into `/target`. The installer's `set_noautologin_desktop` / `set_autologin_desktop` handle gdm/gdm3/lightdm/kdm/kde-kdm/trinity/slim/lxdm and "no display manager" — but never `/etc/sddm.conf`. So on KDE/SDDM the autologin was never modifiable: custom mode's "disable" ran `set_noautologin_desktop` (which did nothing for SDDM), and automated mode skipped the whole checklist and kept autologin without ever asking.

v14 fixes it:

- **`set_noautologin_desktop`** now comments the `User=` line inside the `[Autologin]` section of `/target/etc/sddm.conf` (and `/target/etc/sddm.conf.d/*.conf`), so SDDM shows the normal greeter. The edit is section-scoped (`/^\[Autologin\]/,/^\[/`), so a `User=` key in another section is never touched.
- **`set_autologin_desktop`** now rewrites `User=<olduser>` → `<newuser>` in the same section, so "keep autologin" survives a username change.
- **Automated mode now asks.** Because the expert checklist (where the autologin option lives) is skipped in `auto_mode`, a single yad question — *"Enable automatic login to the desktop for the new user?"* — is added to the up-front collect phase, guarded by `[[ $auto_mode = "yes" ]]` so custom mode (which still asks via the checklist) is unaffected.

Note: the CLI installer had the **same** missing-SDDM bug — fixed in v15 below. (`btrfs-disk-lib.sh` is unchanged in v14.)

</details>

<details>
<summary><b>v15 — same SDDM autologin fix, ported to the CLI installer</b></summary>

v14 fixed SDDM autologin in the GUI installer only. The CLI installer (`refractainstaller`) has the identical defect: its "Disable auto-login?" prompt (ENTER = YES) called `set_noautologin_desktop`, which — like the GUI's before v14 — had no SDDM branch, so on KDE/Debian 13 the autologin was never disabled.

v15 adds the **exact same two blocks** to the CLI's `set_noautologin_desktop` (comment `User=` under `[Autologin]` in `/etc/sddm.conf` + `/etc/sddm.conf.d/*.conf`) and `set_autologin_desktop` (rename `User=` there). The CLI has no automated (`auto_mode`) flow, so no extra question is needed — it already prompts about autologin in its normal sequence; only the missing SDDM handling was the bug. (`refractainstaller-yad` and `btrfs-disk-lib.sh` are unchanged in v15.)

</details>

<hr>

## Tips & Tricks

**Q: My KDE Dolphin forgot my chosen View Mode (e.g. Compact reverted to Icons on a freshly-cloned machine or a new user).**

<details>
<summary><b>A: Manually create .directory file</b></summary>
With its default *Global View Properties* setting, Dolphin does **not** store the view mode in any config file — it keeps it in the **Plasma session** (restored at login by `ksmserver`), held only in memory while Dolphin runs. Because session data is machine-/session-specific, it is not carried into `/etc/skel` (and *should not* be), so a new user or a freshly-installed clone falls back to Dolphin's compiled-in default (Icons). Even quitting Dolphin does not write the setting to disk.

To make the view mode **persistent on disk** (so it survives to new users and clones), close all Dolphin windows and create the file:

```
~/.local/share/dolphin/view_properties/global/.directory
```

with these contents:

```ini
[Dolphin]
Timestamp=2026,7,8,13,0,0
Version=4
ViewMode=2
```

- **`ViewMode`** on Dolphin 25.04.x is `0` = Icons, `1` = Details, **`2` = Compact**. (Note: this ordering is *not* the intuitive one — Compact is `2`, not `1`.)
- **`Timestamp`** must be **newer** than the `ViewPropsTimestamp` line in `~/.config/dolphinrc`, or Dolphin treats the file as stale and ignores it. Use roughly the current date/time in `YEAR,M,D,H,M,S` format.
- This relies on Dolphin's *Global View Properties* being enabled (the default — i.e. no `GlobalViewProps=false` in `dolphinrc`).

Once this file exists, `refractasnapshot`'s `/etc/skel` seeding copies it like any other config, so every new user on the resulting ISO opens Dolphin in your chosen view.

</details>

<hr>

### Refracta component versions these patches are based on

| Package | Version | Source |
|---|---|---|
| refractasnapshot-base | 10.4.3 | SourceForge |
| refractasnapshot-gui | 10.4.1 | SourceForge |
| refractainstaller-base | 9.6.6 | SourceForge |
| refractainstaller-gui | 9.6.6 | SourceForge |
| refracta2usb | 2.4.3 | SourceForge |

> **Note:** The snapshot base (10.4.3) and gui (10.4.1) version numbers differ intentionally. Per the maintainer's note: *"Use latest available version of -gui with latest version of -base, even if numbers are different."*

<hr>

## License

MIT. See [LICENSE](LICENSE).

The Refracta patch is submitted upstream to the Refracta maintainer (fsmithred) for potential inclusion in a future release. Refracta itself is GPL-3.
