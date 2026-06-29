#!/usr/bin/env bash
# SessionEnd hook: SILENT background extraction of durable, cross-project user
# facts into the global personal memory layer (~/.claude/memory/personal/).
#
# Why this shape: SessionEnd output/exit codes are ignored by Claude Code (no
# additionalContext, no system-reminder), so nothing shows up in the
# conversation. The real work is done by a headless `claude -p` spawned DETACHED,
# which reads the just-ended transcript and writes memory files out of band.
# This replaces the old visible Stop-hook nudge (memory-extract-reminder.sh).
#
# Observability (it is invisible in the chat, so everything is logged):
#   fire ledger : ~/.claude/debug/memory-extract.log         (one line per SessionEnd)
#   per-run log : ~/.claude/debug/memory-extract/<ts>_<sid>.log  (the claude -p output)
#   saved files : ~/.claude/memory/personal/*.md  (+ MEMORY.md)
#
# Manual checks:
#   bash memory-extract.sh --now <transcript.jsonl>     # run synchronously, watch it
#   bash memory-extract.sh --dry-run < payload.json     # wiring only, no spawn
#   MEMEX_DEST=/tmp/memtest bash memory-extract.sh --now <t>   # write to a temp dir
#
# Recursion guard: the spawned `claude -p` is itself a session that fires this
# same hook; it carries MEMEX_CHILD=1 so the hook early-exits for it.
#
# Tunables (env): MEMEX_MODEL (default claude-opus-4-8), MEMEX_EFFORT (default
#                 xhigh), MEMEX_MIN_LINES (default 12), MEMEX_DEST.

set -uo pipefail

DEBUG_DIR="$HOME/.claude/debug"
LEDGER="$DEBUG_DIR/memory-extract.log"
RUNDIR="$DEBUG_DIR/memory-extract"
MODEL="${MEMEX_MODEL:-claude-opus-4-8}"
EFFORT="${MEMEX_EFFORT:-xhigh}"
MIN_LINES="${MEMEX_MIN_LINES:-12}"
DEST="${MEMEX_DEST:-$HOME/.claude/memory/personal}"
mkdir -p "$RUNDIR" "$DEST"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
ledger() { printf '[%s] %s\n' "$(ts)" "$1" >> "$LEDGER"; }

# --- recursion guard: never act inside the extractor's own child session ---
if [ -n "${MEMEX_CHILD:-}" ]; then
  ledger "SKIP child session (MEMEX_CHILD set)"
  exit 0
fi

mode="hook"
case "${1:-}" in
  --now)     mode="now"; shift ;;
  --dry-run) mode="dry"; shift ;;
esac

# --- resolve transcript_path / session_id / reason ---
transcript=""; session=""; reason=""
if [ "$mode" = "now" ] && [ -n "${1:-}" ]; then
  transcript="$1"; session="manual-$(date +%s)"; reason="manual"
else
  payload="$(cat 2>/dev/null || true)"
  if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
    session="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
    reason="$(printf '%s' "$payload" | jq -r '.reason // empty')"
  fi
  [ -z "$transcript" ] && transcript="${1:-}"
fi
session="${session:-unknown}"; reason="${reason:-unknown}"

# A "resume" SessionEnd is transient (the session continues); skip it.
if [ "$reason" = "resume" ]; then
  ledger "SKIP session=$session reason=resume (transient)"
  exit 0
fi

# --- gating: need a real, substantive transcript ---
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  ledger "SKIP session=$session reason=$reason (no transcript: ${transcript:-none})"
  exit 0
fi
lines="$(wc -l < "$transcript" 2>/dev/null | tr -d ' ')"
if [ "${lines:-0}" -lt "$MIN_LINES" ]; then
  ledger "SKIP session=$session reason=$reason (transcript $lines lines < $MIN_LINES)"
  exit 0
fi

runlog="$RUNDIR/$(date +%Y%m%d_%H%M%S)_${session}.log"

PROMPT="$(cat <<EOF
You are a silent background memory extractor for Claude Code. Read the session
transcript at: $transcript

Find any DURABLE, cross-project facts about the user it reveals: lasting
preferences, personal/background facts, working style, or corrections to how the
assistant should behave. For each genuinely NEW one (not already present in
$DEST/MEMORY.md), create a one-fact file under $DEST/ — kebab-case slug,
frontmatter with name, description, and metadata.type (one of user, feedback,
reference) — following the conventions already used in that directory, and add a
one-line pointer to $DEST/MEMORY.md.

Rules: read $DEST/MEMORY.md first and skip anything already recorded; skip
project-specific facts (those belong to per-project memory, not here); skip
trivia and one-off task details; be conservative and save only clearly durable,
broadly useful facts. Do NOT edit any CLAUDE.md. Finish with one summary line:
either "SAVED: <slugs>" or "NOTHING NEW".
EOF
)"

extract() {
  echo "=== memory-extract start $(ts) session=$session reason=$reason dest=$DEST ==="
  echo "=== transcript=$transcript ($lines lines) model=$MODEL ==="
  MEMEX_CHILD=1 claude -p "$PROMPT" \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --permission-mode acceptEdits \
    --allowedTools "Read,Write,Edit,Glob,Grep" </dev/null
  echo "=== memory-extract exit $? $(ts) ==="
}

case "$mode" in
  dry)
    ledger "DRYRUN session=$session reason=$reason ($lines lines) model=$MODEL dest=$DEST -> $runlog"
    echo "[dry-run] transcript=$transcript ($lines lines)"
    echo "[dry-run] would spawn: MEMEX_CHILD=1 claude -p <prompt> --model $MODEL --effort $EFFORT --permission-mode acceptEdits"
    echo "[dry-run] runlog would be: $runlog"
    ;;
  now)
    ledger "NOW session=$session reason=$reason ($lines lines) -> $runlog (foreground)"
    extract 2>&1 | tee "$runlog"
    ;;
  hook)
    ledger "FIRED session=$session reason=$reason ($lines lines) -> spawned log=$runlog"
    # detached + nohup so it outlives the hook and the Claude session.
    # Positional args to the inner shell: 1=transcript 2=session 3=reason
    # 4=model 5=prompt  (avoids any function/quote serialization).
    nohup bash -c '
      echo "=== memory-extract start $(date "+%F %T") session=$2 reason=$3 ==="
      echo "=== transcript=$1 model=$4 effort=$6 ==="
      MEMEX_CHILD=1 claude -p "$5" --model "$4" --effort "$6" --permission-mode acceptEdits --allowedTools "Read,Write,Edit,Glob,Grep" </dev/null
      echo "=== memory-extract exit $? $(date "+%F %T") ==="
    ' _ "$transcript" "$session" "$reason" "$MODEL" "$PROMPT" "$EFFORT" >> "$runlog" 2>&1 &
    disown 2>/dev/null || true
    ;;
esac
exit 0
