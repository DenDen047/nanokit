#!/usr/bin/env bash
# SessionEnd hook: SILENT background extraction of durable, cross-project user
# facts into the global personal memory layer (~/.config/claude-memory/personal/).
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
#   saved files : ~/.config/claude-memory/personal/*.md  (+ MEMORY.md)
#
# Manual checks:
#   bash memory-extract.sh --now <transcript.jsonl>     # run synchronously, watch it
#   bash memory-extract.sh --dry-run < payload.json     # wiring only, no spawn
#   bash memory-extract.sh --budget                     # index size vs budget, no model
#   bash memory-extract.sh --prune-now                  # foreground prune, ignores the gate
#   bash memory-extract.sh --prune-if-over              # prune only when over budget
#   MEMEX_DEST=/tmp/memtest bash memory-extract.sh --now <t>   # write to a temp dir
#
# Index budget: extraction only ever APPENDS, so MEMORY.md grew unbounded (491
# lines / 126 KB by 2026-08). Extraction is now followed by a deterministic
# budget check and, when it is over, a bounded prune pass. The MAX_/TARGET_
# block below explains why that has to be reimplemented here.
#
# Recursion guard: the spawned `claude -p` is itself a session that fires this
# same hook; it carries MEMEX_CHILD=1 so the hook early-exits for it.
#
# Tunables (env): MEMEX_MODEL (default claude-opus-4-8), MEMEX_EFFORT (default
#                 xhigh), MEMEX_MIN_LINES (default 12), MEMEX_DEST,
#                 MEMEX_TIMEOUT_S (default 900), MEMEX_MAX_LINES (200),
#                 MEMEX_MAX_BYTES (25600), MEMEX_TARGET_LINES (175),
#                 MEMEX_TARGET_BYTES (23000), MEMEX_PRUNE_TIMEOUT_S (900),
#                 MEMEX_PRUNE_WORK.

set -uo pipefail

DEBUG_DIR="$HOME/.claude/debug"
LEDGER="$DEBUG_DIR/memory-extract.log"
RUNDIR="$DEBUG_DIR/memory-extract"
MODEL="${MEMEX_MODEL:-claude-opus-4-8}"
EFFORT="${MEMEX_EFFORT:-xhigh}"
MIN_LINES="${MEMEX_MIN_LINES:-12}"
# Wall-clock kill switch for the detached child. A normal extraction finishes
# in 2-5 min; without this, a wedged `claude -p` (opus + xhigh, nohup'd) has
# NO stop condition at all — no timeout, no turn cap, nothing (2026-07-03
# loop-engineering audit, finding H2). No `timeout` binary on this Mac, so a
# sleep+kill watchdog is used.
TIMEOUT_S="${MEMEX_TIMEOUT_S:-900}"
# NOTE: dest lives OUTSIDE ~/.claude on purpose. Writes under ~/.claude are an
# approval-gated "sensitive file" path, which a headless background claude -p
# cannot satisfy (no interactive approval), so saves were silently blocked.
DEST="${MEMEX_DEST:-$HOME/.config/claude-memory/personal}"
INDEX="$DEST/MEMORY.md"
ARCHIVE="$DEST/ARCHIVE.md"

