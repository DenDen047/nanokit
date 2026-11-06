#!/usr/bin/env python3
"""Keep Orca browser tabs in the agent's own workspace.

`orca tab create`, `orca open-url` and `orca goto` without --worktree act on
whichever Orca workspace is selected on screen, not the one the agent runs in.
While he looks at another workspace, the page lands there. The obvious lookups
don't fix it: `orca worktree current` fails in folder workspaces, and one folder
can host several workspaces, so a path doesn't identify one. The session id
does: `orca worktree ps` lists each workspace with its agents.

PreToolUse hook (matcher: Bash). The command is tokenized like a shell would
(quotes, heredoc bodies and operators respected), and each simple command is
checked on its own. `--detect` reuses the same parsing for vision-reminder.sh. A call that opens a page without --worktree (goto: without
--page or --worktree) exits 2, which blocks it and shows stderr to the model
with the exact --worktree to add. Outside an Orca agent session, on unparsable
input, or for --help, it exits 0.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys

LOOKUP_TIMEOUT_S = 4  # well under the hook's 10 s, so a slow Orca still gets blocked, not timed out
LOOKUP_HINT = (
    '"$ORCA_CLI_COMMAND" worktree ps --json | jq -r --arg s "$ORCA_AGENT_SESSION_ID" '
    "'.result.worktrees[] | select(tostring | contains($s)) | .worktreeId'"
)
PREFIX_WORDS = {"if", "then", "else", "elif", "do", "while", "until", "time", "!", "env", "command", "exec", "nohup"}
ORCA_NAMES = {"orca", "orca-dev", "orca-ide"}
ORCA_VARS = {"$ORCA_CLI_COMMAND", "${ORCA_CLI_COMMAND}"}


def strip_heredoc_bodies(cmd: str) -> str:
    """Drop heredoc bodies, whose text is data, not commands."""
    lines = cmd.split("\n")
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for _, word in re.findall(r"(?<!<)<<-?(?!<)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_-]*)\1", line):
            while i < len(lines) and lines[i].strip() != word:
                i += 1
            i += 1  # the terminator line
    return "\n".join(out)


def extract_substitutions(cmd: str) -> tuple[str, list[str]]:
    """Swap each $(...) and `...` outside single quotes for a placeholder word.

    Returns the rewritten command and the inner commands, so a call inside a
    substitution is still checked and a substitution inside a URL argument
    doesn't split the outer command.
    """
    out: list[str] = []
    inner: list[str] = []
    in_single = in_double = False
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if ch == "\\" and not in_single:
            out.append(cmd[i : i + 2])
            i += 2
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif not in_single and cmd.startswith("$(", i) and not cmd.startswith("$((", i):
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(cmd[j], 0)
                j += 1
            inner.append(cmd[i + 2 : j - 1])
            out.append("__SUBST__")
            i = j
            continue
        elif not in_single and ch == "`":
            j = cmd.find("`", i + 1)
            j = n if j == -1 else j
            inner.append(cmd[i + 1 : j])
            out.append("__SUBST__")
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out), inner


def simple_commands(cmd: str) -> list[list[str]]:
    cmd = strip_heredoc_bodies(cmd.replace("\\\n", " "))
    cmd = "\n".join(line for line in cmd.split("\n") if not line.lstrip().startswith("#"))
    cmd, inner = extract_substitutions(cmd)
    lexer = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""  # '#' in a URL is a fragment; whole-line comments were dropped above
    commands: list[list[str]] = []
    current: list[str] = []
    for token in lexer:
        if token and all(c in "();|&" for c in token):
            if current:
                commands.append(current)
            current = []
        else:
            current.append(token)
    if current:
        commands.append(current)
    for sub in inner:
        commands.extend(simple_commands(sub))
    return commands


def has_flag(args: list[str], name: str) -> bool:
    return any(a == name or a.startswith(name + "=") for a in args)


def page_call(tokens: list[str]) -> tuple[str, list[str]] | None:
    """("open" | "goto", args) when this simple command opens or navigates an Orca page."""
    i = 0
    while i < len(tokens) and (tokens[i] in PREFIX_WORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i])):
        i += 1
    if i >= len(tokens):
        return None
    head = tokens[i]
    if os.path.basename(head) not in ORCA_NAMES and head not in ORCA_VARS:
        return None
    rest = tokens[i + 1 :]
    if has_flag(rest, "--help") or "-h" in rest:
        return None
    if rest[:2] == ["tab", "create"] or rest[:1] == ["open-url"]:
        return "open", rest
    if rest[:1] == ["goto"]:
        return "goto", rest
    return None


def violation(tokens: list[str]) -> str | None:
    call = page_call(tokens)
    if not call:
        return None
    kind, args = call
    if kind == "open":
        return None if has_flag(args, "--worktree") else "open"
    return None if has_flag(args, "--page") or has_flag(args, "--worktree") else "goto"


def lookup_workspace(session_id: str) -> str | None:
    orca = os.environ.get("ORCA_CLI_COMMAND") or shutil.which("orca")
    if not orca:
        return None
    try:
        proc = subprocess.run(
            [orca, "worktree", "ps", "--json"], capture_output=True, text=True, timeout=LOOKUP_TIMEOUT_S
        )
        for wt in json.loads(proc.stdout).get("result", {}).get("worktrees", []):
            if session_id in json.dumps(wt):
                return wt.get("worktreeId")
    except (OSError, subprocess.SubprocessError, ValueError, AttributeError):
        return None
    return None


def detect() -> int:
    """--detect: exit 0 when the Bash payload opens or navigates an Orca page (used by vision-reminder.sh)."""
    try:
        cmd = json.load(sys.stdin).get("tool_input", {}).get("command") or ""
        return 0 if any(page_call(c) for c in simple_commands(cmd)) else 1
    except (ValueError, AttributeError):
        return 1


def main() -> int:
    if sys.argv[1:] == ["--detect"]:
        return detect()
    session_id = os.environ.get("ORCA_AGENT_SESSION_ID")
    if not session_id:
        return 0
    try:
        cmd = json.load(sys.stdin).get("tool_input", {}).get("command") or ""
        kinds = {v for c in simple_commands(cmd) if (v := violation(c))}
    except (ValueError, AttributeError):
        return 0
    if not kinds:
        return 0

    wt = lookup_workspace(session_id)
    print(
        "Blocked: without --worktree this opens the page in whichever Orca workspace is selected on screen, not this session's.",
        file=sys.stderr,
    )
    if wt:
        print(f'Re-run it with --worktree "id:{wt}" (this session\'s workspace).', file=sys.stderr)
    else:
        print(f'Re-run it with --worktree "id:<value>", where <value> comes from: {LOOKUP_HINT}', file=sys.stderr)
    if "goto" in kinds:
        print("For goto, prefer --page <browserPageId> from the tab you created.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
