#!/usr/bin/env bash
# STATUS (2026-07): 保留中 — 作成・検証済みだが配線が未完了。radar の chat-log 候補源。
#   有効化には (1) .dotter/global.toml で ~/.claude/scripts/ へ symlink し、
#   (2) claude/settings.json の SessionEnd hook に登録する。未配線ゆえ「孤立」に見えるが、
#   claude-settings の radar/inbox_sync.py が本スクリプトの出力 (chat-queue.jsonl) を
#   消費する設計。削除しないこと (2026-07 レビューで削除候補に挙がったが radar が依存)。
#
# SessionEnd hook: SILENT background extraction of PENDING TASKS the user
# committed to / that emerged in the just-ended session, into the task-radar
# chat queue (~/.local/state/task-radar/chat-queue.jsonl).
#
# Sibling of memory-extract.sh: that one condenses PERSONALIZATION, this one
# condenses PENDING TASKS. Both fire on SessionEnd, spawn a DETACHED headless
# claude -p that reads the just-ended transcript out of band, and are invisible
# in the chat (SessionEnd output is ignored by Claude Code — hence full logging).
#
# Why this shape (2026-07-08): the radar must NOT re-scan ~900 raw transcripts.
# Extract pending tasks ONCE per session, at the moment it ends (fresh context,
# one session, cheap) into a queue the radar reads deterministically. This is
# "発見は決定的関数、消費だけ LLM" applied to chat-derived work.
#
# Cost control: a transcript is ~0.4% user text; the rest is tool_result /
# attachments (measured 250x). We STRUCTURALLY STRIP to user text + assistant
# reply text before the LLM sees anything.
#
# Recursion guard: the spawned claude -p fires this hook again -> TASKEX_CHILD=1.
# Also skips inside memory-extract's child (MEMEX_CHILD set).
#
# Observability:
#   fire ledger : ~/.claude/debug/task-extract.log
#   per-run log : ~/.claude/debug/task-extract/<ts>_<sid>.log
#   queue       : ~/.local/state/task-radar/chat-queue.jsonl  (JSONL candidates)
# Manual: bash task-extract.sh --now <transcript.jsonl>   /   --dry-run < payload.json
# Tunables: TASKEX_MODEL (claude-sonnet-5), TASKEX_EFFORT (xhigh),
#           TASKEX_MIN_LINES (20), TASKEX_TIMEOUT_S (600), TASKEX_QUEUE.
set -uo pipefail

DEBUG_DIR="$HOME/.claude/debug"
LEDGER="$DEBUG_DIR/task-extract.log"
RUNDIR="$DEBUG_DIR/task-extract"
MODEL="${TASKEX_MODEL:-claude-sonnet-5}"          # Sonnet で統一 (2026-07-08)
EFFORT="${TASKEX_EFFORT:-xhigh}"
MIN_LINES="${TASKEX_MIN_LINES:-20}"
TIMEOUT_S="${TASKEX_TIMEOUT_S:-600}"
# Queue lives OUTSIDE ~/.claude (writes under ~/.claude are approval-gated and a
# headless background claude -p cannot approve them — same reason memory-extract
# writes to ~/.config).
QUEUE="${TASKEX_QUEUE:-$HOME/.local/state/task-radar/chat-queue.jsonl}"
mkdir -p "$RUNDIR" "$(dirname "$QUEUE")"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
ledger() { printf '[%s] %s\n' "$(ts)" "$1" >> "$LEDGER"; }

# --- recursion guard: never act inside an extractor child session ---
if [ -n "${TASKEX_CHILD:-}" ] || [ -n "${MEMEX_CHILD:-}" ]; then
  ledger "SKIP child session"
  exit 0
fi

mode="hook"
case "${1:-}" in
  --now)     mode="now"; shift ;;
  --dry-run) mode="dry"; shift ;;
esac

# --- resolve transcript_path / session_id / reason (same wiring as memory-extract) ---
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

[ "$reason" = "resume" ] && { ledger "SKIP session=$session reason=resume (transient)"; exit 0; }
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
  ledger "SKIP session=$session reason=$reason (no transcript: ${transcript:-none})"; exit 0
fi
lines="$(wc -l < "$transcript" 2>/dev/null | tr -d ' ')"
if [ "${lines:-0}" -lt "$MIN_LINES" ]; then
  ledger "SKIP session=$session reason=$reason (transcript $lines < $MIN_LINES)"; exit 0
fi

