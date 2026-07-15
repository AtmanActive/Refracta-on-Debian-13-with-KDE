#!/usr/bin/env bash
#
# New wrapper for refractainstaller-yad 9.5.0

TEXTDOMAIN=refractainstaller-gui
TEXTDOMAINDIR=/usr/share/locale/

# --- theme-aware xterm colours (best-effort; silent + never a dependency) ---
# refracta_xterm_theme echoes xterm colour flags matching the desktop's
# light/dark preference, or NOTHING if it can't tell (so xterm keeps its
# built-in colours). It never errors, hangs, or requires the query tools.
# When run as root via sudo it reads the invoking user's KDE config.
refracta_xterm_theme() {
	local mode="" k bg r g b s cs home="$HOME"
	if [[ $EUID -eq 0 && -n $SUDO_USER ]]; then
		home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
		[[ -d $home ]] || home="$HOME"
	fi
	if   command -v kreadconfig6 >/dev/null 2>&1; then k=kreadconfig6
	elif command -v kreadconfig5 >/dev/null 2>&1; then k=kreadconfig5 ; fi
	if [[ -n $k ]]; then
		bg=$(HOME="$home" "$k" --file kdeglobals --group 'Colors:Window' --key BackgroundNormal 2>/dev/null)
		IFS=',' read -r r g b _ <<< "$bg"
		if [[ $r =~ ^[0-9]+$ && $g =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]]; then
			(( (r*299 + g*587 + b*114) / 1000 < 128 )) && mode=dark || mode=light
		else
			s=$(HOME="$home" "$k" --file kdeglobals --group General --key ColorScheme 2>/dev/null)
			case "${s,,}" in *dark*) mode=dark ;; *light*) mode=light ;; esac
		fi
	fi
	if [[ -z $mode ]] && command -v gsettings >/dev/null 2>&1; then
		cs=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)
		case "$cs" in *prefer-dark*) mode=dark ;; *prefer-light*) mode=light ;; esac
	fi
	case "$mode" in
		dark)  printf '%s' '-bg #232629 -fg #fcfcfc -cr #3daee9' ;;
		light) printf '%s' '-bg #fcfcfc -fg #232629 -cr #3daee9' ;;
	esac
}
XTC="$(refracta_xterm_theme)"

if ! [[ -f /usr/bin/yad ]]; then
	xterm $XTC -fa mono -fs 14 -geometry 80x20+0+0 -e 'echo $"Yad is not installed. 
Install it or run the text-only refractainstaller in a root terminal."' &
	exit 0
fi

installer="/usr/bin/refractainstaller-yad"


# Start script in terminal with sudo. Most live systems have sudo nopasswd.
# If sudo fails, ask for root password.
xterm $XTC -fa mono -fs 12 -e  "echo 'If user password fails, use root password.' && sudo  $installer ||  su -c $installer"


exit 0

