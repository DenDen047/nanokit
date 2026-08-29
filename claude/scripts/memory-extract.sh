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
#   saved files : ~/.config/claude-memory/personal/*.md  (+ a staged pointer line,
#                 merged into PENDING.md by this script after the model exits)
#
# Manual checks:
#   bash memory-extract.sh --now <transcript.jsonl>     # run synchronously, watch it
#   bash memory-extract.sh --dry-run < payload.json     # wiring only, no spawn
#   bash memory-extract.sh --budget                     # index size vs budget, no model
#   bash memory-extract.sh --prune-now                  # foreground prune, ignores the gate
#   bash memory-extract.sh --prune-if-over              # prune only when over budget
#   bash memory-extract.sh --pending                    # numbered review queue (PENDING.md)
#   bash memory-extract.sh --review-apply 1,4|none      # promote those numbers to MEMORY.md, archive the rest
#   bash memory-extract.sh --add-index '- [T](f.md) — h'  # explicit 覚えて: index line under the same lock
#   bash memory-extract.sh --run <t> <session> <reason> # what the detached hook child runs (lock, extract, guard, merge, prune)
#   MEMEX_DEST=/tmp/memtest bash memory-extract.sh --now <t>   # write to a temp dir
#
# Index budget: extraction only ever APPENDS, so MEMORY.md grew unbounded (491
# lines / 126 KB by 2026-08). Extraction is now followed by a deterministic
# budget check and, when it is over, a bounded prune pass. The MAX_/TARGET_
# block below explains why that has to be reimplemented here.
#
# Promotion gate: MEMORY.md is @imported into every session, so nothing the
# extractor writes may land there on its own. The model appends pointer lines
# to a per-run staging file; this script merges them into PENDING.md (not
# loaded); a person moves them out with --review-apply (the /memory-review
# skill drives it). Nothing is promoted by default. Every writer of the three
# curated files (MEMORY.md, ARCHIVE.md, PENDING.md) holds one mkdir lock, and
# each model pass is bracketed by a snapshot: a curated file it was not allowed
# to touch is restored and the incident is logged and notified.
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
PENDING="$DEST/PENDING.md"
STAGING="${MEMEX_STAGING:-$DEST/.staging}"   # per-run extractor output + pre-pass snapshots
LOCK="$DEST/.lock"                            # flock file shared by every writer of the curated files

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

# --- promotion gate: staging -> PENDING.md review queue ----------------------
# The extractor never writes to MEMORY.md, ARCHIVE.md or PENDING.md. It appends
# pointer lines to a per-run staging file; deterministic code merges that into
# the queue, and a person moves queue lines out with --review-apply. Every
# writer of the curated files runs under one mkdir lock, and each model pass is
# bracketed by a snapshot so a curated file it was not allowed to touch is put
# back and reported (silent on success, loud on failure).
PENDING_HEADER='# Pending memory entries (review queue — NOT loaded)

Written by the SessionEnd extractor. Nothing here reaches MEMORY.md until a person
picks it in the weekly review (`/memory-review`, or `--pending` then `--review-apply`).
Same pointer format as MEMORY.md, one line per memory.
'
ensure_pending() {
  [ -f "$PENDING" ] || printf '%s\n' "$PENDING_HEADER" > "$PENDING"
}

# The lock is a kernel flock, not a mkdir directory: a python helper takes
# LOCK_EX on $LOCK and holds it for exactly as long as its stdin (our fd 9)
# stays open. When this shell exits or dies, the kernel drops the lock, so
# there is no stale-lock detection and nothing to reclaim. bash 3.2 has no
# flock(1) and macOS ships none, hence the helper. Children inherit fd 9, so
# a claude -p that outlives a killed shell keeps the lock until it exits.
LOCK_HELPER='
import fcntl, os, sys, time
path, max_wait = sys.argv[1], float(sys.argv[2])
fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
deadline = time.time() + max_wait
while True:
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        break
    except OSError:
        if time.time() >= deadline:
            sys.stdout.write("BUSY\n"); sys.stdout.flush(); sys.exit(1)
        time.sleep(1)
