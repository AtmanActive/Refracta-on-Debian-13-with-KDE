#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# skel-seed-lib.sh — shared library for seeding /etc/skel from a user's desktop
#
# SINGLE SOURCE OF TRUTH for WHICH dotfiles / configs get copied into /etc/skel
# so a Refracta snapshot boots as a near-identical clone of the running desktop.
#
# Sourced by:
#   • refractasnapshot / refractasnapshot-gui — the "seed /etc/skel" snapshot mode
#   • refracta_seed_home_environment_before_iso_creation.sh — standalone CLI
#
# Sourcing this file only DEFINES functions and arrays — it performs NO work and
# never calls exit. Call refracta_seed_skel <source_home> to do the seeding.
#
# Privilege model: writing /etc/skel needs root; reading the config needs the
# desktop user. The standalone script runs AS the user and elevates writes with
# sudo; refractasnapshot already runs AS root and reads the desktop user's home
# directly. _skel_as_root() bridges both (runs direct when already root, via
# sudo otherwise), and refracta_skel_source_home() finds the desktop user's home
# even when the caller is root (sudo/pkexec/uid-1000 fallback).
#
# To change WHAT gets seeded, edit the arrays below — every caller follows.
# ══════════════════════════════════════════════════════════════════════════════

REFRACTA_SKEL_TARGET="${REFRACTA_SKEL_TARGET:-/etc/skel}"

# ── Logging (plain; callers may tee/redirect stdout+stderr) ────────────────────
refracta_skel_log()  { echo "[skel] $*"; }
refracta_skel_warn() { echo "[skel] WARNING: $*" >&2; }
refracta_skel_err()  { echo "[skel] ERROR: $*" >&2; }

# ── Run a command with root privileges (direct if root, else via sudo) ─────────
_skel_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ── Resolve the desktop user's home even when running as root ───────────────────
# Order of preference: $SUDO_USER (sudo) → $PKEXEC_UID (pkexec/polkit) → the
# primary uid-1000 user. Echoes the home path (empty if it can't be determined).
refracta_skel_source_home() {
    local _u="" _h=""
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != root ]; then
        _u="$SUDO_USER"
    elif [ -n "$PKEXEC_UID" ]; then
        _u=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
    fi
    [ -z "$_u" ] && _u=$(awk -F: '$3==1000 {print $1; exit}' /etc/passwd)
    [ -n "$_u" ] && _h=$(getent passwd "$_u" | cut -d: -f6)
    printf '%s' "$_h"
}

# ══════════════════════════════════════════════════════════════════════════════
# The layout: what gets seeded (edit here — every caller follows)
# ══════════════════════════════════════════════════════════════════════════════

# ── Shell & terminal dotfiles ──────────────────────────────────────────────────
REFRACTA_SKEL_SHELL_DOTFILES=(
    ".bashrc" ".bash_profile" ".bash_aliases" ".bash_logout" ".profile"
    ".inputrc" ".dircolors" ".hushlogin"
    ".zshrc" ".zsh_history" ".zprofile" ".zshenv" ".zlogout"
    ".fishrc"
)

