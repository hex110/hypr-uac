#!/bin/sh
# Installer for hypr-uac. Idempotent: safe to re-run to upgrade.
#
# Touching /etc/pam.d/sudo is the one step that can hurt, so it is done last,
# after a backup, and the two lines are only ever inserted above the existing
# stack -- never replacing it. If anything in the dialog fails at runtime, PAM
# ignores it and your password stack runs as before.
set -eu

PREFIX=${PREFIX:-/usr/local}
ASKPASS_DIR=${ASKPASS_DIR:-$HOME/.local/bin}
PAM_SUDO=${PAM_SUDO:-/etc/pam.d/sudo}
BACKUP_DIR=$PREFIX/share/hypr-uac
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user; it calls sudo itself"

for dep in python3 sudo; do
    command -v "$dep" >/dev/null 2>&1 || die "missing dependency: $dep"
done
python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1")' 2>/dev/null \
    || die "missing GTK4 + libadwaita python bindings (Arch: python-gobject gtk4 libadwaita)"

say "==> installing the dialog and PAM helper into $PREFIX/bin"
sudo install -d -m 755 "$PREFIX/bin" "$BACKUP_DIR"
sudo install -o root -g root -m 755 "$SRC/bin/hypr-uac"     "$PREFIX/bin/hypr-uac"
sudo install -o root -g root -m 755 "$SRC/bin/hypr-uac-pam" "$PREFIX/bin/hypr-uac-pam"

say "==> installing the askpass shim into $ASKPASS_DIR"
install -d -m 755 "$ASKPASS_DIR"
install -m 755 "$SRC/bin/hypr-askpass" "$ASKPASS_DIR/hypr-askpass"

say "==> wiring $PAM_SUDO"
if grep -q 'hypr-uac-pam' "$PAM_SUDO"; then
    say "    already wired, leaving it alone"
else
    sudo cp "$PAM_SUDO" "$BACKUP_DIR/pam.d-sudo.orig"
    say "    backed up to $BACKUP_DIR/pam.d-sudo.orig"
    tmp=$(mktemp)
    # Insert above the first auth line, keeping the rest of the stack intact.
    awk '
        !done && /^[[:space:]]*auth[[:space:]]/ {
            print "auth\t\t[success=done default=ignore]\tpam_exec.so quiet '"$PREFIX"'/bin/hypr-uac-pam prompt"
            print "auth\t\t[success=die default=ignore]\tpam_exec.so quiet '"$PREFIX"'/bin/hypr-uac-pam denied"
            done = 1
        }
        { print }
    ' "$PAM_SUDO" > "$tmp"
    grep -q 'hypr-uac-pam' "$tmp" || { rm -f "$tmp"; die "no auth line found in $PAM_SUDO; wire it by hand from examples/pam/sudo"; }
    sudo install -o root -g root -m 644 "$tmp" "$PAM_SUDO"
    rm -f "$tmp"
fi

cat <<NOTE

Installed. Two manual steps remain:

1. Window rules -- hypr-uac is a normal toplevel, so Hyprland will tile it
   unless you add the rules from:
       examples/hyprland/windowrules.lua   (Lua config)
       examples/hyprland/windowrules.conf  (hyprlang config)

2. Askpass, so the fallback and ssh use the same window. Add to your shell:
       export SUDO_ASKPASS=$ASKPASS_DIR/hypr-askpass
       export SSH_ASKPASS=$ASKPASS_DIR/hypr-askpass
   (fish: set -gx SUDO_ASKPASS $ASKPASS_DIR/hypr-askpass)
   Leave SSH_ASKPASS_REQUIRE unset unless you want ssh to prefer the dialog
   over your terminal.

Optional: examples/polkit/ makes chosen polkit actions passwordless. Read the
comments first -- it is a different, promptless trade-off.

Test with:  sudo -k && sudo id
If the dialog never appears, the password prompt still works; nothing is lost.
NOTE