sys.stdout.write("OK\n"); sys.stdout.flush()
sys.stdin.buffer.read()   # blocks until the shell closes fd 9; the kernel then releases the lock
'
LOCK_HELPER_PID=""
lock_acquire() {   # $1 = seconds to wait before giving up
  local max="${1:-30}" fifo out reply polls=0
  mkdir -p "$DEST"
  fifo="$(mktemp -u)" && mkfifo "$fifo" || return 1
  out="$(mktemp)" || { rm -f "$fifo"; return 1; }
  python3 -c "$LOCK_HELPER" "$LOCK" "$max" < "$fifo" > "$out" 2>/dev/null &
  LOCK_HELPER_PID=$!
  exec 9> "$fifo"          # rendezvous: unblocks the helper's open of the read end
  rm -f "$fifo"
  until [ -s "$out" ]; do
    sleep 0.2; polls=$((polls + 1))
    [ "$polls" -gt $(( (max + 5) * 5 )) ] && break
  done
  reply="$(cat "$out" 2>/dev/null)"; rm -f "$out"
  if [ "$reply" != "OK" ]; then
    exec 9>&-; wait "$LOCK_HELPER_PID" 2>/dev/null; LOCK_HELPER_PID=""
    return 1
  fi
  trap 'lock_release' EXIT
  return 0
}
lock_release() {
  exec 9>&- 2>/dev/null
  if [ -n "${LOCK_HELPER_PID:-}" ]; then wait "$LOCK_HELPER_PID" 2>/dev/null; LOCK_HELPER_PID=""; fi
  return 0
}

# Commit the memory repo (when it is one). Gives every model pass a rollback
# point and makes the weekly review readable as git history.
memory_commit() {   # $1 = message
  git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$DEST" add -A >/dev/null 2>&1
  git -C "$DEST" commit -qm "$1" >/dev/null 2>&1 || true
  return 0
}

# Snapshot the curated files before a model pass; put back whichever the pass
# was not allowed to change.
snap_take() {
  SNAP="$STAGING/${session:-manual-$$}.snap"
  rm -rf "$SNAP"; mkdir -p "$SNAP" || return 1
  local f b
  for f in "$INDEX" "$ARCHIVE" "$PENDING"; do
    b="$(basename "$f")"
    if [ -f "$f" ]; then cp "$f" "$SNAP/$b" || return 1; else : > "$SNAP/$b.absent" || return 1; fi
  done
  return 0
}
snap_restore() {   # $@ = curated files the pass just run was not allowed to touch
  # Returns non-zero if any restore failed; the caller then keeps the snapshot.
  local f b changed="" rc=0 tmp
  for f in "$@"; do
    b="$(basename "$f")"
    if [ -f "$SNAP/$b.absent" ]; then
      if [ -e "$f" ]; then
        if rm -f "$f"; then changed="$changed $b(created)"; else rc=1; changed="$changed $b(FAILED)"; fi
      fi
    elif [ -f "$SNAP/$b" ] && ! cmp -s "$f" "$SNAP/$b"; then
      tmp="$DEST/.$b.restore.$$"
      if cp "$SNAP/$b" "$tmp" 2>/dev/null && mv "$tmp" "$f" 2>/dev/null; then changed="$changed $b"
      else rm -f "$tmp"; rc=1; changed="$changed $b(FAILED)"; fi
    fi
  done
  if [ -n "$changed" ]; then
    ledger "WARN session=${session:-manual} restored$changed (a model pass wrote outside the gate)"
    echo "=== WARN restored$changed: a model pass wrote to a curated file; that edit was discarded ==="
    osascript -e "display notification \"restored$changed, see ~/.claude/debug/memory-extract.log\" with title \"memory-extract gate\"" 2>/dev/null || true
  fi
  return "$rc"
}
snap_drop() { [ -n "${SNAP:-}" ] && rm -rf "$SNAP"; return 0; }

