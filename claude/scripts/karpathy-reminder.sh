#!/usr/bin/env bash
# Inject Karpathy 4-tenet reminder on the first edit of each code file per session.
# Wired as PreToolUse hook (matcher: Edit|Write|MultiEdit|NotebookEdit).
# Stays silent for non-code files and for files already reminded in this session.

set -euo pipefail

payload=$(cat)

# jq absent → no-op (never break the edit flow)
command -v jq >/dev/null 2>&1 || exit 0

file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "nosession"')

[ -z "$file_path" ] && exit 0

ext=$(printf '%s' "${file_path##*.}" | tr '[:upper:]' '[:lower:]')

case "$ext" in
  py|pyi|ipynb|\
ts|tsx|js|jsx|mjs|cjs|\
go|rs|swift|kt|kts|java|scala|sc|\
c|cc|cpp|cxx|h|hh|hpp|hxx|m|mm|\
rb|php|sh|bash|zsh|\
vue|svelte|\
ex|exs|lua|zig|hs|lhs|ml|mli|sql) ;;
  *) exit 0 ;;
esac

state_dir="$HOME/.claude/state/karpathy/$session_id"
mkdir -p "$state_dir"

if command -v sha256sum >/dev/null 2>&1; then
  hash=$(printf '%s' "$file_path" | sha256sum | cut -d' ' -f1)
else
  hash=$(printf '%s' "$file_path" | shasum -a 256 | cut -d' ' -f1)
fi

marker="$state_dir/$hash"
[ -e "$marker" ] && exit 0
touch "$marker"

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Karpathy 4 tenets — (1) Think before coding: state assumptions, ask when unclear. (2) Simplicity first: minimum code, nothing speculative. (3) Surgical changes: touch only what the task requires; do not refactor unrelated code. (4) Goal-driven: define verifiable success criteria up front. Full text: ~/.claude/skills/karpathy-guidelines/SKILL.md"}}
JSON
