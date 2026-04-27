-- Local Unix-domain multiplexer.
-- Gives tmux-server-like persistence: panes survive when the GUI window
-- closes (Cmd+Q / window close), and reopening WezTerm reattaches to the
-- same workspaces. The mux server (`wezterm-mux-server`) is auto-spawned
-- on first connect; you don't need launchd/systemd integration.
local M = {}

function M.apply(config)
  config.unix_domains = {
    {
      name = "unix",
      -- socket_path defaults to ~/.local/share/wezterm/sock/...
      -- Override only if you need cross-host or custom-location sockets.
    },
  }

  -- Auto-attach: every GUI launch becomes `wezterm connect unix`.
  -- Without this you'd start a fresh non-mux session each time, defeating
  -- the persistence guarantee.
  config.default_gui_startup_args = { "connect", "unix" }
end

return M
