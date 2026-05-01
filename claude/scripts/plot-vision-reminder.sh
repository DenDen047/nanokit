#!/usr/bin/env bash
# Remind the model to visually verify a plot image it just produced.
# Wired as PostToolUse hook (matcher: Write|Bash).
#
# Coverage:
#   Write — fires when tool_input.file_path matches an image extension
#           (png/jpg/jpeg/gif/webp/svg/pdf). Cooldown: per-path, 10s.
#           SVG/PDF get specialized rasterize-then-Read messages.
#   Bash  — fires when tool_input.command contains a plotting keyword
#           (matplotlib/plotly/seaborn/altair/savefig/plt.show).
#           Cooldown: global, 60s. No specific path injected.
#
# Fail-safe: jq absent → exit 0 (never break the tool flow).

set -euo pipefail

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
[ -z "$tool" ] && exit 0

state_dir="$HOME/.claude/state/plot-vision"
mkdir -p "$state_dir"

mtime_of() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

emit_reminder() {
  jq -nc --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
}

raster_checklist='Read it now and visually verify before declaring the task done. Check: (1) axis labels and tick labels are not cut off at figure edges; (2) legend does not overlap data or other plot elements; (3) tick labels do not collide or overlap each other; (4) data points/lines are not occluded by markers or annotations; (5) colors have sufficient contrast and the aspect ratio matches the intended message. If any check fails, regenerate the plot.'

case "$tool" in
  Write)
    file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
    [ -z "$file_path" ] && exit 0

    ext=$(printf '%s' "${file_path##*.}" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
      png|jpg|jpeg|gif|webp|svg|pdf) ;;
      *) exit 0 ;;
    esac

    if command -v sha256sum >/dev/null 2>&1; then
      hash=$(printf '%s' "$file_path" | sha256sum | cut -d' ' -f1)
    else
      hash=$(printf '%s' "$file_path" | shasum -a 256 | cut -d' ' -f1)
    fi
    marker="$state_dir/write_$hash"
    if [ -e "$marker" ]; then
      now=$(date +%s)
      mtime=$(mtime_of "$marker")
      if [ -n "$mtime" ] && [ $((now - mtime)) -lt 10 ]; then
        exit 0
      fi
    fi
    touch "$marker"

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

    marker="$state_dir/bash_global"
    if [ -e "$marker" ]; then
      now=$(date +%s)
      mtime=$(mtime_of "$marker")
      if [ -n "$mtime" ] && [ $((now - mtime)) -lt 60 ]; then
        exit 0
      fi
    fi
    touch "$marker"

    msg="The Bash command you just ran appears to render a plot. If it produced an image file, Read that file before declaring done. ${raster_checklist}"
    emit_reminder "$msg"
    ;;

  *)
    exit 0
    ;;
esac