# Move every staged pointer line into the queue, skipping exact lines already
# in the queue, the index or the archive. All staging files are merged, so one
# left behind by a killed run is picked up by the next. Caller holds the lock.
merge_staging() {
  local sf work n=0 line ok present f
  ensure_pending
  for sf in "$STAGING"/*.md; do
    [ -f "$sf" ] || continue
    # Work from a copy: if the staging file cannot be read in full it is kept
    # untouched, and the original is deleted only after every line went in.
    work="$sf.work"
    if ! cp "$sf" "$work" 2>/dev/null; then
      rm -f "$work"
      ledger "ERROR session=${session:-manual} cannot read staging $sf; kept"
      echo "=== ERROR could not read staging file $sf; kept ==="
      return 1
    fi
    ok=1
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in "- ["*)
        # Only files that exist are consulted; a grep read error counts as
        # "not present" so the worst case is a duplicate, never a lost line.
        present=0
        for f in "$PENDING" "$INDEX" "$ARCHIVE"; do
          if [ -f "$f" ] && grep -qxF -- "$line" "$f" 2>/dev/null; then present=1; break; fi
        done
        if [ "$present" -eq 0 ]; then
          printf '%s\n' "$line" >> "$PENDING" || { ok=0; break; }
          n=$((n + 1))
        fi ;;
      esac
    done < "$work" || ok=0
    if [ "$ok" -eq 1 ]; then
      rm -f "$sf" "$work"
    else
      rm -f "$work"
      ledger "ERROR session=${session:-manual} append to PENDING.md failed; staging kept: $sf"
      echo "=== ERROR could not append to PENDING.md; staging kept at $sf ==="
      return 1
    fi
  done
  ledger "MERGED session=${session:-manual} queued=$n"
  echo "=== merged $n line(s) into PENDING.md ==="
}

# The extractor is told to stage, never to touch the queue. If it appended to
# PENDING.md anyway, keep those lines by staging them before the restore.
salvage_queue_writes() {
  # Returns non-zero on a read or write error; the caller then keeps the snapshot.
  [ -f "$PENDING" ] && [ -f "$SNAP/PENDING.md" ] || return 0
  local tmp rc
  tmp="$(mktemp)" || return 1
  grep -vxF -f "$SNAP/PENDING.md" "$PENDING" > "$tmp" 2>/dev/null; rc=$?
  if [ "$rc" -ge 2 ]; then rm -f "$tmp"; return 1; fi
  grep -q '^- \[' "$tmp" 2>/dev/null; rc=$?
  if [ "$rc" -ge 2 ]; then rm -f "$tmp"; return 1; fi
  if [ "$rc" -eq 0 ]; then
    grep '^- \[' "$tmp" >> "$STAGE_FILE" || { rm -f "$tmp"; return 1; }
  fi
  rm -f "$tmp"
  return 0
}

# Explicit "remember this" from a session: the memory file is written by the
# agent, the index line goes through here so it takes the same lock as every
# other writer instead of editing MEMORY.md underneath a running extraction.
add_index() {
  local line="${1:-}" slug
  case "$line" in "- ["*) ;; *) echo "usage: --add-index '- [Title](file.md) — hook'" >&2; return 2 ;; esac
  slug="$(printf '%s' "$line" | sed -n 's/.*](\([^)]*\.md\)).*/\1/p')"
  if [ -z "$slug" ] || [ ! -f "$DEST/$slug" ]; then
    echo "memory file not found under $DEST: ${slug:-?} (write the memory file first)" >&2; return 1
  fi
  lock_acquire 30 || { echo "memory files are locked (an extraction or prune is running); retry in a minute" >&2; return 3; }
  if [ -f "$INDEX" ] && grep -qxF -- "$line" "$INDEX"; then
    echo "already in index"; lock_release; return 0
  fi
  printf '%s\n' "$line" >> "$INDEX" || { lock_release; return 1; }
  memory_commit "add-index $(date +%F): $slug"
  ledger "ADD-INDEX $slug $(budget_report)"
  echo "added to index: $line"
  lock_release
}

