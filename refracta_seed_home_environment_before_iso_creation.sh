#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════════════════
# refracta_seed_home_environment_before_iso_creation.sh
# Seeds /etc/skel with the current user's full KDE Plasma 6 configuration,
# application settings, and dotfiles so that a Refracta-created ISO boots
# as a near-identical clone of this running system.
#
# The actual list of what gets seeded + the copy logic live in the SHARED
# library skel-seed-lib.sh (the single source of truth, also used by the
# patched refractasnapshot's "seed /etc/skel" snapshot mode). This script is
# the standalone CLI wrapper around it.
#
# Usage:   bash refracta_seed_home_environment_before_iso_creation.sh
# Run as:  Regular user (NOT root). Writes to /etc/skel are elevated with sudo.
# Safe to: Re-run at any time before taking a Refracta snapshot.
# ══════════════════════════════════════════════════════════════════════════════

# ── Configuration ─────────────────────────────────────────────────────────────
LOG_FILE="/tmp/seed-skel-$(date +%Y%m%d-%H%M%S).log"

# ── Colour output ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log()     { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}" | tee -a "$LOG_FILE"; }

# ── Load the shared library (single source of truth) ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB=""
for _cand in /usr/lib/refractasnapshot/skel-seed-lib.sh "$SCRIPT_DIR/skel-seed-lib.sh"; do
    [ -f "$_cand" ] && { LIB="$_cand"; break; }
done
if [ -z "$LIB" ]; then
    err "skel-seed-lib.sh not found (looked in /usr/lib/refractasnapshot and $SCRIPT_DIR)."
    err "Apply the refractasnapshot skel-seed patch, or keep skel-seed-lib.sh next to this script."
    exit 1
fi
# shellcheck source=/dev/null
source "$LIB"

# ── Sanity Checks ─────────────────────────────────────────────────────────────
section "Sanity Checks"

if [ "$EUID" -eq 0 ]; then
    err "Do not run this script as root. Run as your regular user (writes use sudo)."
    exit 1
fi

if [ ! -d "$REFRACTA_SKEL_TARGET" ]; then
    err "$REFRACTA_SKEL_TARGET does not exist. Is this a Debian-based system?"
    exit 1
fi

log "Source home : $HOME"
log "Target skel : $REFRACTA_SKEL_TARGET"
log "Log file    : $LOG_FILE"
echo ""

# ── Safety Confirmation ───────────────────────────────────────────────────────
echo -e "${YELLOW}This will overwrite files in $REFRACTA_SKEL_TARGET with your current user's settings.${RESET}"
echo -e "${YELLOW}This is intended to be run BEFORE taking a Refracta snapshot.${RESET}"
echo ""
read -rp "Type YES to confirm and continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted by user."
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# Seed /etc/skel (delegated to the shared library)
# ══════════════════════════════════════════════════════════════════════════════
section "Seeding $REFRACTA_SKEL_TARGET"

if ! refracta_seed_skel "$HOME" 2>&1 | tee -a "$LOG_FILE"; then
    err "Seeding failed. See messages above and $LOG_FILE."
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# What Was Intentionally Excluded (summary)
# ══════════════════════════════════════════════════════════════════════════════
section "Intentional Exclusions Summary"
refracta_skel_exclusions_note | tee -a "$LOG_FILE"

# ── Done ───────────────────────────────────────────────────────────────────────
section "Complete"
echo ""
ok "Seeding complete. Full log saved to: $LOG_FILE"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Review $REFRACTA_SKEL_TARGET to confirm it looks correct"
echo "  2. Run: sudo refractasnapshot   (or just use the default 'seed + UEFI' mode)"
echo "  3. The resulting ISO will boot with your full KDE Plasma setup intact"
echo ""
