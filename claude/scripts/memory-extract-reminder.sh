#!/usr/bin/env bash
# Stop hook: periodically nudge the model to persist durable, cross-project
# user facts/preferences into the GLOBAL personal memory layer
# (~/.claude/memory/personal/), and project-specific facts into this project's
# own memory dir.
#
# Why this exists: native auto-memory (autoMemoryEnabled) captures continuously
# but writes per-project, so cross-project preferences never reach a layer that
# loads everywhere. The global personal layer is @import-ed by the global
# CLAUDE.md, so anything saved there shows up in every project. This nudge is
# what drives durable facts INTO that global layer.
#
# Non-blocking by design: emits additionalContext (rides to the next turn)
# instead of decision:block, so it never delays the current answer or forces a
# mid-turn detour. Rate-limited by a cooldown marker; also bails out when
# stop_hook_active is set (belt-and-suspenders loop guard). To make it more
# forceful, one could switch to {"decision":"block","reason":...} — intentionally
# not done here to preserve conversational flow.
#
# Fail-safe: jq absent → exit 0 (never break the session).

set -euo pipefail

payload=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

# If Claude is already continuing as a result of a stop hook, do nothing.
active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')
[ "$active" = "true" ] && exit 0

cooldown="${MEMORY_EXTRACT_COOLDOWN:-7200}"   # seconds; default 2h
state_dir="$HOME/.claude/state/memory-extract"
mkdir -p "$state_dir"
marker="$state_dir/last_nudge"

mtime_of() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || true
}

if [ -e "$marker" ]; then
  now=$(date +%s)
  mtime=$(mtime_of "$marker")
  if [ -n "$mtime" ] && [ $((now - mtime)) -lt "$cooldown" ]; then
    exit 0
  fi
fi
touch "$marker"

nudge='Before wrapping up: reflect on this session for anything worth REMEMBERING about the user. If the user revealed a durable preference, a personal/background fact, a working style, or a correction to how you should behave, persist it now (skip anything already recorded). Routing: facts that should apply in EVERY project -> write a one-fact file under ~/.claude/memory/personal/ (kebab-case slug, frontmatter name/description/metadata:type, following that directory MEMORY.md conventions) and add a one-line pointer to ~/.claude/memory/personal/MEMORY.md. Project-specific facts -> this project memory dir. Do NOT edit CLAUDE.md automatically (a human promotes those by hand). If nothing new is worth saving, do nothing.'

jq -nc --arg ctx "$nudge" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$ctx}}'
