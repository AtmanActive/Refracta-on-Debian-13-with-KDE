#!/usr/bin/env bash

# ══════════════════════════════════════════════════════════════════════════════
# seed-skel.sh
# Seeds /etc/skel with the current user's full KDE Plasma 6 configuration,
# application settings, and dotfiles so that a Refracta-created ISO boots
# as a near-identical clone of this running system.
#
# Usage:   bash seed-skel.sh
# Run as:  Regular user (NOT root). The script uses sudo only where needed.
# Safe to: Re-run at any time before taking a Refracta snapshot.
# ══════════════════════════════════════════════════════════════════════════════

# ── Configuration ─────────────────────────────────────────────────────────────
SOURCE_HOME="$HOME"
TARGET_SKEL="/etc/skel"
LOG_FILE="/tmp/seed-skel-$(date +%Y%m%d-%H%M%S).log"

# ── Colour output ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log()     { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" | tee -a "$LOG_FILE"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}" | tee -a "$LOG_FILE"; }

# ── Sanity Checks ─────────────────────────────────────────────────────────────
section "Sanity Checks"

if [ "$EUID" -eq 0 ]; then
    err "Do not run this script as root. Run as your regular user."
    exit 1
fi

if [ ! -d "$TARGET_SKEL" ]; then
    err "/etc/skel does not exist. Is this a Debian-based system?"
    exit 1
fi

log "Source home : $SOURCE_HOME"
log "Target skel : $TARGET_SKEL"
log "Log file    : $LOG_FILE"
echo ""

# ── Safety Confirmation ───────────────────────────────────────────────────────
echo -e "${YELLOW}This will overwrite files in /etc/skel with your current user's settings.${RESET}"
echo -e "${YELLOW}This is intended to be run BEFORE taking a Refracta snapshot.${RESET}"
echo ""
read -rp "Type YES to confirm and continue: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted by user."
    exit 0
fi

# ── Helper: safe sudo copy ────────────────────────────────────────────────────
# Copies $1 into $TARGET_SKEL, preserving directory structure.
# Skips silently if source does not exist.
skel_copy() {
    local SRC="$1"
    local RELATIVE="${SRC#$SOURCE_HOME/}"          # e.g. .config/dolphinrc
    local DEST_DIR="$TARGET_SKEL/$(dirname "$RELATIVE")"

    if [ ! -e "$SRC" ]; then
        warn "Skipping (not found): $SRC"
        return
    fi

    sudo mkdir -p "$DEST_DIR"

    if [ -d "$SRC" ]; then
        sudo cp -a "$SRC" "$DEST_DIR/"
    else
        sudo cp -a "$SRC" "$DEST_DIR/"
    fi
    ok "Copied: ~/$RELATIVE"
}

# ── Helper: rsync a directory with exclusions ─────────────────────────────────
skel_rsync() {
    local SRC="$1"          # absolute source path
    local DEST="$2"         # absolute destination path
    shift 2
    local EXCLUDES=("$@")   # remaining args are rsync --exclude patterns

    if [ ! -d "$SRC" ]; then
        warn "Skipping (not found): $SRC"
        return
    fi

    sudo mkdir -p "$DEST"

    local RSYNC_ARGS=(-a --delete)
    for EX in "${EXCLUDES[@]}"; do
        RSYNC_ARGS+=(--exclude="$EX")
    done

    sudo rsync "${RSYNC_ARGS[@]}" "$SRC/" "$DEST/"
    ok "Synced: $SRC → $DEST"
}

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — Shell & Terminal Dotfiles
# ══════════════════════════════════════════════════════════════════════════════
section "Shell & Terminal Dotfiles"

SHELL_DOTFILES=(
    ".bashrc"
    ".bash_profile"
    ".bash_aliases"
    ".bash_logout"
    ".profile"
    ".inputrc"
    ".dircolors"
    ".hushlogin"
    ".zshrc"
    ".zsh_history"          # optional — remove if you don't want history seeded
    ".zprofile"
    ".zshenv"
    ".zlogout"
    ".fishrc"
)

for FILE in "${SHELL_DOTFILES[@]}"; do
    skel_copy "$SOURCE_HOME/$FILE"
done

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — KDE Plasma 6 Core Configuration (~/.config/)
# ══════════════════════════════════════════════════════════════════════════════
section "KDE Plasma 6 Core Configuration"

