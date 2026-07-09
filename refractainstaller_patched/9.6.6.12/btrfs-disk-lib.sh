#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# btrfs-disk-lib.sh — shared Refracta btrfs disk-layout library
#
# Single source of truth for the btrfs subvolume layout + manifest, used by:
#   - refractainstaller / refractainstaller-yad  (guided "Auto-create" mode)
#   - disk_setup_for_btrfs_desktop_subvolumes.sh (standalone disk prep)
#
# It is SOURCED, not executed, and assumes the caller runs as root.
# The patch installs a copy at /usr/lib/refractainstaller/btrfs-disk-lib.sh.
# To change the layout, edit REFRACTA_BTRFS_LAYOUT here — both the installer and
# the standalone script (and the manifest the installer learns) follow it.
# ──────────────────────────────────────────────────────────────────────────────

# subvolume:mountpoint — shallow paths first so parents mount before children.
REFRACTA_BTRFS_LAYOUT=(
    "@rootfs:/"
    "@home:/home"
    "@var_log:/var/log"
    "@var_cache:/var/cache"
    "@libvirt_images:/var/lib/libvirt/images"
    "@swap:/swap"
    "@tmp:/tmp"
    "@snapshots:/.snapshots"
)

# Manifest filename written at the btrfs top level (subvolid=5).
# MUST match $btrfs_layout_manifest in refractainstaller{,-yad}.
REFRACTA_BTRFS_MANIFEST=".refracta-btrfs-layout"

# Partition sizes (MiB). p3 (btrfs) takes the remaining space.
REFRACTA_EFI_SIZE_MiB=1024
REFRACTA_BOOT_SIZE_MiB=1024

# refracta_part_name DISK N  ->  Nth partition device node.
# Handles nvme0n1p1 / mmcblk0p1 (disk ends in a digit) vs sda1 (ends in a letter).
refracta_part_name () {
    local _disk="$1" _n="$2"
    case "$_disk" in
        *[0-9]) echo "${_disk}p${_n}" ;;
        *)      echo "${_disk}${_n}" ;;
    esac
}

# refracta_btrfs_check_tools  ->  0 if all needed tools are present, else 1.
# On failure, prints the missing tool names to stderr.
refracta_btrfs_check_tools () {
    local _c _missing=""
    for _c in sgdisk wipefs mkfs.fat mkfs.ext4 mkfs.btrfs btrfs partprobe blkid; do
        command -v "$_c" >/dev/null 2>&1 || _missing="$_missing $_c"
    done
    [[ -z "$_missing" ]] && return 0
    echo "missing tools:$_missing" >&2
    return 1
}

# refracta_btrfs_manifest_lines  ->  prints the manifest body (comments + pairs).
refracta_btrfs_manifest_lines () {
    local _e
    echo "# Refracta btrfs subvolume layout"
    echo "# <subvolume><TAB><mountpoint> - read by refractainstaller"
    for _e in "${REFRACTA_BTRFS_LAYOUT[@]}"; do
        printf '%s\t%s\n' "${_e%%:*}" "${_e#*:}"
    done
}

# refracta_btrfs_make_layout DISK
#   DESTROYS DISK and creates the standard layout:
#     p1  ESP   (FAT32, EF00)        p2  /boot (ext4, 8300)
#     p3  btrfs (8300) with the subvolumes above + the layout manifest.
#   Progress goes to stdout, errors to stderr. Returns 0 on success, 1 on error.
#   Assumes root. Does NOT prompt — the CALLER must confirm the destruction.
refracta_btrfs_make_layout () {
    local _disk="$1" _efi _boot _btrfs _top _sv _e _i _p _r
    [[ -b "$_disk" ]] || { echo "not a block device: $_disk" >&2; return 1; }
    _efi=$(refracta_part_name "$_disk" 1)
    _boot=$(refracta_part_name "$_disk" 2)
    _btrfs=$(refracta_part_name "$_disk" 3)

    echo "Wiping $_disk ..."
    wipefs --all --force "$_disk" || { echo "wipefs failed on $_disk" >&2; return 1; }
    sgdisk --zap-all "$_disk"     || { echo "sgdisk --zap-all failed on $_disk" >&2; return 1; }

    echo "Creating GPT partitions on $_disk ..."
    sgdisk \
        --new=1:0:+${REFRACTA_EFI_SIZE_MiB}M  --typecode=1:EF00 --change-name=1:"EFI System" \
        --new=2:0:+${REFRACTA_BOOT_SIZE_MiB}M --typecode=2:8300 --change-name=2:"Linux boot" \
        --new=3:0:0                           --typecode=3:8300 --change-name=3:"Linux btrfs" \
        "$_disk" || { echo "sgdisk partitioning failed on $_disk" >&2; return 1; }

    partprobe "$_disk"; sleep 2
    for _i in 1 2 3; do
        _p=$(refracta_part_name "$_disk" "$_i"); _r=0
        while [[ ! -b "$_p" && $_r -lt 10 ]]; do sleep 1; _r=$((_r+1)); done
        [[ -b "$_p" ]] || { echo "partition $_p did not appear after 10s" >&2; return 1; }
    done

    echo "Formatting partitions ..."
    mkfs.fat -F32 -n EFI "$_efi"                    || { echo "mkfs.fat failed on $_efi" >&2; return 1; }
    mkfs.ext4 -F -L boot "$_boot"                   || { echo "mkfs.ext4 failed on $_boot" >&2; return 1; }
    mkfs.btrfs --force --label btrfs-root "$_btrfs" || { echo "mkfs.btrfs failed on $_btrfs" >&2; return 1; }

    echo "Creating subvolumes and writing the manifest ..."
    _top=$(mktemp -d)
    mount -o subvolid=5 "$_btrfs" "$_top" || { echo "mount subvolid=5 failed on $_btrfs" >&2; rmdir "$_top"; return 1; }
    for _e in "${REFRACTA_BTRFS_LAYOUT[@]}"; do
        _sv="${_e%%:*}"
        btrfs subvolume create "$_top/$_sv" || { echo "subvolume create failed: $_sv" >&2; umount "$_top"; rmdir "$_top"; return 1; }
    done
    refracta_btrfs_manifest_lines > "$_top/$REFRACTA_BTRFS_MANIFEST"
    sync
    umount "$_top"; rmdir "$_top"

    echo "Done: $_disk -> p1 ESP, p2 /boot (ext4), p3 btrfs + ${#REFRACTA_BTRFS_LAYOUT[@]} subvolumes + manifest"
    return 0
}