# --- index budget -------------------------------------------------------------
# Claude Code's NATIVE auto memory loads only the first 200 lines OR 25 KB of
# MEMORY.md, whichever comes first, and after every write measures the file and
# tells the model to shorten the index -- one line per entry, detail into topic
# files, merge or drop stale entries -- erroring once it is over.
# See https://code.claude.com/docs/en/memory ("How it works").
#
# THIS layer is not auto memory: it reaches the session through a CLAUDE.md
# @import, and imports load in full (CLAUDE.md-family files up to 4 MiB), so
# neither the cap nor the self-shortening loop can fire for it. Both are
# reproduced below with upstream's split -- the measurement is deterministic
# shell, the shortening is a bounded `claude -p` pass.
#
# Targets sit under the caps so the next extraction does not immediately re-trip
# the gate. Pointer lines are 138 bytes at the shortest (p50 259), so shortening
# alone cannot reach 25 KB: the prune pass MUST demote entries to ARCHIVE.md,
# which is not imported and is therefore opt-in.
MAX_LINES="${MEMEX_MAX_LINES:-200}"
MAX_BYTES="${MEMEX_MAX_BYTES:-25600}"
TARGET_LINES="${MEMEX_TARGET_LINES:-175}"
TARGET_BYTES="${MEMEX_TARGET_BYTES:-23000}"
PRUNE_TIMEOUT_S="${MEMEX_PRUNE_TIMEOUT_S:-900}"
# Scratch dir for the prune pass. Reordering ~500 index lines by hand is not
# viable, so the pass writes and runs a classifier; with nowhere to put it, it
# drops helper .py files into $DEST, where they read as memories.
PRUNE_WORK="${MEMEX_PRUNE_WORK:-${TMPDIR:-/tmp}/memory-prune-work}"

# Absolute path to this script, so the detached child can re-enter it for the
# prune phase without depending on cwd or on how it was invoked.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

mkdir -p "$RUNDIR" "$DEST"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
ledger() { printf '[%s] %s\n' "$(ts)" "$1" >> "$LEDGER"; }

# --- recursion guard: never act inside the extractor's own child session ---
if [ -n "${MEMEX_CHILD:-}" ]; then
  ledger "SKIP child session (MEMEX_CHILD set)"
  exit 0
fi

# --- index budget: deterministic measurement ---------------------------------
index_lines() { if [ -f "$INDEX" ]; then wc -l < "$INDEX" | tr -d ' '; else echo 0; fi; }
index_bytes() { if [ -f "$INDEX" ]; then wc -c < "$INDEX" | tr -d ' '; else echo 0; fi; }

over_budget() {
  local l b; l="$(index_lines)"; b="$(index_bytes)"
  [ "$l" -gt "$MAX_LINES" ] || [ "$b" -gt "$MAX_BYTES" ]
}

budget_report() {
  local l b st; l="$(index_lines)"; b="$(index_bytes)"
  if over_budget; then st="OVER"; else st="OK"; fi
  printf '%s lines=%s/%s bytes=%s/%s' "$st" "$l" "$MAX_LINES" "$b" "$MAX_BYTES"
}