# ── KDE Plasma 6 core configuration files (~/.config/*) ─────────────────────────
REFRACTA_SKEL_KDE_CONFIG_FILES=(
    # Global / appearance
    ".config/kdeglobals" ".config/plasmarc" ".config/ksplashrc"
    ".config/kscreenlockerrc" ".config/breezerc" ".config/Trolltech.conf"
    ".config/kcmfonts" ".config/kcminputrc" ".config/kxkbrc"
    ".config/touchpadxlibinputrc" ".config/klaunchrc"
    # GTK integration (KDE applies these to GTK apps)
    ".config/gtkrc" ".config/gtkrc-2.0"
    # Panel & desktop layout
    ".config/plasma-org.kde.plasma.desktop-appletsrc" ".config/plasmashellrc"
    # Window manager (KWin)
    ".config/kwinrc" ".config/kwinrulesrc"
    # Activities
    ".config/kactivitymanagerdrc" ".config/kactivitymanagerd-switcher"
    ".config/kactivitymanagerd-statsrc" ".config/kactivitymanagerd-pluginsrc"
    # Shortcuts
    ".config/kglobalshortcutsrc" ".config/khotkeysrc"
    # Startup & session
    ".config/ksmserverrc" ".config/kded5rc" ".config/kded_device_automounterrc"
    ".config/device_automounter_kcmrc"
    # Search
    ".config/krunnerrc" ".config/baloofilerc" ".config/kuriikwsfiltersrc"
    # Notifications
    ".config/plasmanotifyrc" ".config/knotifyrc" ".config/kmixrc"
    # Regional & localisation
    ".config/plasma-localerc" ".config/ktimezonedrc" ".config/user-dirs.dirs"
    # Accessibility
    ".config/kaccessrc"
    # File associations & default apps
    ".config/mimeapps.list"
    # Power management
    ".config/powermanagementprofilesrc"
    # Display
    ".config/kgammarc"
    # Bluetooth
    ".config/bluedevilglobalrc"
    # Taskbar / task manager
    ".config/plasma-org.kde.plasma.taskmanager.defaultrc"
    # Misc KDE apps
    ".config/PlasmaUserFeedback" ".config/kfontinstuirc" ".config/spectaclerc"
    ".config/okularrc" ".config/okularpartrc" ".config/kiorc" ".config/kiosk"
    ".config/kprintrc"
)

# ── KDE / desktop config directories (~/.config/*) rsynced whole ───────────────
REFRACTA_SKEL_KDE_CONFIG_DIRS=(
    ".config/gtk-3.0" ".config/gtk-4.0" ".config/kdeconnect"
    ".config/autostart" ".config/autostart-scripts" ".config/autostart.d"
    ".config/plasma-workspace"
)

# ── KDE application data (~/.local/share/*) rsynced whole ───────────────────────
REFRACTA_SKEL_LOCAL_SHARE_DIRS=(
    "dolphin" "konsole" "plasma" "plasma-systemmonitor" "plasma_notes" "kwin"
    "kactivitymanagerd" "kservices5" "kservicetypes5" "kxmlgui5" "kscreen"
    "color-schemes" "plasma/desktoptheme" "icons" "themes" "fonts" "sounds"
    "kate" "okular" "spectacle" "knewstuff3"
)

# ── Exclusions for the bulk ~/.config sync (runtime/session-specific junk) ──────
REFRACTA_SKEL_CONFIG_EXCLUDES=(
    "pulse" "dconf" "ibus" "*.lock" "*.pid" "krunnerd" "session" "*.socket"
)

# ══════════════════════════════════════════════════════════════════════════════
# Copy helpers (operate relative to REFRACTA_SKEL_SRC, set by refracta_seed_skel)
# ══════════════════════════════════════════════════════════════════════════════

# _skel_copy <abs-path-under-source-home>
# Copies the file/dir into REFRACTA_SKEL_TARGET, preserving relative structure.
# Silently skips (with a note) if the source does not exist.
_skel_copy() {
    local SRC="$1"
    local RELATIVE="${SRC#$REFRACTA_SKEL_SRC/}"
    local DEST_DIR="$REFRACTA_SKEL_TARGET/$(dirname "$RELATIVE")"
    if [ ! -e "$SRC" ]; then
        refracta_skel_warn "skip (not found): ~/$RELATIVE"
        return
    fi
    _skel_as_root mkdir -p "$DEST_DIR"
    _skel_as_root cp -a "$SRC" "$DEST_DIR/"
    refracta_skel_log "copied: ~/$RELATIVE"
}

# _skel_rsync <abs-source-dir> <abs-dest-dir> [exclude ...]
_skel_rsync() {
    local SRC="$1" DEST="$2"; shift 2
    local EX RSYNC_ARGS=(-a --delete)
    if [ ! -d "$SRC" ]; then
        refracta_skel_warn "skip (not found): $SRC"
        return
    fi
    for EX in "$@"; do RSYNC_ARGS+=(--exclude="$EX"); done
    _skel_as_root mkdir -p "$DEST"
    _skel_as_root rsync "${RSYNC_ARGS[@]}" "$SRC/" "$DEST/"
    refracta_skel_log "synced: $SRC → $DEST"
}