# The prune pass may rewrite MEMORY.md and ARCHIVE.md but never the queue.
prune_guarded() {
  local rc
  snap_take || { ledger "ERROR snapshot failed before prune; prune skipped"; echo "=== ERROR snapshot failed; prune skipped ==="; return 1; }
  memory_commit "pre-prune $(date '+%F %T')"
  run_prune; rc=$?
  if [ "$rc" -ne 0 ]; then
    # A prune that was killed or failed may have moved half the lines and
    # merged or deleted memory files. Put everything back: the three curated
    # files from the snapshot, every tracked file from the commit just made.
    snap_restore "$INDEX" "$ARCHIVE" "$PENDING" || true
    git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git -C "$DEST" checkout -q -- . 2>/dev/null
    ledger "ERROR session=${session:-manual} prune rc=$rc; rolled back, snapshot kept at $SNAP"
    echo "=== ERROR prune rc=$rc; rolled back to the pre-prune state, snapshot kept at $SNAP ==="
    osascript -e "display notification \"prune failed and was rolled back\" with title \"memory-extract gate\"" 2>/dev/null || true
    return "$rc"
  fi
  if snap_restore "$PENDING"; then
    snap_drop
  else
    ledger "ERROR session=${session:-manual} restore after prune failed; snapshot kept at $SNAP"
    echo "=== ERROR restore after prune failed; snapshot kept at $SNAP ==="
    osascript -e "display notification \"restore failed, snapshot kept\" with title \"memory-extract gate\"" 2>/dev/null || true
    return 1
  fi
  return 0
}

pending_list() {
  ensure_pending
  local n=0 line
  while IFS= read -r line; do
    case "$line" in "- ["*) n=$((n+1)); printf '%3d  %s\n' "$n" "$line" ;; esac
  done < "$PENDING"
  [ "$n" -eq 0 ] && echo "(empty)"
  return 0
}

