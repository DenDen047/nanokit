-- WezTerm entry point. nanokit/wezterm/wezterm.lua → ~/.config/wezterm/wezterm.lua
-- Module split: keybinds.lua / appearance.lua
--
-- Visual aspects (window decoration, tab bar position, color scheme,
-- status bar) are intentionally left at WezTerm defaults. Add them back
-- here or in appearance.lua only when you decide on a deliberate look.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- ---------------------------------------------------------------------------
-- Shell & terminfo (functional, not visual)
-- ---------------------------------------------------------------------------
-- Use the pixi-managed zsh as a login shell so .zprofile / .zshenv chain runs.
config.default_prog = { os.getenv("HOME") .. "/.pixi/envs/zsh/bin/zsh", "-l" }

-- WezTerm's own terminfo. Inside SSH sessions WezTerm auto-falls-back to
-- xterm-256color if the remote host lacks the wezterm terminfo.
config.term = "wezterm"

-- ---------------------------------------------------------------------------
-- Tab bar visibility
-- ---------------------------------------------------------------------------
-- Both fields match WezTerm's documented defaults; we set them explicitly
-- so the tab bar stays visible even with a single tab and survives any
-- future default changes.
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

-- ---------------------------------------------------------------------------
-- Compose modules
-- ---------------------------------------------------------------------------
require("appearance").apply(config)
require("keybinds").apply(config)
require("domains").apply(config)

return config
