-- Hyprland >= 0.56 Lua config.
-- hypr-uac is a real toplevel, not a layer surface, so it needs floating
-- explicitly. Pinned so it is answerable from whichever workspace you are on,
-- and dimmed so it is obvious what has the focus.
local uac = "^(hypr-uac)$"
hl.window_rule({ match = { class = uac }, float = true })
hl.window_rule({ match = { class = uac }, center = true })
hl.window_rule({ match = { class = uac }, pin = true })
hl.window_rule({ match = { class = uac }, dim_around = true })
-- Optional hard modal. Left off by default so you can click away to check
-- what a command does before answering:
-- hl.window_rule({ match = { class = uac }, stay_focused = true })
