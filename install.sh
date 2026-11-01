#!/bin/sh
# Installer for hypr-uac. Idempotent: safe to re-run to upgrade.
#
# Touching /etc/pam.d/sudo is the one step that can hurt, so it is done last,
# after a backup, and the two lines are only ever inserted above the existing
# stack -- never replacing it. If anything in the dialog fails at runtime, PAM
# ignores it and your password stack runs as before.
set -eu

# The polkit agent is on by default: GUI apps that need root mostly try pkexec
# first, and with no agent registered pkexec just exits 127.
WITH_POLKIT_AGENT=1
for arg in "$@"; do
    case $arg in
        --polkit-agent) WITH_POLKIT_AGENT=1 ;;  # the default; kept for old scripts
        --no-polkit-agent) WITH_POLKIT_AGENT=0 ;;
        -h|--help)
            echo "usage: $0 [--no-polkit-agent]"
            echo "  --no-polkit-agent  keep your current polkit agent instead of"
            echo "                     replacing it with hypr-uac-polkit"
            exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

PREFIX=${PREFIX:-/usr/local}
ASKPASS_DIR=${ASKPASS_DIR:-$HOME/.local/bin}
UNIT_DIR=${UNIT_DIR:-$HOME/.config/systemd/user}
ENV_FILE=${ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/50-hypr-uac.conf}
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
sudo install -o root -g root -m 755 "$SRC/bin/hypr-uac-doctor" "$PREFIX/bin/hypr-uac-doctor"

say "==> installing the askpass shim into $ASKPASS_DIR"
install -d -m 755 "$ASKPASS_DIR"
install -m 755 "$SRC/bin/hypr-askpass" "$ASKPASS_DIR/hypr-askpass"

# Session-wide, not a shell rc file: the desktop session usually never runs
# your interactive shell, so an export in ~/.bashrc or config.fish reaches
# terminals and nothing else -- and GUI apps that fall back to `sudo -A` then
# report that no password prompt is available. environment.d is read by the
# systemd user manager, so it reaches services, D-Bus-activated apps and a
# Hyprland started through uwsm. A Hyprland started some other way needs
# examples/hyprland/env.lua as well; hypr-uac-doctor tells you which you have.
say "==> setting SUDO_ASKPASS / SSH_ASKPASS in $ENV_FILE"
install -d -m 755 "$(dirname -- "$ENV_FILE")"
cat > "$ENV_FILE" <<ENV
# Written by hypr-uac's install.sh; removed by uninstall.sh.
SUDO_ASKPASS=$ASKPASS_DIR/hypr-askpass
SSH_ASKPASS=$ASKPASS_DIR/hypr-askpass
ENV
# environment.d is only read when the user manager starts; this covers the
# rest of the current login.
systemctl --user set-environment \
    "SUDO_ASKPASS=$ASKPASS_DIR/hypr-askpass" "SSH_ASKPASS=$ASKPASS_DIR/hypr-askpass" 2>/dev/null || true

if [ "$WITH_POLKIT_AGENT" -eq 1 ]; then
    say "==> installing the polkit agent"
    sudo install -o root -g root -m 755 "$SRC/bin/hypr-uac-polkit" "$PREFIX/bin/hypr-uac-polkit"
    install -d -m 755 "$UNIT_DIR"
    sed "s|/usr/local/bin/hypr-uac-polkit|$PREFIX/bin/hypr-uac-polkit|" \
        "$SRC/systemd/hypr-uac-polkit.service" > "$UNIT_DIR/hypr-uac-polkit.service"
    systemctl --user daemon-reload
    # Only one agent may hold a session. The unit also carries Conflicts=, so
    # a stray `systemctl --user preset-all` re-enabling the old one cannot end
    # with both running.
    systemctl --user disable --now hyprpolkitagent.service 2>/dev/null || true
    systemctl --user enable --now hypr-uac-polkit.service
    say "    hyprpolkitagent disabled; hypr-uac-polkit enabled"
fi

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

say ""
say "Installed."
if ! grep -rqs 'hypr-uac' "${XDG_CONFIG_HOME:-$HOME/.config}/hypr"; then
    cat <<NOTE
One manual step remains:

  Window rules -- hypr-uac is a normal toplevel, so Hyprland will tile it
  unless you add the rules from:
      examples/hyprland/windowrules.lua   (Lua config)
      examples/hyprland/windowrules.conf  (hyprlang config)
NOTE
fi

cat <<NOTE

Optional: examples/polkit/ makes chosen polkit actions passwordless. Read the
comments first -- it is a different, promptless trade-off.

Running hypr-uac-doctor to check the result. Run it again any time something
that should prompt does not.
NOTE

"$PREFIX/bin/hypr-uac-doctor" || true