KDE_CONFIG_FILES=(
    # ── Global / Appearance ──────────────────────────────────────────────
    ".config/kdeglobals"                    # fonts, colours, icons, app style
    ".config/plasmarc"                      # Plasma style, general behaviour
    ".config/ksplashrc"                     # splash screen
    ".config/kscreenlockerrc"               # screen locker / global theme
    ".config/breezerc"                      # Breeze window decoration settings
    ".config/Trolltech.conf"                # Qt colour settings
    ".config/kcmfonts"                      # font rendering / DPI
    ".config/kcminputrc"                    # mouse, cursor, touchpad (Wayland)
    ".config/kxkbrc"                        # keyboard layouts
    ".config/touchpadxlibinputrc"           # touchpad (X11)
    ".config/klaunchrc"                     # launch feedback

    # ── GTK integration (KDE applies these to GTK apps) ─────────────────
    ".config/gtkrc"
    ".config/gtkrc-2.0"

    # ── Panel & Desktop layout ────────────────────────────────────────────
    ".config/plasma-org.kde.plasma.desktop-appletsrc"   # panel + widget layout
    ".config/plasmashellrc"                             # panel positioning

    # ── Window Manager (KWin) ─────────────────────────────────────────────
    ".config/kwinrc"                        # effects, edges, compositing, rules
    ".config/kwinrulesrc"                   # per-window rules

    # ── Activities ────────────────────────────────────────────────────────
    ".config/kactivitymanagerdrc"
    ".config/kactivitymanagerd-switcher"
    ".config/kactivitymanagerd-statsrc"
    ".config/kactivitymanagerd-pluginsrc"

    # ── Shortcuts ─────────────────────────────────────────────────────────
    ".config/kglobalshortcutsrc"            # global keyboard shortcuts
    ".config/khotkeysrc"                    # custom shortcuts

    # ── Startup & Session ─────────────────────────────────────────────────
    ".config/ksmserverrc"                   # session manager (restore windows)
    ".config/kded5rc"                       # background services
    ".config/kded_device_automounterrc"
    ".config/device_automounter_kcmrc"

    # ── Search ────────────────────────────────────────────────────────────
    ".config/krunnerrc"                     # KRunner settings
    ".config/baloofilerc"                   # Baloo file search settings (not index)
    ".config/kuriikwsfiltersrc"             # web search keywords

    # ── Notifications ─────────────────────────────────────────────────────
    ".config/plasmanotifyrc"
    ".config/knotifyrc"
    ".config/kmixrc"

    # ── Regional & Localisation ────────────────────────────────────────────
    ".config/plasma-localerc"
    ".config/ktimezonedrc"
    ".config/user-dirs.dirs"                # XDG user dirs (Downloads, etc.)

    # ── Accessibility ─────────────────────────────────────────────────────
    ".config/kaccessrc"

    # ── File Associations & Default Apps ─────────────────────────────────
    ".config/mimeapps.list"

    # ── Power Management ──────────────────────────────────────────────────
    ".config/powermanagementprofilesrc"

    # ── Display ───────────────────────────────────────────────────────────
    ".config/kgammarc"                      # display gamma / night colour

    # ── Bluetooth ─────────────────────────────────────────────────────────
    ".config/bluedevilglobalrc"

    # ── Taskbar / Task Manager ────────────────────────────────────────────
    ".config/plasma-org.kde.plasma.taskmanager.defaultrc"

    # ── Miscellaneous KDE apps ─────────────────────────────────────────────
    ".config/PlasmaUserFeedback"
    ".config/kfontinstuirc"
    ".config/spectaclerc"                   # screenshot tool
    ".config/okularrc"                      # PDF viewer
    ".config/okularpartrc"
    ".config/kiorc"                         # KIO file operations
    ".config/kiosk"
    ".config/kprintrc"                      # printing
)

for FILE in "${KDE_CONFIG_FILES[@]}"; do
    skel_copy "$SOURCE_HOME/$FILE"
done

# ── KDE Config Directories ──────────────────────────────────────────────────
section "KDE Config Directories"

KDE_CONFIG_DIRS=(
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/kdeconnect"                    # KDE Connect device pairing
    ".config/autostart"                     # autostart .desktop entries
    ".config/autostart-scripts"             # autostart shell scripts
    ".config/autostart.d"
    ".config/plasma-workspace"              # wallpaper and workspace extras
)

for DIR in "${KDE_CONFIG_DIRS[@]}"; do
    if [ -d "$SOURCE_HOME/$DIR" ]; then
        skel_rsync "$SOURCE_HOME/$DIR" "$TARGET_SKEL/$DIR"
    fi
done

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — KDE Application Data (~/.local/share/)
# Synced with explicit exclusions for caches/runtime/security-sensitive data
# ══════════════════════════════════════════════════════════════════════════════
section "KDE Application Data (~/.local/share/)"

