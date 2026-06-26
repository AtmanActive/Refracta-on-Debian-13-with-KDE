#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════════════════
# install_and_prepare_refracta_on_debian13.sh
#
# Downloads, installs, and configures Refracta tools on a fresh Debian 13
# (trixie) x64 installation. Prepares the system for creating btrfs-based
# custom ISOs with refractasnapshot and installing them with refractainstaller.
#
# This script is idempotent — safe to run multiple times. Each step inspects
# the current state and skips work already completed.
#
# What this script does:
#   1. Downloads Refracta .deb packages from SourceForge (correct URLs)
#   2. Installs them with apt (resolving dependencies automatically)
#   3. Sets COMPRESS=gzip in initramfs.conf and rebuilds initramfs
#   4. Enables --force-extra-removable in refractainstaller.conf so GRUB
#      creates the \EFI\BOOT\BOOTX64.EFI fallback (fixes VirtualBox boot)
#
# Run as root:  sudo bash install_and_prepare_refracta_on_debian13.sh
# ══════════════════════════════════════════════════════════════════════════════

# ── Configuration ─────────────────────────────────────────────────────────────
DOWNLOAD_DIR="/tmp/refracta-debs"
SF_BASE="https://sourceforge.net/projects/refracta/files/tools"

# Refracta packages: filename|package_name|expected_version
# NOTE: refractasnapshot-base is 10.4.3 (not 10.4.1 — that version does not
#       exist on SourceForge). The gui is 10.4.1. This mismatch is intentional
#       per the maintainer's note: "Use latest available version of -gui with
#       latest version of -base, even if numbers are different."
PACKAGES=(
    "refractasnapshot-base_10.4.3_all.deb|refractasnapshot-base|10.4.3"
    "refractasnapshot-gui_10.4.1_all.deb|refractasnapshot-gui|10.4.1"
    "refractainstaller-base_9.6.6_all.deb|refractainstaller-base|9.6.6"
    "refractainstaller-gui_9.6.6_all.deb|refractainstaller-gui|9.6.6"
    "refracta2usb-2.4.3.deb|refracta2usb|2.4.3"
)

# Additional packages to install from apt repos (needed for btrfs workflow)
EXTRA_APT_PACKAGES=( btrfs-progs )

# File paths
INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"
REFRACTA_CONF="/etc/refractainstaller.conf"

# Resolve the directory containing this script (for patch reference in summary)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour output ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()     { echo -e "${CYAN}==>${RESET} $*"; }
ok()      { echo -e "${GREEN}==>${RESET} $*"; }
warn()    { echo -e "${YELLOW}WARNING:${RESET} $*"; }
err()     { echo -e "${RED}ERROR:${RESET} $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}\n"; }

# ── Helper functions ──────────────────────────────────────────────────────────

# Check if a package is installed at a specific version
is_pkg_at_version() {
    local pkg="$1" expected_ver="$2"
    local installed_ver
    installed_ver=$(dpkg -s "$pkg" 2>/dev/null | awk '/^Version:/ {print $2}')
    [[ "$installed_ver" == "$expected_ver" ]]
}

# Check if a package is installed (any version)
is_pkg_installed() {
    dpkg -s "$1" &>/dev/null
}

# Check if a .deb file is a valid Debian package
is_deb_valid() {
    dpkg-deb -I "$1" >/dev/null 2>&1
}

# ══════════════════════════════════════════════════════════════════════════════
# Sanity Checks
# ══════════════════════════════════════════════════════════════════════════════
section "Sanity Checks"

if [[ "$EUID" -ne 0 ]]; then
    err "This script must be run as root."
    err "Use:  sudo bash install_and_prepare_refracta_on_debian13.sh"
    exit 1
fi

if ! grep -q 'VERSION_ID="13"' /etc/os-release 2>/dev/null; then
    warn "This script is designed for Debian 13 (trixie). Continuing anyway."
fi

if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    warn "This script is designed for amd64. The .deb packages are arch-independent."
fi

if ! command -v wget &>/dev/null; then
    err "wget is required but not installed. Install with: apt-get install wget"
    exit 1
fi

if ! command -v update-initramfs &>/dev/null; then
    err "update-initramfs not found. Install with: apt-get install initramfs-tools"
    exit 1
fi

ok "Sanity checks passed."

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Download Refracta Packages from SourceForge
# ══════════════════════════════════════════════════════════════════════════════
section "Step 1: Download Refracta Packages"

