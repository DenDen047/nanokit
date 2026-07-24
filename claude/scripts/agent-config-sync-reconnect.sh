#!/usr/bin/env bash
# SessionStart self-heal for nanokit's shared agent config.
#
# Why this exists (2026-07 postmortem): distributing nanokit's skills into
# ~/.claude/skills and ~/.agents/skills is done by `agent-config-sync`
# (codex/sync-config.py), which was MANUAL-only. When its Claude-side links
# silently failed, nothing re-ran it, so ~/.claude/skills drifted 40 skills out
# of date for days without anyone noticing. This hook makes the sync idempotently
# self-heal on every SessionStart -- the same resident pattern the MCP launchers
# use -- so the distribution can't silently rot again.
#
# Design: QUIET on success (the user dislikes noisy hooks), LOUD on failure.
# A non-zero sync (some item did not sync) surfaces BOTH to the user
# (`systemMessage`) and to Claude (`additionalContext`), so a broken state is
# impossible to miss. Every run is logged regardless for forensics.
#
#   log : ~/.claude/debug/agent-config-sync-reconnect.log
#   fix : ./nanokit agent-config-sync   (after clearing the reported stale path)

set -uo pipefail

LOG="$HOME/.claude/debug/agent-config-sync-reconnect.log"
mkdir -p "$(dirname "$LOG")"
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Resolve the real nanokit checkout from this script's own (possibly symlinked)
# location: <nanokit>/claude/scripts/agent-config-sync-reconnect.sh
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do src="$(readlink "$src")"; done
NANOKIT_ROOT="$(cd "$(dirname "$src")/../.." >/dev/null 2>&1 && pwd)"
SYNC="$NANOKIT_ROOT/codex/sync-config.py"

if [ ! -f "$SYNC" ] || ! command -v python3 >/dev/null 2>&1; then
  # nanokit or python3 not available here: log and stay silent (don't nag every
  # session on a host that doesn't have this checkout).
  echo "[$(ts)] skip: SYNC=$SYNC python3=$(command -v python3 || echo none)" >>"$LOG"
  exit 0
fi

# Single-flight lock (mkdir is atomic) so parallel Claude sessions don't race on
# the symlinks. Break a stale lock left by a crashed run (>2 min old).
LOCK="$HOME/.claude/state/agent-config-sync.lock"
mkdir -p "$(dirname "$LOCK")"
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
  rmdir "$LOCK" 2>/dev/null || true
fi
if ! mkdir "$LOCK" 2>/dev/null; then
  # Another session is already syncing; it will report any problem.
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

out="$(python3 "$SYNC" 2>&1)"
rc=$?
echo "[$(ts)] rc=$rc :: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)" >>"$LOG"

if [ "$rc" -eq 0 ]; then
  exit 0   # success / already in sync -> quiet
fi

# Something did not sync. Make it impossible to miss: systemMessage -> user,
# additionalContext -> Claude. Emit ONLY JSON on stdout so it parses cleanly.
NANOKIT_ROOT="$NANOKIT_ROOT" SYNC_OUT="$out" SYNC_RC="$rc" python3 <<'PY'
import json, os
out = os.environ.get("SYNC_OUT", "").strip()
rc = os.environ.get("SYNC_RC", "?")
root = os.environ.get("NANOKIT_ROOT", "~/nanokit")
msg = (
    f"agent-config-sync self-heal did not fully sync (exit {rc}). "
    f"Shared skills/config may be out of date.\n{out}\n"
    f"Fix: clear the stale non-symlink path shown above, then run "
    f"`cd {root} && ./nanokit agent-config-sync`."
)
print(json.dumps({
    "systemMessage": "⚠️ " + msg,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "[agent-config-sync] " + msg,
    },
}))
PY
exit 0