review_apply() {
  # $1 = comma-separated numbers as printed by --pending, or "none".
  # Kept lines are appended to MEMORY.md; the rest go to ARCHIVE.md under the
  # "## <metadata.type>" heading of the memory they point at. Each file is
  # written whole to a temp file and renamed into place, destinations skip
  # lines they already hold, and the queue is written last, so a run cut short
  # can simply be repeated. The python runs as a simple command with its own
  # stdout file, not inside $(...): see the PRUNE_PROMPT note on heredocs.
  local keep="${1:-}" out summary rc
  if [ -z "$keep" ]; then echo "usage: --review-apply <n,n,...|none>" >&2; return 2; fi
  if ! lock_acquire 30; then
    echo "memory files are locked (an extraction or prune is running); retry in a minute" >&2
    return 3
  fi
  ensure_pending
  out="$(mktemp)"
  python3 - "$DEST" "$keep" > "$out" 2>&1 <<'PY'
import os, re, sys, pathlib, tempfile
dest, keep = pathlib.Path(sys.argv[1]), sys.argv[2].strip()
pend, idx, arc = dest/'PENDING.md', dest/'MEMORY.md', dest/'ARCHIVE.md'
def read_lines(p, default):
    return p.read_text().splitlines() if p.exists() else list(default)
def write_atomic(p, lines):
    fd, tmp = tempfile.mkstemp(dir=str(dest), prefix='.' + p.name + '.')
    with os.fdopen(fd, 'w') as f:
        f.write('\n'.join(lines).rstrip('\n') + '\n')
    os.replace(tmp, p)
lines = read_lines(pend, [])
entries = [l for l in lines if l.startswith('- [')]
header = [l for l in lines if not l.startswith('- [')]
if keep.lower() == 'none':
    keep_ids = set()
else:
    try:
        keep_ids = {int(x) for x in keep.split(',') if x.strip()}
    except ValueError:
        sys.exit(f"bad number list: {keep!r}")
bad = sorted(k for k in keep_ids if k < 1 or k > len(entries))
if bad:
    sys.exit(f"no such pending entry: {bad} (queue has {len(entries)})")
kept = [e for i, e in enumerate(entries, 1) if i in keep_ids]
rest = [e for i, e in enumerate(entries, 1) if i not in keep_ids]
def mtype(line):
    m = re.search(r'\]\(([^)]+\.md)\)', line)
    f = dest / m.group(1) if m else None
    if f and f.exists():
        mm = re.search(r'^\s*type:\s*(\w+)', f.read_text(), re.M)
        if mm:
            return mm.group(1)
    return 'user'
idx_lines = read_lines(idx, [])
new_idx = [e for e in kept if e not in idx_lines]
if new_idx:
    write_atomic(idx, idx_lines + new_idx)
arc_lines = read_lines(arc, ['# Personal memory archive (opt-in overflow of MEMORY.md — NOT auto-loaded)'])
new_arc = [e for e in rest if e not in arc_lines]
if new_arc:
    a = list(arc_lines)
    for line in new_arc:
        typ = mtype(line)
        hi = next((i for i, l in enumerate(a) if l.startswith('## ' + typ)), None)
        if hi is None:
            a += ['', f'## {typ}', line]
            continue
        end = next((i for i in range(hi + 1, len(a)) if a[i].startswith('## ')), len(a))
        ins = end
        while ins > hi + 1 and a[ins - 1].strip() == '':
            ins -= 1
        a.insert(ins, line)
    write_atomic(arc, a)
write_atomic(pend, header)
print(f"REVIEWED: kept={len(kept)} archived={len(rest)}")
PY
  rc=$?
  summary="$(cat "$out")"; rm -f "$out"
  if [ "$rc" -ne 0 ]; then echo "$summary" >&2; lock_release; return "$rc"; fi
  echo "$summary"
  memory_commit "review $(date +%F): $summary"
  ledger "REVIEW $summary $(budget_report)"
  echo "budget:  $(budget_report)"
  lock_release
}

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
  pending : $PENDING    (review queue; not yours to touch)
  staging : $STAGING    (this script owns it; not yours to touch)
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
  - NEVER create anything in $DEST other than MEMORY.md and ARCHIVE.md, and
    NEVER touch PENDING.md. Helper scripts and intermediate output go in
    $PRUNE_WORK.

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
  --pending)       mode="pending"; shift ;;
  --review-apply)  mode="review-apply"; shift ;;
  --run)           mode="run"; shift ;;
  --add-index)     mode="add-index"; shift ;;
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
    lock_acquire 60 || { echo "memory files are locked; retry later" >&2; exit 3; }
    ensure_pending
    ledger "PRUNE-NOW requested $(budget_report)"
    runlog="$RUNDIR/$(date +%Y%m%d_%H%M%S)_prune.log"
    prune_guarded 2>&1 | tee "$runlog"
    lock_release
    exit 0
    ;;
  pending)
    pending_list
    exit 0
    ;;
  review-apply)
    review_apply "${1:-}"
    exit $?
    ;;
  add-index)
    add_index "${1:-}"
    exit $?
    ;;
  prune-if-over)
    lock_acquire 60 || { ledger "PRUNE-IF-OVER skip (lock busy)"; exit 0; }
    ensure_pending
    if over_budget; then
      ledger "PRUNE-IF-OVER firing $(budget_report)"
      prune_guarded 2>&1
    else
      ledger "PRUNE-IF-OVER skip $(budget_report)"
    fi
    lock_release
    exit 0
    ;;
esac

# --- resolve transcript_path / session_id / reason ---
transcript=""; session=""; reason=""
if { [ "$mode" = "now" ] || [ "$mode" = "run" ]; } && [ -n "${1:-}" ]; then
  transcript="$1"; session="${2:-manual-$(date +%s)}"; reason="${3:-manual}"
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
STAGE_FILE="$STAGING/$session.md"   # where the extractor leaves its pointer lines

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

For each genuinely NEW fact (not already recorded anywhere in $DEST), create a
one-fact file under $DEST/ — kebab-case slug, frontmatter with name,
description, and metadata.type (one of: user, feedback, reference; "user" is
broad and covers identity, interests, tastes, values, and thinking style) —
following the conventions already used in that directory, and append one
pointer line of the form "- [Title](file.md) — hook" to $STAGE_FILE (create it
if absent). That file is merged into the review queue by the caller. NEVER
write to $DEST/MEMORY.md, $DEST/ARCHIVE.md or $DEST/PENDING.md: the index is
curated by a person, and entries reach it only through the weekly review.