mkdir -p "$DOWNLOAD_DIR"

needs_download=()
needs_install=()

for entry in "${PACKAGES[@]}"; do
    IFS='|' read -r filename pkgname version <<< "$entry"
    filepath="$DOWNLOAD_DIR/$filename"
    url="$SF_BASE/$filename/download"

    if is_pkg_at_version "$pkgname" "$version"; then
        ok "$pkgname $version is already installed."
    else
        # Package is not at target version — check if a different version is installed
        installed_ver=$(dpkg -s "$pkgname" 2>/dev/null | awk '/^Version:/ {print $2}')
        if [[ -n "$installed_ver" ]]; then
            warn "$pkgname is at $installed_ver (target: $version) — will install $version."
        else
            log "$pkgname is not installed — will install $version."
        fi

        needs_install+=("$filepath")

        if [[ -f "$filepath" ]] && is_deb_valid "$filepath"; then
            log "$filename already downloaded and valid."
        else
            needs_download+=("$url|$filepath|$filename")
        fi
    fi
done

if [[ ${#needs_download[@]} -eq 0 ]]; then
    ok "All needed packages already downloaded or installed."
else
    for entry in "${needs_download[@]}"; do
        IFS='|' read -r url filepath filename <<< "$entry"
        log "Downloading $filename ..."
        if ! wget -q -O "$filepath" "$url"; then
            err "Download failed: $filename"
            err "URL: $url"
            rm -f "$filepath"
            exit 1
        fi
        if ! is_deb_valid "$filepath"; then
            err "Downloaded file is not a valid .deb: $filename"
            rm -f "$filepath"
            exit 1
        fi
        ok "Downloaded: $filename ($(du -h "$filepath" | cut -f1))"
    done
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — Install Packages
# ══════════════════════════════════════════════════════════════════════════════
section "Step 2: Install Packages"

# Build the full install list (local .debs + extra apt packages)
all_to_install=()
for filepath in "${needs_install[@]}"; do
    all_to_install+=("$filepath")
done

for pkg in "${EXTRA_APT_PACKAGES[@]}"; do
    if is_pkg_installed "$pkg"; then
        ok "$pkg is already installed."
    else
        all_to_install+=("$pkg")
        log "$pkg will be installed from apt."
    fi
done

if [[ ${#all_to_install[@]} -eq 0 ]]; then
    ok "All packages already installed. Nothing to do."
else
    log "Running apt-get update ..."
    apt-get update -qq

    log "Installing ${#all_to_install[@]} package(s) ..."
    if ! apt-get install -y "${all_to_install[@]}"; then
        err "apt-get install failed."
        exit 1
    fi
    ok "Packages installed successfully."
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Configure initramfs Compression + Rebuild
# ══════════════════════════════════════════════════════════════════════════════
section "Step 3: Configure initramfs Compression (gzip)"

if [[ ! -f "$INITRAMFS_CONF" ]]; then
    err "$INITRAMFS_CONF not found."
    exit 1
fi

initramfs_changed=0

if grep -qE '^COMPRESS=gzip' "$INITRAMFS_CONF"; then
    ok "COMPRESS=gzip is already set in $INITRAMFS_CONF"
elif grep -qE '^COMPRESS=' "$INITRAMFS_CONF"; then
    current_compress=$(grep -E '^COMPRESS=' "$INITRAMFS_CONF" | head -1 | cut -d= -f2)
    log "Changing COMPRESS from $current_compress to gzip ..."
    sed -i 's/^COMPRESS=.*/COMPRESS=gzip/' "$INITRAMFS_CONF"
    ok "COMPRESS set to gzip."
    initramfs_changed=1
elif grep -qE '^#[[:space:]]*COMPRESS=' "$INITRAMFS_CONF"; then
    log "Uncommenting and setting COMPRESS=gzip ..."
    sed -i 's/^#[[:space:]]*COMPRESS=.*/COMPRESS=gzip/' "$INITRAMFS_CONF"
    ok "COMPRESS set to gzip."
    initramfs_changed=1
else
    log "No COMPRESS line found — appending COMPRESS=gzip ..."
    echo 'COMPRESS=gzip' >> "$INITRAMFS_CONF"
    ok "COMPRESS=gzip added."
    initramfs_changed=1
fi

if [[ $initramfs_changed -eq 1 ]]; then
    log "Rebuilding initramfs for all kernels ..."
else
    log "Rebuilding initramfs for all kernels (ensuring correctness) ..."
fi

if update-initramfs -u -k all; then
    ok "initramfs rebuilt successfully."
else
    err "update-initramfs failed."
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Configure refractainstaller.conf (EFI fallback bootloader)
# ══════════════════════════════════════════════════════════════════════════════
section "Step 4: Enable EFI Fallback Bootloader in refractainstaller.conf"

if [[ ! -f "$REFRACTA_CONF" ]]; then
    warn "$REFRACTA_CONF not found. Is refractainstaller-base installed?"
    warn "Skipping this step."
else
    if grep -qE '^media_opt="--force-extra-removable"' "$REFRACTA_CONF"; then
        ok "media_opt is already uncommented in $REFRACTA_CONF"
    elif grep -qE '^#media_opt=' "$REFRACTA_CONF"; then
        log "Uncommenting media_opt ..."
        sed -i 's/^#media_opt=.*/media_opt="--force-extra-removable"/' "$REFRACTA_CONF"
        ok 'media_opt uncommented — GRUB will create \\EFI\\BOOT\\BOOTX64.EFI fallback.'
    elif grep -qE '^media_opt=' "$REFRACTA_CONF"; then
        log "media_opt is uncommented but has wrong value — fixing ..."
        sed -i 's/^media_opt=.*/media_opt="--force-extra-removable"/' "$REFRACTA_CONF"
        ok "media_opt set correctly."
    else
        log "No media_opt line found — appending ..."
        echo 'media_opt="--force-extra-removable"' >> "$REFRACTA_CONF"
        ok "media_opt added."
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
section "Summary"

echo -e "${BOLD}Refracta packages:${RESET}"
for entry in "${PACKAGES[@]}"; do
    IFS='|' read -r filename pkgname version <<< "$entry"
    if is_pkg_at_version "$pkgname" "$version"; then
        echo -e "  ${GREEN}OK${RESET}  $pkgname $version"
    else
        installed_ver=$(dpkg -s "$pkgname" 2>/dev/null | awk '/^Version:/ {print $2}')
        if [[ -n "$installed_ver" ]]; then
            echo -e "  ${RED}!!${RESET}  $pkgname $installed_ver (target: $version)"
        else
            echo -e "  ${RED}!!${RESET}  $pkgname NOT installed (target: $version)"
        fi
    fi
done

echo ""
echo -e "${BOLD}Additional packages:${RESET}"
for pkg in "${EXTRA_APT_PACKAGES[@]}"; do
    if is_pkg_installed "$pkg"; then
        echo -e "  ${GREEN}OK${RESET}  $pkg"
    else
        echo -e "  ${RED}!!${RESET}  $pkg NOT installed"
    fi
done

echo ""
echo -e "${BOLD}Configuration:${RESET}"
if grep -qE '^COMPRESS=gzip' "$INITRAMFS_CONF" 2>/dev/null; then
    echo -e "  ${GREEN}OK${RESET}  initramfs COMPRESS=gzip"
else
    echo -e "  ${RED}!!${RESET}  initramfs COMPRESS=gzip (NOT set)"
fi

if [[ -f "$REFRACTA_CONF" ]] && grep -qE '^media_opt="--force-extra-removable"' "$REFRACTA_CONF"; then
    echo -e "  ${GREEN}OK${RESET}  media_opt=--force-extra-removable (EFI fallback)"
else
    echo -e "  ${RED}!!${RESET}  media_opt=--force-extra-removable (NOT set)"
fi

echo ""
echo -e "${BOLD}Remaining manual steps:${RESET}"
echo ""
echo -e "  ${CYAN}btrfs patch:${RESET} Apply the btrfs filesystem support patch to"
echo -e "    refractainstaller if you want btrfs (with or without subvolumes):"
echo -e "    sudo patch -p1 -d / < ${SCRIPT_DIR}/btrfs-support-for-refractainstaller.patch"
echo ""
echo -e "  ${CYAN}Seed home environment:${RESET} Run the seed script before taking"
echo -e "    a snapshot to copy your KDE config into /etc/skel:"
echo -e "    bash ${SCRIPT_DIR}/refracta_seed_home_environment_before_iso_creation.sh"
echo ""
echo -e "  ${CYAN}Create ISO:${RESET} Run refractasnapshot to create the custom ISO."
echo ""
echo -e "  ${CYAN}Disk setup + install:${RESET} On the target machine, run"
echo -e "    disk_setup_for_btrfs_desktop.sh, then refractainstaller-gui."
echo ""
ok "Done."