# --- index budget: model-side shortening -------------------------------------
# Deliberately NON-DESTRUCTIVE. Demotion moves a pointer line to ARCHIVE.md; the
# memory file itself always stays on disk, so nothing is lost and the step is
# reversible by moving the line back. Deleting a memory, and deciding a memory is
# not worth keeping, remain the user's calls.
#
# Built with `read -r -d ''` rather than "$(cat <<EOF ...)": inside a command
# substitution bash keeps matching quotes and parens while it scans for the
# closing paren, and the quotes, parens and apostrophes in this prompt truncated
# it mid-sentence. A heredoc on a simple command is only expanded, never
# tokenised, so the body can contain anything.
IFS='' read -r -d '' PRUNE_PROMPT <<EOF || true
You are maintaining the size of a personal memory INDEX for Claude Code.

  index   : $INDEX      (loaded into EVERY session via a CLAUDE.md @import)
  archive : $ARCHIVE    (NOT imported; read on demand only)
  memories: $DEST/*.md  (one durable fact per file)
  scratch : $PRUNE_WORK (yours; wiped before and after this run)

The index is over budget. Bring $INDEX to at most $TARGET_LINES lines AND at
most $TARGET_BYTES bytes, and report the numbers you end at.

You may ONLY do these three things:
  1. SHORTEN the hook text of a pointer line. Leave the leading marker, the
     bracketed title and the parenthesised slug exactly as they are; compress
     only the prose after the em dash.
  2. MERGE two pointer lines that record the SAME fact. Fold the second file's
     content into the first, keep one pointer line, and delete the redundant
     file only when every claim in it survives in the file you kept.
  3. DEMOTE a pointer line: move it, unchanged apart from allowed shortening,
     from $INDEX to $ARCHIVE. The memory file itself STAYS where it is.

Hard prohibitions:
  - NEVER delete a memory file except as the second half of a merge (rule 2).
  - NEVER drop a pointer line without it landing in $ARCHIVE.
  - NEVER rewrite, soften or reinterpret the BODY of a memory file. The bodies
    are the user's own record; you are maintaining the index, nothing else.
  - NEVER edit any CLAUDE.md.
  - NEVER create anything in $DEST other than MEMORY.md and ARCHIVE.md. Helper
    scripts and intermediate output go in $PRUNE_WORK.

What stays in $INDEX (it is the always-loaded layer, so it holds INSTRUCTIONS):
  - the metadata.type: feedback memories that apply whatever you are working on
    -- standing corrections and directives about how to work. A feedback memory
    that only bites once its own topic comes up (organising one media library,
    laying out one kind of chart, one vendor's quirk) is context-gated and may
    be demoted like any other topic fact.
  - the metadata.type: user memories that change the shape of EVERY answer
    whatever the topic: prose and language rules, how to pace and structure
    output for him, plan and model and concurrency limits, and hard environment
    constraints that would make an answer wrong if ignored -- no local GPU, no
    Windows machine, pixi-only, ls is lsd, clamshell with no Touch ID, limited
    RAM, and the like.

What goes to $ARCHIVE (facts that matter only once their topic comes up):
  - every metadata.type: reference memory
  - the metadata.type: user long tail: travel, tastes and interests, family and
    personal admin, accounts and services, per-client engagement history,
    career and domain background

Demote whole entries before you compress hooks: a pointer line is 138 bytes at
its shortest, so shortening alone cannot reach the byte target.

You have Bash. Editing ~500 index lines one at a time is the wrong tool: write a
script in $PRUNE_WORK, run it, and check the result. Read each memory's own
frontmatter for its metadata.type rather than guessing from the slug.

Keep both files in the existing pointer format, one line per memory. Give
$ARCHIVE a short header saying it is the opt-in overflow of $INDEX and is read
on demand, and group its entries by type. In $INDEX, keep the existing preamble
(shorten it if you like) and put ONE line directly under it pointing at
$ARCHIVE and saying to grep it when a needed fact is not in the index.

Finish with exactly one summary line:
  PRUNED: kept=N demoted=N merged=N lines=N bytes=N
EOF

run_prune() {
  echo "=== memory-prune start $(ts) dest=$DEST ==="
  echo "=== before: $(budget_report) ==="
  rm -rf "$PRUNE_WORK"; mkdir -p "$PRUNE_WORK"
  set -m
  # Bash is required here and not in extraction: this pass has to reorder
  # hundreds of index lines, which is a script's job, not hundreds of Edit calls
  # (the first run wrote a classifier it then could not execute).
  # --strict-mcp-config with no --mcp-config starts ZERO MCP servers; this child
  # only touches files, so booting the MCP stack was pure startup cost.
  MEMEX_CHILD=1 claude -p "$PRUNE_PROMPT" \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --permission-mode acceptEdits \
    --strict-mcp-config \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash" </dev/null &
  local cpid=$!
  ( sleep "$PRUNE_TIMEOUT_S" && kill -- -"$cpid" 2>/dev/null \
      && echo "=== memory-prune KILLED after ${PRUNE_TIMEOUT_S}s timeout $(ts) ===" ) &
  local wpid=$!; disown "$wpid" 2>/dev/null || true
  wait "$cpid" 2>/dev/null; local rc=$?
  kill -- -"$wpid" 2>/dev/null
  rm -rf "$PRUNE_WORK"
  find "$DEST" -maxdepth 1 -name '_*' -type f -delete 2>/dev/null   # safety net
  echo "=== after:  $(budget_report) ==="
  echo "=== memory-prune exit $rc $(ts) ==="
  ledger "PRUNE rc=$rc $(budget_report)"
  return "$rc"
}

mode="hook"
case "${1:-}" in
  --now)           mode="now"; shift ;;
  --dry-run)       mode="dry"; shift ;;
  --budget)        mode="budget"; shift ;;
  --prune-now)     mode="prune-now"; shift ;;
  --prune-if-over) mode="prune-if-over"; shift ;;
esac

# --- budget / prune modes need no transcript: dispatch and exit ---------------
case "$mode" in
  budget)
    echo "index:   $INDEX"
    if [ -f "$ARCHIVE" ]; then
      echo "archive: $ARCHIVE ($(wc -l < "$ARCHIVE" | tr -d ' ') lines)"
    else
      echo "archive: $ARCHIVE (absent)"
    fi
    echo "budget:  $(budget_report) target=${TARGET_LINES}L/${TARGET_BYTES}B"
    if over_budget; then exit 1; else exit 0; fi
    ;;
  prune-now)
    ledger "PRUNE-NOW requested $(budget_report)"
    runlog="$RUNDIR/$(date +%Y%m%d_%H%M%S)_prune.log"
    run_prune 2>&1 | tee "$runlog"
    exit 0
    ;;
  prune-if-over)
    if over_budget; then
      ledger "PRUNE-IF-OVER firing $(budget_report)"
      run_prune 2>&1
    else
      ledger "PRUNE-IF-OVER skip $(budget_report)"
    fi
    exit 0
    ;;
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
You are a silent background memory extractor for Claude Code, building a RICH,
COMPREHENSIVE personalization profile of the user across all projects. Read the
session transcript at: $transcript

From it, capture any DURABLE, cross-project facts that help personalize how the
assistant works WITH and FOR this specific person. Collect BROADLY — not just
work habits. Look for, among others:
  - thinking and reasoning style (how they decompose problems, what they value
    in an answer, what convinces or annoys them)
  - communication and explanation preferences (tone, format, language, depth)
  - hobbies, interests, and side pursuits
  - aesthetic tastes, likes and dislikes
  - values, priorities and principles (what they optimize for; what they reject)
  - domain expertise, background and skills
  - tools, workflow and environment preferences
  - goals, direction and long-term aims (cross-cutting, not one project of tasks)
  - people, collaborators and team structure they work within
  - corrections or guidance on how the assistant should behave

For each genuinely NEW fact (not already in $DEST/MEMORY.md), create a one-fact
file under $DEST/ — kebab-case slug, frontmatter with name, description, and
metadata.type (one of: user, feedback, reference; "user" is broad and covers
identity, interests, tastes, values, and thinking style) — following the
conventions already used in that directory, and add one pointer line to
$DEST/MEMORY.md.

Rules:
  - Read $DEST/MEMORY.md FIRST; skip anything already recorded. If you have a
    real refinement to an existing fact, update that file instead of duplicating.
  - NEVER store secrets or credentials (passwords, API keys, tokens, private
    keys, OTP or 2FA codes). This is the ONE hard exclusion — everything else,
    including sensitive personal topics, is in scope when the user volunteers it.
  - Skip project-specific facts (those belong to per-project memory, not here).
  - Skip pure one-off task trivia; keep only what will still be true and useful
    weeks from now.
  - One clear, specific fact per file; prefer concrete over vague.
  - Do NOT edit any CLAUDE.md.
Finish with one summary line: either "SAVED: <slugs>" or "NOTHING NEW".
EOF
)"

extract() {
  echo "=== memory-extract start $(ts) session=$session reason=$reason dest=$DEST ==="
  echo "=== transcript=$transcript ($lines lines) model=$MODEL timeout=${TIMEOUT_S}s ==="
  # set -m: each background job gets its own process group, so the watchdog
  # can kill claude AND its node children (kill -- -pgid). Killing only the
  # direct child leaves grandchildren holding the stdout pipe.
  set -m
  # --strict-mcp-config with no --mcp-config starts ZERO MCP servers. This child
  # reads a transcript and writes memory files, so every server it used to boot
  # (codex, zotero, scrapling, workspace-*) was startup cost and nothing else.
  MEMEX_CHILD=1 claude -p "$PROMPT" \
    --model "$MODEL" \
    --effort "$EFFORT" \
    --permission-mode acceptEdits \
    --strict-mcp-config \
    --allowedTools "Read,Write,Edit,Glob,Grep" </dev/null &
  local cpid=$!
  ( sleep "$TIMEOUT_S" && kill -- -"$cpid" 2>/dev/null \
      && echo "=== memory-extract KILLED after ${TIMEOUT_S}s timeout $(ts) ===" ) &
  local wpid=$!; disown "$wpid" 2>/dev/null || true
  wait "$cpid" 2>/dev/null; local rc=$?
  kill -- -"$wpid" 2>/dev/null
  echo "=== memory-extract exit $rc $(ts) ==="
}

case "$mode" in
  dry)
    ledger "DRYRUN session=$session reason=$reason ($lines lines) model=$MODEL dest=$DEST -> $runlog"
    echo "[dry-run] transcript=$transcript ($lines lines)"
    echo "[dry-run] would spawn: MEMEX_CHILD=1 claude -p <prompt> --model $MODEL --effort $EFFORT --permission-mode acceptEdits"
    echo "[dry-run] runlog would be: $runlog"
    echo "[dry-run] index budget: $(budget_report) target=${TARGET_LINES}L/${TARGET_BYTES}B"
    ;;
  now)
    ledger "NOW session=$session reason=$reason ($lines lines) -> $runlog (foreground)"
    extract 2>&1 | tee "$runlog"
    if over_budget; then
      run_prune 2>&1 | tee -a "$runlog"
    else
      ledger "BUDGET $(budget_report) (no prune)"
    fi
    ;;
  hook)
    ledger "FIRED session=$session reason=$reason ($lines lines) $(budget_report) -> spawned log=$runlog"
    # detached + nohup so it outlives the hook and the Claude session.
    # Positional args to the inner shell: 1=transcript 2=session 3=reason
    # 4=model 5=prompt 6=effort 7=timeout_s 8=self  (avoids any function/quote
    # serialization). A sleep+kill watchdog bounds the child: without it a
    # wedged claude -p ran forever (audit finding H2).
    # After extraction the child re-enters this script as --prune-if-over. The
    # inner shell is a separate bash -c, so the budget helpers are out of scope
    # and re-exec is the cheapest way to reuse them. That pass is itself gated
    # and bounded, and is a no-op while the index is under budget.
    nohup bash -c '
      echo "=== memory-extract start $(date "+%F %T") session=$2 reason=$3 ==="
      echo "=== transcript=$1 model=$4 effort=$6 timeout=${7}s ==="
      set -m
      MEMEX_CHILD=1 claude -p "$5" --model "$4" --effort "$6" --permission-mode acceptEdits --strict-mcp-config --allowedTools "Read,Write,Edit,Glob,Grep" </dev/null &
      cpid=$!
      ( sleep "$7" && kill -- -"$cpid" 2>/dev/null \
          && echo "=== memory-extract KILLED after ${7}s timeout $(date "+%F %T") ===" ) &
      wpid=$!; disown "$wpid" 2>/dev/null || true
      wait "$cpid" 2>/dev/null; rc=$?
      kill -- -"$wpid" 2>/dev/null
      echo "=== memory-extract exit $rc $(date "+%F %T") ==="
      bash "$8" --prune-if-over
    ' _ "$transcript" "$session" "$reason" "$MODEL" "$PROMPT" "$EFFORT" "$TIMEOUT_S" "$SELF" >> "$runlog" 2>&1 &
    disown 2>/dev/null || true
    ;;
esac
exit 0
