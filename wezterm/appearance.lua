-- Font-only module. Tab labels, status bar, color scheme, and pane dimming
-- are intentionally left at WezTerm built-in defaults — restore them here
-- (or in wezterm.lua) when you decide on a deliberate look.
local wezterm = require("wezterm")

local M = {}

function M.apply(config)
  -- -------------------------------------------------------------------------
  -- Font
  -- -------------------------------------------------------------------------
  -- Mirrors the user's Ghostty config:
  --   ~/Library/Application Support/com.mitchellh.ghostty/config.ghostty
  --     font-family = "Hack Nerd Font"
  --     font-family = "BIZ UDGothic"
  --     font-size   = 14
  -- BIZ UDGothic (Universal Design gothic) keeps kanji+kana widths even,
  -- so box-drawing and aligned columns stay intact when JP text mixes in.
  config.font = wezterm.font_with_fallback({
    "Hack Nerd Font",
    "BIZ UDGothic",
    "Apple Color Emoji",
  })
  config.font_size = 14.0
end

return M
