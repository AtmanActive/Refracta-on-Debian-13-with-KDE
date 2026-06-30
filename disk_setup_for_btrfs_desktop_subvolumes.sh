#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════════════════
# disk_setup_for_btrfs_desktop_subvolumes.sh
# Creates a clean GPT partition table, formats all partitions, creates btrfs
# subvolumes, and writes the layout manifest the patched refractainstaller reads.
#
# The actual layout + work lives in the SHARED library btrfs-disk-lib.sh (the
# single source of truth, also used by refractainstaller's "Auto-create btrfs
# layout" guided mode). This script is the standalone CLI wrapper around it.
#
# Target layout:
#   p1  1024M  EF00  FAT32  /boot/efi
#   p2  1024M  8300  ext4   /boot
#   p3  ~rest  8300  btrfs  /  (subvolumes per REFRACTA_BTRFS_LAYOUT)
#
# Run from a Refracta live ISO on the disk you want to erase.
# ══════════════════════════════════════════════════════════════════════════════

# ── Configuration ─────────────────────────────────────────────────────────────
DISK="/dev/nvme0n1"

# ── Colour output ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()     { echo -e "${CYAN}==>${RESET} $*"; }
ok()      { echo -e "${GREEN}==>${RESET} $*"; }
warn()    { echo -e "${YELLOW}WARNING:${RESET} $*"; }
err()     { echo -e "${RED}ERROR:${RESET} $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}\n"; }

# ── Load the shared library (single source of truth) ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB=""
for _cand in /usr/lib/refractainstaller/btrfs-disk-lib.sh "$SCRIPT_DIR/btrfs-disk-lib.sh"; do
    [ -f "$_cand" ] && { LIB="$_cand"; break; }
done
if [ -z "$LIB" ]; then
    err "btrfs-disk-lib.sh not found (looked in /usr/lib/refractainstaller and $SCRIPT_DIR)."
    err "Apply the refractainstaller btrfs patch, or keep btrfs-disk-lib.sh next to this script."
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

# ══════════════════════════════════════════════════════════════════════════════
# Sanity Checks
# ══════════════════════════════════════════════════════════════════════════════
section "Sanity Checks"

if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root. Use: sudo bash $(basename "$0")"
    exit 1
fi

if ! refracta_btrfs_check_tools 2>/tmp/.refracta_tools_missing; then
    err "Required command(s) not found:$(cut -d: -f2 /tmp/.refracta_tools_missing)"
    err "Install with: apt-get install gdisk dosfstools e2fsprogs btrfs-progs"
    rm -f /tmp/.refracta_tools_missing
    exit 1
fi
rm -f /tmp/.refracta_tools_missing

if [ ! -b "$DISK" ]; then
    err "Disk device '$DISK' not found. Edit DISK= at the top of this script."
    exit 1
fi

log "Target disk: $DISK"
echo ""
lsblk "$DISK" 2>/dev/null || true
echo ""

# ── Safety Confirmation ────────────────────────────────────────────────────────
echo -e "${RED}${BOLD}WARNING: This will COMPLETELY ERASE $DISK${RESET}"
echo -e "${YELLOW}         All existing data will be permanently and irreversibly lost.${RESET}"
echo ""
read -rp "Type YES to confirm and continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted by user."
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Create the layout (delegated to the shared library)
# ══════════════════════════════════════════════════════════════════════════════
section "Creating btrfs layout on $DISK"

if ! refracta_btrfs_make_layout "$DISK"; then
    err "Disk setup failed. See messages above."
    exit 1
fi
ok "Disk setup complete."

# ══════════════════════════════════════════════════════════════════════════════
# Verification Summary
# ══════════════════════════════════════════════════════════════════════════════
section "Verification Summary"

echo -e "${BOLD}Block device layout:${RESET}"
lsblk -f "$DISK"
echo ""
echo -e "${BOLD}Partition details:${RESET}"
sgdisk --print "$DISK"
echo ""

P1=$(refracta_part_name "$DISK" 1)
P2=$(refracta_part_name "$DISK" 2)
P3=$(refracta_part_name "$DISK" 3)

echo -e "${BOLD}What was created:${RESET}"
echo ""
echo -e "  ${CYAN}${P1}${RESET}  1024 MiB  FAT32   /boot/efi"
echo -e "  ${CYAN}${P2}${RESET}  1024 MiB  ext4    /boot"
echo -e "  ${CYAN}${P3}${RESET}  ~rest     btrfs   / (root pool)"
echo ""
echo -e "  ${BOLD}btrfs subvolumes on ${P3}:${RESET}"
for _e in "${REFRACTA_BTRFS_LAYOUT[@]}"; do
    printf "    ${CYAN}%-18s${RESET}  →  %s\n" "${_e%%:*}" "${_e#*:}"
done
echo ""
echo -e "  ${BOLD}layout manifest:${RESET} top-level (subvolid=5)/${REFRACTA_BTRFS_MANIFEST}"
echo ""
echo -e "${BOLD}Expected /etc/fstab entries after installation:${RESET}"
echo ""
echo "  # EFI"
echo "  UUID=<uuid-of-p1>    /boot/efi   vfat    umask=0077              0  1"
echo ""
echo "  # boot"
echo "  UUID=<uuid-of-p2>    /boot       ext4    defaults                0  2"
echo ""
echo "  # btrfs subvolumes (all share the SAME p3 UUID)"
for _e in "${REFRACTA_BTRFS_LAYOUT[@]}"; do
    printf "  UUID=<uuid-of-p3>    %-26s btrfs   defaults,noatime,subvol=%s\n" "${_e#*:}" "${_e%%:*}"
done
echo ""
echo "  # swapfile inside the @swap subvolume (created NoCoW by refractainstaller)"
echo "  /swap/swapfile       none                       swap    sw"
echo ""
echo -e "${YELLOW}NOTE:${RESET} All btrfs subvolume entries share the SAME UUID (they are all on"
echo "       the same btrfs pool — just mounted via different subvol= options)."
echo ""
echo -e "${BOLD}Retrieve UUIDs with:${RESET}  ${CYAN}blkid $DISK*${RESET}"
echo ""
echo -e "${BOLD}Next step:${RESET} Launch refractainstaller-gui (btrfs patch applied)."
echo "  Choose 'Do not format filesystems' and select ${P3} as root."
echo "  The installer reads the manifest at the btrfs top level and LEARNS this"
echo "  exact subvolume layout automatically — mounting each subvolume, writing"
echo "  fstab, and creating the NoCoW swapfile in @swap. No manual mapping needed."
echo ""
echo -e "  (Or skip this script entirely and use the installer's"
echo -e "   ${BOLD}\"Auto-create btrfs layout\"${RESET} button, which runs this same library.)"
