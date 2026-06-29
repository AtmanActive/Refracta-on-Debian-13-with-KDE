#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════════════════
# disk_setup.sh
# Creates a clean GPT partition table and formats all partitions on a blank
# 256GB disk. Uses plain btrfs (no subvolumes) for the root filesystem.
#
# Target layout:
#   p1  1024M    EF00  FAT32   /boot/efi
#   p2  1024M    8300  ext4    /boot
#   p3  ~253G    8300  btrfs   / (plain, no subvolumes)
#
# Run from a Refracta live ISO on a blank disk.
# ══════════════════════════════════════════════════════════════════════════════

# https://github.com/flaksit/convert-btrfs-structure

# ── Configuration ─────────────────────────────────────────────────────────────
DISK="/dev/nvme0n1"

# Partition sizes (MiB)
EFI_SIZE_MiB=1024
BOOT_SIZE_MiB=1024
# p3 takes all remaining space automatically

# ── Colour output ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()     { echo -e "${CYAN}==>${RESET} $*"; }
ok()      { echo -e "${GREEN}==>${RESET} $*"; }
warn()    { echo -e "${YELLOW}WARNING:${RESET} $*"; }
err()     { echo -e "${RED}ERROR:${RESET} $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}\n"; }

# ══════════════════════════════════════════════════════════════════════════════
# Sanity Checks
# ══════════════════════════════════════════════════════════════════════════════
section "Sanity Checks"

if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root. Use: sudo bash disk_setup.sh"
    exit 1
fi

for CMD in sgdisk mkfs.fat mkfs.ext4 mkfs.btrfs btrfs partprobe; do
    if ! command -v "$CMD" &>/dev/null; then
        err "Required command not found: $CMD"
        err "Install with: apt-get install gdisk dosfstools e2fsprogs btrfs-progs"
        exit 1
    fi
done

if [ ! -b "$DISK" ]; then
    err "Disk device '$DISK' not found."
    exit 1
fi

# Show what we are about to destroy
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
# STEP 1 — Wipe existing partition table
# ══════════════════════════════════════════════════════════════════════════════
section "Step 1: Wipe Existing Partition Table"

log "Wiping existing signatures and partition table on $DISK..."
sudo wipefs --all --force "$DISK"
sudo sgdisk --zap-all "$DISK"
ok "Disk wiped."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Create GPT Partition Table and Partitions
# ══════════════════════════════════════════════════════════════════════════════
section "Step 2: Create GPT Partitions"

log "Creating partition layout..."

sudo sgdisk \
    --new=1:0:+${EFI_SIZE_MiB}M  --typecode=1:EF00  --change-name=1:"EFI System"    \
    --new=2:0:+${BOOT_SIZE_MiB}M --typecode=2:8300  --change-name=2:"Linux boot"    \
    --new=3:0:0                  --typecode=3:8300  --change-name=3:"Linux btrfs"   \
    "$DISK"

if [ $? -ne 0 ]; then
    err "sgdisk partitioning failed. Aborting."
    exit 1
fi
ok "GPT partition table created."

log "Informing kernel of new partition layout..."
sudo partprobe "$DISK"
sleep 3

# Confirm all three partition nodes are visible
for PART in 1 2 3; do
    PART_DEV="${DISK}p${PART}"
    RETRIES=0
    while [ ! -b "$PART_DEV" ] && [ $RETRIES -lt 10 ]; do
        sleep 1
        RETRIES=$((RETRIES + 1))
    done
    if [ ! -b "$PART_DEV" ]; then
        err "Partition device $PART_DEV did not appear after 10s. Aborting."
        exit 1
    fi
done
ok "All partition device nodes confirmed present."

# Print final partition layout for review
echo ""
log "Partition layout:"
sudo sgdisk --print "$DISK"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Format Partitions
# ══════════════════════════════════════════════════════════════════════════════
section "Step 3: Format Partitions"

EFI_PART="${DISK}p1"
BOOT_PART="${DISK}p2"
BTRFS_PART="${DISK}p3"

# ── p1 → FAT32 (EFI) ──────────────────────────────────────────────────────────
log "Formatting $EFI_PART as FAT32 (EFI System Partition)..."
sudo mkfs.fat -F32 -n "EFI" "$EFI_PART"
if [ $? -ne 0 ]; then err "mkfs.fat failed on $EFI_PART. Aborting."; exit 1; fi
ok "FAT32 created on $EFI_PART (label: EFI)"

# ── p2 → ext4 (/boot) ─────────────────────────────────────────────────────────
log "Formatting $BOOT_PART as ext4 (/boot)..."
sudo mkfs.ext4 -L "boot" "$BOOT_PART"
if [ $? -ne 0 ]; then err "mkfs.ext4 failed on $BOOT_PART. Aborting."; exit 1; fi
ok "ext4 created on $BOOT_PART (label: boot)"

# ── p3 → btrfs (/) ────────────────────────────────────────────────────────────
log "Formatting $BTRFS_PART as btrfs (root pool)..."
sudo mkfs.btrfs --label "btrfs-root" --force "$BTRFS_PART"
if [ $? -ne 0 ]; then err "mkfs.btrfs failed on $BTRFS_PART. Aborting."; exit 1; fi
ok "btrfs created on $BTRFS_PART (label: btrfs-root)"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Verify and Summary
# ══════════════════════════════════════════════════════════════════════════════
section "Step 4: Verification Summary"

echo -e "${BOLD}Block device layout:${RESET}"
lsblk -f "$DISK"
echo ""

echo -e "${BOLD}Partition details:${RESET}"
sudo sgdisk --print "$DISK"
echo ""

ok "Disk setup complete."
echo ""
echo -e "${BOLD}What was created:${RESET}"
echo ""
echo -e "  ${CYAN}${DISK}p1${RESET}  1024 MiB  FAT32   /boot/efi"
echo -e "  ${CYAN}${DISK}p2${RESET}  1024 MiB  ext4    /boot"
echo -e "  ${CYAN}${DISK}p3${RESET}  ~254 GiB  btrfs   / (plain, no subvolumes)"
echo ""
echo -e "${BOLD}Expected /etc/fstab entries after installation:${RESET}"
echo ""
echo "  # EFI"
echo "  UUID=<uuid-of-p1>    /boot/efi   vfat    umask=0077              0  1"
echo ""
echo "  # boot"
echo "  UUID=<uuid-of-p2>    /boot       ext4    defaults                0  2"
echo ""
echo "  # root (plain btrfs, no subvolumes)"
echo "  UUID=<uuid-of-p3>    /           btrfs   defaults,noatime        0  0"
echo ""
echo -e "${BOLD}Retrieve UUIDs with:${RESET}"
echo -e "  ${CYAN}blkid $DISK*${RESET}"
echo ""
echo -e "${BOLD}Next step:${RESET} Launch refractainstaller-gui."
echo "  Select 'Do not format filesystems' and choose /dev/nvme0n1p3 as root."
echo "  The patched installer will auto-detect plain btrfs (no @rootfs subvolume)"
echo "  and set btrfs_mode=single, mounting the top-level volume as /."