Rules:
  - Read $DEST/MEMORY.md and $DEST/PENDING.md FIRST, and grep $DEST/ARCHIVE.md
    and the file names in $DEST/ for each candidate topic (the archive is large;
    do not read it whole). Skip anything already recorded in any of them. If
    you have a real refinement to an existing fact, update that file instead
    of duplicating, and leave its existing pointer line where it is.
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

run_pipeline() {
  # One lock for the whole run: the extractor's minutes-long pass, the merge
  # and the prune. A review arriving meanwhile waits or is told to retry, and
  # a second SessionEnd run waits here before it spawns anything.
  if ! lock_acquire 1800; then
    ledger "SKIP session=$session (memory lock busy for 30 min)"
    echo "=== memory lock busy for 30 min, giving up ==="
    return 1
  fi
  ensure_pending
  mkdir -p "$STAGING"
  if ! snap_take; then
    ledger "ERROR session=$session snapshot failed; extraction skipped"
    echo "=== ERROR snapshot failed; extraction skipped ==="
    lock_release; return 1
  fi
  extract
  local s_rc r_rc
  salvage_queue_writes; s_rc=$?
  # Keep the queue as the model left it inside the snapshot, so a failed
  # salvage can be recovered by hand; if even that copy fails, leave the
  # queue alone rather than restore over the only copy.
  if [ -f "$PENDING" ] && cp "$PENDING" "$SNAP/PENDING.post.md" 2>/dev/null; then
    snap_restore "$INDEX" "$ARCHIVE" "$PENDING"; r_rc=$?
  else
    snap_restore "$INDEX" "$ARCHIVE"; r_rc=$?
    [ -f "$PENDING" ] && r_rc=1
  fi
  if [ "$s_rc" -ne 0 ] || [ "$r_rc" -ne 0 ]; then
    ledger "ERROR session=$session salvage=$s_rc restore=$r_rc; snapshot kept at $SNAP"
    echo "=== ERROR salvage=$s_rc restore=$r_rc; snapshot kept at $SNAP ==="
    osascript -e "display notification \"salvage or restore failed, snapshot kept\" with title \"memory-extract gate\"" 2>/dev/null || true
    lock_release; return 1
  fi
  if ! merge_staging; then snap_drop; lock_release; return 1; fi
  snap_drop
  memory_commit "extract $(date '+%F %T') session=$session"
  if over_budget; then
    ledger "BUDGET $(budget_report) -> prune"
    prune_guarded
  else
    ledger "BUDGET $(budget_report) (no prune)"
  fi
  lock_release
}

case "$mode" in
  dry)
    ledger "DRYRUN session=$session reason=$reason ($lines lines) model=$MODEL dest=$DEST -> $runlog"
    echo "[dry-run] transcript=$transcript ($lines lines)"
    echo "[dry-run] would spawn: MEMEX_CHILD=1 claude -p <prompt> --model $MODEL --effort $EFFORT --permission-mode acceptEdits"
    echo "[dry-run] runlog would be: $runlog"
    echo "[dry-run] staging file: $STAGE_FILE"
    echo "[dry-run] index budget: $(budget_report) target=${TARGET_LINES}L/${TARGET_BYTES}B"
    ;;
  now)
    ledger "NOW session=$session reason=$reason ($lines lines) -> $runlog (foreground)"
    run_pipeline 2>&1 | tee "$runlog"
    ;;
  run)
    # The detached hook child; stdout and stderr already go to the run log.
    run_pipeline
    ;;
  hook)
    ledger "FIRED session=$session reason=$reason ($lines lines) $(budget_report) -> spawned log=$runlog"
    # detached + nohup so it outlives the hook and the Claude session. The
    # child re-enters this script as --run so the lock, snapshot, merge and
    # prune helpers are in scope; extract() bounds claude -p with a sleep+kill
    # watchdog (without it a wedged claude -p ran forever, audit finding H2).
    nohup bash "$SELF" --run "$transcript" "$session" "$reason" >> "$runlog" 2>&1 &
    disown 2>/dev/null || true
    ;;
esac
exit 0