# --- structural strip: [USER] text + [ASSISTANT] text only (drops tool noise, ~250x) ---
stamp="$(date +%Y%m%d_%H%M%S)_${session}"
stripped="$RUNDIR/${stamp}.stripped.txt"
python3 - "$transcript" > "$stripped" 2>/dev/null <<'PYEOF'
import json,sys
def texts(c):
    if isinstance(c,str): return [c]
    if isinstance(c,list): return [x.get("text","") for x in c if isinstance(x,dict) and x.get("type")=="text"]
    return []
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    try: d=json.loads(line)
    except: continue
    t=d.get("type"); msg=d.get("message",{})
    cont=msg.get("content") if isinstance(msg,dict) else None
    if t=="user":
        for tx in texts(cont):
            tx=tx.strip()
            if tx and not tx.startswith("<") and "tool_result" not in tx[:40]:
                print("[USER]", tx[:1200])
    elif t=="assistant":
        for tx in texts(cont):
            tx=tx.strip()
            if tx: print("[ASSISTANT]", tx[:600])
PYEOF
slines="$(wc -l < "$stripped" 2>/dev/null | tr -d ' ')"
runlog="$RUNDIR/${stamp}.log"

PROMPT="$(cat <<EOF
You are a silent task extractor for the task-radar loop. Read the STRIPPED
session log at: $stripped  (only user messages [USER] and assistant replies
[ASSISTANT]; tool noise removed).

Find PENDING tasks the user committed to, was asked to do, or that emerged and
were NOT resolved within this SAME session. Signals: "next let's X", "I'll do
Y", "後で", "次は", "決めた", "TODO", unfinished follow-ups. Do NOT emit anything
that was completed/resolved later in the same session (e.g. it was done / "it
worked" / marked Done). Prefer concrete, verb-ending titles.

Output JSONL ONLY — one candidate per line, no prose, no code fences:
{"kind":"candidate","source":"claude-log","org":"<owning org if inferable, else personal>","type":"約束|停滞|期限|機会","owner":"ai|self|delegate","granularity":"task|micro","title":"<具体的な・動詞で終わるタスク名>","evidence":"<原文からの短い引用>","proposed_action":"<最初の一手>","confidence":0.0-1.0,"session":"$session"}
If there is no pending task, output nothing at all.
EOF
)"

# Run claude -p, keep only JSONL ({-start) lines, APPEND to the queue; full output -> runlog.
run_extract() {
  local out; out="$(TASKEX_CHILD=1 claude -p "$PROMPT" --model "$MODEL" --effort "$EFFORT" \
      --allowedTools "Read" </dev/null 2>>"$runlog")"
  printf '%s\n' "$out" >> "$runlog"
  local n=0
  while IFS= read -r l; do
    case "$l" in \{*) printf '%s\n' "$l" >> "$QUEUE"; n=$((n+1));; esac
  done <<< "$out"
  echo "=== task-extract: appended $n candidate(s) to $QUEUE $(ts) ==="  >> "$runlog"
  ledger "DONE session=$session appended=$n (stripped $slines lines)"
}

case "$mode" in
  dry)
    ledger "DRYRUN session=$session ($lines->$slines lines) model=$MODEL queue=$QUEUE"
    echo "[dry-run] transcript=$transcript ($lines lines) -> stripped $slines lines"
    echo "[dry-run] would spawn Sonnet extractor; JSONL -> $QUEUE"
    ;;
  now)
    ledger "NOW session=$session ($lines->$slines lines) -> $runlog (foreground)"
    echo "=== task-extract start $(ts) session=$session (stripped $slines lines) ===" | tee -a "$runlog"
    run_extract
    tail -3 "$runlog"
    ;;
  hook)
    ledger "FIRED session=$session reason=$reason ($lines->$slines lines) -> $runlog"
    # detached + nohup + watchdog (sleep+kill on pgid), same shape as memory-extract.
    # inner positional args: 1=prompt 2=model 3=effort 4=queue 5=timeout 6=runlog 7=session
    nohup bash -c '
      set -m
      out_tmp="$(mktemp)"
      TASKEX_CHILD=1 claude -p "$1" --model "$2" --effort "$3" --allowedTools "Read" </dev/null >"$out_tmp" 2>>"$6" &
      cpid=$!
      ( sleep "$5" && kill -- -"$cpid" 2>/dev/null && echo "=== task-extract KILLED after ${5}s ===" >>"$6" ) &
      wpid=$!
      wait "$cpid" 2>/dev/null
      kill -- -"$wpid" 2>/dev/null
      n=0
      while IFS= read -r l; do case "$l" in \{*) printf "%s\n" "$l" >> "$4"; n=$((n+1));; esac; done < "$out_tmp"
      cat "$out_tmp" >> "$6"; rm -f "$out_tmp"
      echo "=== task-extract done session=$7 appended=$n $(date "+%F %T") ===" >> "$6"
    ' _ "$PROMPT" "$MODEL" "$EFFORT" "$QUEUE" "$TIMEOUT_S" "$runlog" "$session" >> "$runlog" 2>&1 &
    disown 2>/dev/null || true
    ;;
esac
exit 0
