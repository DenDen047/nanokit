#!/usr/bin/env bash
# Remind the model to VISUALLY verify what it just produced.
# Generalized from plot-vision-reminder.sh to cover three surfaces:
#   (a) plot / image writes        — rasterize-then-Read self-check
#   (b) frontend / UI file edits   — render-screenshot-then-Read self-check
#   (c) browser navigation         — screenshot-then-Read self-check
# Wired as PostToolUse hook (matchers: Write|Edit|MultiEdit|Bash and
# mcp__claude-in-chrome__navigate). See nanokit/claude/settings.json.
#
# Coverage & cooldowns:
#   Write (image ext png/jpg/jpeg/gif/webp/svg/pdf)   — per-path, 10s
#   Write|Edit|MultiEdit (frontend ext)               — global,   20s
#   Bash (plotting interpreter + plotting keyword)     — global,   60s
#   mcp__claude-in-chrome__navigate                    — global,   45s
#
# Fail-safe: jq absent → exit 0 (never break the tool flow).

set -euo pipefail

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
[ -z "$tool" ] && exit 0

state_dir="$HOME/.claude/state/vision-reminder"
mkdir -p "$state_dir"

mtime_of() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

emit_reminder() {
  # Ledger of every fire, so "the hook nudged" can be separated from "the model
  # actually screenshotted + Read". Append-only; grows only when the hook fires.
  mkdir -p "$HOME/.claude/debug"
  printf '[%s] FIRED tool=%s :: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$tool" "$(printf '%.110s' "$1")" \
    >> "$HOME/.claude/debug/vision-reminder.log"
  jq -nc --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
}

# cooldown_ok <marker> <window_seconds> -> 0 if allowed (and stamps marker),
# 1 if still within the cooldown window.
cooldown_ok() {
  local marker="$1" window="$2" now mtime
  if [ -e "$marker" ]; then
    now=$(date +%s)
    mtime=$(mtime_of "$marker")
    if [ -n "$mtime" ] && [ $((now - mtime)) -lt "$window" ]; then
      return 1
    fi
  fi
  touch "$marker"
  return 0
}

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

is_frontend_ext() {
  case "$1" in
    html|htm|css|scss|sass|less|jsx|tsx|vue|svelte|astro) return 0 ;;
    *) return 1 ;;
  esac
}

is_image_ext() {
  case "$1" in
    png|jpg|jpeg|gif|webp|svg|pdf) return 0 ;;
    *) return 1 ;;
  esac
}

raster_checklist='Read it now and visually verify before declaring the task done. Check: (1) axis labels and tick labels are not cut off at figure edges; (2) legend does not overlap data or other plot elements; (3) tick labels do not collide or overlap each other; (4) data points/lines are not occluded by markers or annotations; (5) colors have sufficient contrast and the aspect ratio matches the intended message. If any check fails, regenerate the plot.'

ui_checklist='Render the result (dev server / headless browser / open the file) and take a screenshot, then Read the PNG before declaring the task done. Check: (1) layout is not broken and nothing overflows or is clipped at the viewport edges; (2) elements do not overlap unintentionally; (3) text has sufficient contrast and is legible; (4) spacing and alignment match the intent; (5) it holds at the target viewport widths (and in dark mode if relevant). If any check fails, fix and re-verify.'

case "$tool" in
  Write|Edit|MultiEdit)
    file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
    [ -z "$file_path" ] && exit 0

    ext=$(printf '%s' "${file_path##*.}" | tr '[:upper:]' '[:lower:]')

    # Image writes (only Write actually emits image bytes; Edit/MultiEdit are text).
    if [ "$tool" = "Write" ] && is_image_ext "$ext"; then
      marker="$state_dir/img_$(hash_of "$file_path")"
      cooldown_ok "$marker" 10 || exit 0
      case "$ext" in
        svg)
          msg="You just wrote an SVG at ${file_path}. Vision input cannot read SVG directly — rasterize it (e.g. \`rsvg-convert\` or a headless browser screenshot to PNG) and Read the PNG to verify. ${raster_checklist}"
          ;;
        pdf)
          msg="You just wrote a PDF at ${file_path}. Vision input cannot read PDF reliably via Read — convert page 1 to PNG (e.g. \`pdftoppm -png -r 150 ${file_path} /tmp/plot_check\`) and Read the PNG. ${raster_checklist}"
          ;;
        *)
          msg="You just wrote an image at ${file_path}. ${raster_checklist}"
          ;;
      esac
      emit_reminder "$msg"
      exit 0
    fi

    # Frontend / UI source edits — nudge a render + screenshot self-check.
    if is_frontend_ext "$ext"; then
      cooldown_ok "$state_dir/frontend_global" 20 || exit 0
      msg="You just modified a UI/frontend file (${file_path}). ${ui_checklist}"
      emit_reminder "$msg"
      exit 0
    fi

    exit 0
    ;;

  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
    [ -z "$cmd" ] && exit 0

    # Allow-list interpreters that can actually render plots. Without this
    # gate, `git commit -m "...matplotlib..."` or `echo "savefig"` fire the
    # hook because plot keywords appear anywhere in the command string.
    first_word=$(printf '%s' "$cmd" | awk '{print $1}' | sed 's|.*/||')
    case "$first_word" in
      python|python3|jupyter|ipython|uv|poetry|pixi|pdm|pipenv) ;;
      *) exit 0 ;;
    esac

    if ! printf '%s' "$cmd" | grep -Eqi '(savefig|matplotlib|plotly|seaborn|altair|plt\.show)'; then
      exit 0
    fi

    cooldown_ok "$state_dir/bash_global" 60 || exit 0
    msg="The Bash command you just ran appears to render a plot. If it produced an image file, Read that file before declaring done. ${raster_checklist}"
    emit_reminder "$msg"
    ;;

  mcp__claude-in-chrome__navigate)
    cooldown_ok "$state_dir/browser_global" 45 || exit 0
    msg="You just navigated the browser. If the task is about how a page looks or behaves, take a screenshot now and Read it to visually verify the result before declaring done. ${ui_checklist}"
    emit_reminder "$msg"
    ;;

  *)
    exit 0
    ;;
esac
