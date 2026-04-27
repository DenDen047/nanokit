-- Keybindings. Mirror of tmux.conf, ported to WezTerm's leader-key model.
-- The original tmux.conf left `prefix` at its default (C-b) and only added
-- `bind C-a send-prefix`, so we use C-b here to match tmux's actual prefix.
--
-- Mapping table:
--   tmux                          → WezTerm
--   prefix = C-b (tmux default)   → LEADER = CTRL+b (1s timeout)
--   prefix |  (split horizontal)  → LEADER |
--   prefix -  (split vertical)    → LEADER -
--   prefix h/j/k/l (move pane)    → LEADER h/j/k/l
--   prefix c  (new window)        → LEADER c          (= new tab)
--   prefix r  (reload)            → LEADER r          (= ReloadConfiguration)
--   prefix C-b (send literal C-b) → LEADER CTRL+b
--   copy-mode (vi)                → CopyMode key table (built-in, vi-style)
--   v in copy-mode (begin sel)    → already vi-default in WezTerm CopyMode
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

function M.apply(config)
  -- -------------------------------------------------------------------------
  -- Leader: CTRL+b (matches tmux's default prefix), 1-second chord window
  -- -------------------------------------------------------------------------
  config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }

  -- -------------------------------------------------------------------------
  -- Mouse / clipboard / scrollback (tmux: setw -g mouse on, set-clipboard on)
  -- -------------------------------------------------------------------------
  config.scrollback_lines = 50000
  config.enable_scroll_bar = false
  -- WezTerm enables OSC 52 by default; tmux's `set-clipboard on` equivalent
  -- is automatic. Mouse selection auto-copies to clipboard:
  config.selection_word_boundary = " \t\n{}[]()\"'`,;:|"

  -- -------------------------------------------------------------------------
  -- Key table: 'leader' actions (the part right after pressing CTRL+a)
  -- -------------------------------------------------------------------------
  config.keys = {
    -- Pane splits, opening in the same cwd as the current pane
    -- '|' is already the shifted form on US layouts, so we don't add SHIFT here.
    -- Recent WezTerm normalizes keys to their character form for symbol keys.
    { key = "|", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

    -- Vim-style pane navigation
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },

    -- New tab in current pane's cwd (tmux: bind c new-window -c '#{pane_current_path}')
    { key = "c", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },

    -- Reload config (tmux: bind r source-file ~/.tmux.conf)
    -- WezTerm auto-reloads on save, but keep the manual binding for parity.
    { key = "r", mods = "LEADER", action = act.ReloadConfiguration },

    -- Send a literal Ctrl+b: pressing the leader twice forwards C-b to the shell
    -- (mirrors tmux's default `bind C-b send-prefix`).
    { key = "b", mods = "LEADER|CTRL", action = act.SendKey({ key = "b", mods = "CTRL" }) },

    -- Enter copy mode (vi-keys), equivalent to tmux's [ / Enter
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },

    -- Quick window-list-like picker (tmux: prefix w)
    { key = "w", mods = "LEADER", action = act.ShowTabNavigator },

    -- Pane zoom toggle (tmux: prefix z)
    { key = "z", mods = "LEADER", action = act.TogglePaneZoomState },

    -- ---------------------------------------------------------------------
    -- macOS conveniences (no LEADER)
    -- ---------------------------------------------------------------------
    -- Cmd+K clears scrollback like Terminal.app
    { key = "k", mods = "CMD", action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),  -- redraw shell prompt
    }) },
  }
end

return M