# ══════════════════════════════════════════════════════════════════════════════
# refracta_seed_skel <source_home>
# Seeds REFRACTA_SKEL_TARGET from the given home directory. Returns 0 on success,
# 1 on a setup error (never exits, so a caller can warn-and-continue).
# ══════════════════════════════════════════════════════════════════════════════
refracta_seed_skel() {
    REFRACTA_SKEL_SRC="${1:-$HOME}"

    if [ -z "$REFRACTA_SKEL_SRC" ]; then
        refracta_skel_err "no source home directory given"
        return 1
    fi
    if [ ! -d "$REFRACTA_SKEL_SRC" ]; then
        refracta_skel_err "source home not found: $REFRACTA_SKEL_SRC"
        return 1
    fi
    if [ ! -d "$REFRACTA_SKEL_TARGET" ]; then
        refracta_skel_err "$REFRACTA_SKEL_TARGET does not exist (not a Debian-based system?)"
        return 1
    fi

    refracta_skel_log "source home : $REFRACTA_SKEL_SRC"
    refracta_skel_log "target skel : $REFRACTA_SKEL_TARGET"

    local FILE DIR

    # 1 — shell & terminal dotfiles
    for FILE in "${REFRACTA_SKEL_SHELL_DOTFILES[@]}"; do
        _skel_copy "$REFRACTA_SKEL_SRC/$FILE"
    done

    # 2 — KDE Plasma 6 core config files
    for FILE in "${REFRACTA_SKEL_KDE_CONFIG_FILES[@]}"; do
        _skel_copy "$REFRACTA_SKEL_SRC/$FILE"
    done

    # 2b — KDE / desktop config directories
    for DIR in "${REFRACTA_SKEL_KDE_CONFIG_DIRS[@]}"; do
        _skel_rsync "$REFRACTA_SKEL_SRC/$DIR" "$REFRACTA_SKEL_TARGET/$DIR"
    done

    # 3 — KDE application data (~/.local/share)
    for DIR in "${REFRACTA_SKEL_LOCAL_SHARE_DIRS[@]}"; do
        _skel_rsync "$REFRACTA_SKEL_SRC/.local/share/$DIR" "$REFRACTA_SKEL_TARGET/.local/share/$DIR"
    done
    _skel_copy "$REFRACTA_SKEL_SRC/.local/share/user-places.xbel"

    # 4 — all other ~/.config (bulk, with exclusions)
    _skel_rsync "$REFRACTA_SKEL_SRC/.config" "$REFRACTA_SKEL_TARGET/.config" \
        "${REFRACTA_SKEL_CONFIG_EXCLUDES[@]}"

    # 5 — local binaries
    _skel_rsync "$REFRACTA_SKEL_SRC/.local/bin" "$REFRACTA_SKEL_TARGET/.local/bin"

    # 6 — fix ownership (/etc/skel must be root:root; live system re-chowns per user)
    _skel_as_root chown -R root:root "$REFRACTA_SKEL_TARGET"
    refracta_skel_log "ownership set to root:root on $REFRACTA_SKEL_TARGET"

    return 0
}

# ── Human-readable summary of what is intentionally NOT seeded ──────────────────
refracta_skel_exclusions_note() {
    cat <<'EOF'
Intentionally NOT seeded into /etc/skel:

  ~/.cache/                        Regenerated at runtime
  ~/.local/share/Trash/            Unwanted
  ~/.local/share/thumbnails/       Regenerated by the file manager
  ~/.local/share/baloo/            Baloo file index (can be hundreds of MB)
  ~/.local/share/akonadi/          Akonadi PIM database (machine/session specific)
  ~/.local/share/recently-used.xbel   Session-specific recent files list
  ~/.local/share/kwalletd/         KDE Wallet — encrypted passwords (SECURITY)
  ~/.local/share/sddm/             Display manager session data (machine-specific)
  ~/.config/pulse/                 PulseAudio runtime state
  ~/.config/dconf/                 GNOME/dconf binary DB (not relevant to KDE)
  *.lock / *.pid / *.socket        Runtime lock/socket files

NOTE on KDE Wallet: saved passwords (WiFi, websites, etc.) are deliberately
excluded. You will need to re-enter passwords after installing from the ISO.
EOF
}