LOCAL_SHARE_DIRS=(
    "dolphin"                   # Dolphin bookmarks, view properties per folder
    "konsole"                   # Konsole profiles and colour schemes
    "plasma"                    # Plasma extras
    "plasma-systemmonitor"      # System Monitor custom pages
    "plasma_notes"              # Plasma sticky notes widget
    "kwin"                      # KWin scripts and rules
    "kactivitymanagerd"         # Activity data
    "kservices5"                # Service menus, search providers
    "kservicetypes5"
    "kxmlgui5"                  # Toolbar customisations per application
    "kscreen"                   # Monitor layout profiles
    "color-schemes"             # Custom colour schemes
    "plasma/desktoptheme"       # Custom Plasma themes (if any installed to user)
    "icons"                     # User-installed icon themes
    "themes"                    # User-installed themes
    "fonts"                     # User-installed fonts
    "sounds"                    # Custom notification sounds
    "kate"                      # Kate editor sessions and settings
    "okular"                    # Okular annotations
    "spectacle"                 # Spectacle screenshot history (config only)
    "knewstuff3"                # Installed "Get Hot New Stuff" items
)

for DIR in "${LOCAL_SHARE_DIRS[@]}"; do
    SRC="$SOURCE_HOME/.local/share/$DIR"
    DEST="$TARGET_SKEL/.local/share/$DIR"
    if [ -d "$SRC" ]; then
        skel_rsync "$SRC" "$DEST"
    fi
done

# ── user-places.xbel — Dolphin/Nautilus sidebar bookmarks ─────────────────
# Included: useful to have your bookmarks present in the live ISO.
# Note: machine-specific paths (e.g. /home/yourname/...) will appear but
#       won't break anything — they simply won't resolve until you install.
skel_copy "$SOURCE_HOME/.local/share/user-places.xbel"

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Non-KDE Application Configs (~/.config/ — everything else)
# This catches configs for Firefox, VSCode, terminals, editors, etc.
# Excludes known problematic or cache-like directories.
# ══════════════════════════════════════════════════════════════════════════════
section "All Other Application Configs (~/.config/ bulk sync)"

skel_rsync \
    "$SOURCE_HOME/.config" \
    "$TARGET_SKEL/.config" \
    "pulse"             \
    "dconf"             \
    "ibus"              \
    "*.lock"            \
    "*.pid"             \
    "krunnerd"          \
    "session"           \
    "*.socket"

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 5 — Local Binaries (~/.local/bin/)
# ══════════════════════════════════════════════════════════════════════════════
section "Local Binaries (~/.local/bin/)"

if [ -d "$SOURCE_HOME/.local/bin" ]; then
    skel_rsync "$SOURCE_HOME/.local/bin" "$TARGET_SKEL/.local/bin"
fi

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 6 — Fix Ownership
# /etc/skel contents must be owned by root:root.
# When the live system creates a new user from skel, it re-chowns automatically.
# ══════════════════════════════════════════════════════════════════════════════
section "Fixing Ownership (chown root:root)"

sudo chown -R root:root "$TARGET_SKEL"
ok "Ownership set to root:root on all /etc/skel contents."

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 7 — What Was Intentionally Excluded (summary)
# ══════════════════════════════════════════════════════════════════════════════
section "Intentional Exclusions Summary"

cat <<'EOF'
The following were intentionally NOT seeded into /etc/skel:

  ~/.cache/                        Regenerated at runtime — always excluded
  ~/.local/share/Trash/            Obviously unwanted
  ~/.local/share/thumbnails/       Regenerated by the file manager at runtime
  ~/.local/share/baloo/            Baloo file index database (can be hundreds of MB)
  ~/.local/share/akonadi/          Akonadi PIM database (machine/session specific)
  ~/.local/share/recently-used.xbel   Session-specific recent files list
  ~/.local/share/kwalletd/         KDE Wallet — contains encrypted passwords (SECURITY)
  ~/.local/share/sddm/             Display manager session data (machine-specific)
  ~/.config/pulse/                 PulseAudio runtime state
  ~/.config/dconf/                 GNOME/dconf binary DB (not relevant to KDE)
  *.lock / *.pid / *.socket        Runtime lock/socket files — always excluded

  NOTE on KDE Wallet: your saved passwords (WiFi, websites, etc.) are deliberately
  excluded. You will need to re-enter passwords after installing from the ISO.
  If you want wallet data included, manually copy ~/.local/share/kwalletd/ after
  reviewing its contents and security implications.
EOF

# ══════════════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════════════
section "Complete"
echo ""
ok "Seeding complete. Full log saved to: $LOG_FILE"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Review /etc/skel to confirm it looks correct"
echo "  2. Run: sudo refractasnapshot"
echo "  3. The resulting ISO will boot with your full KDE Plasma setup intact"
echo ""
