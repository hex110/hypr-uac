#!/bin/sh
# Reverses install.sh. Restores the original /etc/pam.d/sudo first, so the
# password stack is back before the helper it refers to disappears.
set -eu

PREFIX=${PREFIX:-/usr/local}
ASKPASS_DIR=${ASKPASS_DIR:-$HOME/.local/bin}
PAM_SUDO=${PAM_SUDO:-/etc/pam.d/sudo}
BACKUP_DIR=$PREFIX/share/hypr-uac

say() { printf '%s\n' "$*"; }

[ "$(id -u)" -ne 0 ] || { echo "run as your normal user" >&2; exit 1; }

if [ -f "$BACKUP_DIR/pam.d-sudo.orig" ]; then
    say "==> restoring $PAM_SUDO from backup"
    sudo install -o root -g root -m 644 "$BACKUP_DIR/pam.d-sudo.orig" "$PAM_SUDO"
elif grep -q 'hypr-uac-pam' "$PAM_SUDO" 2>/dev/null; then
    say "==> no backup found; stripping the hypr-uac lines from $PAM_SUDO"
    tmp=$(mktemp)
    grep -v 'hypr-uac-pam' "$PAM_SUDO" > "$tmp"
    sudo install -o root -g root -m 644 "$tmp" "$PAM_SUDO"
    rm -f "$tmp"
fi

if [ -f "$HOME/.config/systemd/user/hypr-uac-polkit.service" ]; then
    say "==> restoring the original polkit agent"
    systemctl --user disable --now hypr-uac-polkit.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/hypr-uac-polkit.service"
    systemctl --user daemon-reload
    systemctl --user enable --now hyprpolkitagent.service 2>/dev/null || \
        say "    could not re-enable hyprpolkitagent; enable an agent yourself"
fi

say "==> removing binaries"
sudo rm -f "$PREFIX/bin/hypr-uac" "$PREFIX/bin/hypr-uac-pam" \
           "$PREFIX/bin/hypr-uac-polkit"
rm -f "$ASKPASS_DIR/hypr-askpass"

say "Done. Remove the window rules, the SUDO_ASKPASS/SSH_ASKPASS exports and"
say "any /etc/polkit-1/rules.d/49-hypr-uac-desktop.rules by hand."
