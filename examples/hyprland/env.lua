-- Only needed when Hyprland is NOT started through systemd (uwsm): then it
-- never sees ~/.config/environment.d, and neither does anything it launches.
-- hypr-uac-doctor says whether you need this. Adjust the path if you installed
-- with a different ASKPASS_DIR.
hl.env("SUDO_ASKPASS", os.getenv("HOME") .. "/.local/bin/hypr-askpass")
hl.env("SSH_ASKPASS", os.getenv("HOME") .. "/.local/bin/hypr-askpass")
