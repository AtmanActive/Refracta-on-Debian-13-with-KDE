#!/usr/bin/env bash
#
# Wrapper for refractasnapshot-gui

command="/usr/bin/refractasnapshot-gui"

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

# --- welcome banner shown in the xterm before the password prompt ---
# Printed inside the xterm right before sudo/su asks for a password, so the
# prompt no longer appears "out of the blue". The final line (which password to
# type) is only added when a password is actually required; pass "none" to omit
# it. Never errors and never blocks.
refracta_welcome_banner() {  # $1 = auth hint: sudo | root | none
	printf '%s\n' \
		'' \
		'  Welcome to Refracta Snapshot.' \
		'' \
		'  This program will collect your running operating system into an ISO' \
		'  file ready to be deployed on the next machine.' \
		''
	case "$1" in
		sudo) printf '%s\n' '  To continue, please enter your sudo password.' ;;
		root) printf '%s\n' '  To continue, please enter the root password.' ;;
	esac
}

# I hope nobody uses this, but it's here
# in case you're running a root xsession.
if [[ $(id -u) -eq 0 ]] ; then
	"$command"
	exit 0
fi

# This will be used to test for sudo nopasswd.
sudo_allowed=$(sudo -n uptime 2>&1 | grep load | wc -l)

if [[ -e $(which gksu) ]] ; then
	gksu "$command"
elif
	[[ -e $(which kdesu) ]] ; then
	kdesu "$command"
elif
	[[ -e $(which kdesudo) ]] ; then
	kdesudo "$command"
elif
	#another way to do it
	[[ -e $(which tdesu) ]] ; then
	tdesu "$command"
elif
	[[ -e $(which ktsuss) ]] ; then
	ktsuss "$command" 
elif
	# for sudo with no password
	[[ $sudo_allowed -ne 0 ]] ; then
		sudo "$command"
elif
	# for sudo with password
	$(groups $USER | grep -qs sudo); then
	# Only claim a password is needed if sudo would actually ask for one.
	if sudo -n true 2>/dev/null ; then _auth=none ; else _auth=sudo ; fi
	REFRACTA_BANNER="$(refracta_welcome_banner "$_auth")"
	export REFRACTA_BANNER command
	xterm $XTC -fa mono -fs 12 -e bash -c 'printf "%s\n\n" "$REFRACTA_BANNER"; exec sudo "$command"'
else
	REFRACTA_BANNER="$(refracta_welcome_banner root)"
	export REFRACTA_BANNER command
	xterm $XTC -fa mono -fs 12 -e bash -c 'printf "%s\n\n" "$REFRACTA_BANNER"; exec su -c "$command"'
fi

exit 0
