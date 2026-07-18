#!/usr/bin/env python3
"""Sync nanokit's portable Codex config and shared agent files into $HOME."""

from __future__ import annotations

import argparse
import difflib
import os
import re
import shutil
import sys
from pathlib import Path

NANOKIT_ROOT = Path(__file__).resolve().parent.parent
CONFIG_SOURCE = NANOKIT_ROOT / "codex" / "config.toml"
INSTRUCTIONS_SOURCE = NANOKIT_ROOT / "claude" / "CLAUDE.md"
SKILLS_SOURCE = NANOKIT_ROOT / "claude" / "skills"
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*=")
SECTION_RE = re.compile(r"^\s*\[")


class SyncConflict(RuntimeError):
    pass


def home_path() -> Path:
    override = os.environ.get("NANOKIT_SYNC_HOME")
    if override:
        return Path(override).expanduser()
    return Path(os.path.expanduser("~"))


def codex_home() -> Path:
    override = os.environ.get("CODEX_HOME")
    return Path(os.path.expanduser(override)) if override else home_path() / ".codex"


def live_config_path() -> Path:
    return codex_home() / "config.toml"


def managed_lines() -> dict[str, str]:
    managed: dict[str, str] = {}
    for raw in CONFIG_SOURCE.read_text().splitlines():
        match = KEY_RE.match(raw)
        if match:
            managed[match.group(1)] = raw
    if not managed:
        raise SyncConflict(f"no top-level keys found in {CONFIG_SOURCE}")
    return managed


def upsert(live_text: str, managed: dict[str, str]) -> str:
    lines = live_text.splitlines()
    section_start = next(
        (index for index, line in enumerate(lines) if SECTION_RE.match(line)), len(lines)
    )
    remaining = dict(managed)
    for index in range(section_start):
        match = KEY_RE.match(lines[index])
        if match and match.group(1) in remaining:
            lines[index] = remaining.pop(match.group(1))

    insert_at = section_start
    while insert_at > 0 and lines[insert_at - 1].strip() == "":
        insert_at -= 1
    for key in managed:
        if key in remaining:
            lines.insert(insert_at, remaining[key])
            insert_at += 1
    return "\n".join(lines) + "\n"


def config_change() -> tuple[Path, str, str]:
    live = live_config_path()
    old_text = live.read_text() if live.exists() else ""
    new_text = upsert(old_text, managed_lines()) if live.exists() else CONFIG_SOURCE.read_text()
    return live, old_text, new_text


def resolved_link(path: Path) -> Path | None:
    if not path.is_symlink():
        return None
    raw = Path(os.readlink(path))
    return (path.parent / raw).resolve() if not raw.is_absolute() else raw.resolve()


def is_previous_nanokit_link(path: Path) -> bool:
    if not path.is_symlink():
        return False
    raw = os.readlink(path).replace("\\", "/")
    return "/nanokit/claude/" in raw or raw.startswith("nanokit/claude/")


def tree_snapshot(root: Path) -> dict[str, tuple[str, bytes | str]]:
    snapshot: dict[str, tuple[str, bytes | str]] = {}
    for path in sorted(root.rglob("*")):
        relative = str(path.relative_to(root))
        if path.is_symlink():
            snapshot[relative] = ("symlink", os.readlink(path))
        elif path.is_file():
            snapshot[relative] = ("file", path.read_bytes())
        elif path.is_dir():
            snapshot[relative] = ("directory", "")
    return snapshot


def plan_link(source: Path, destination: Path, *, replace_empty_file: bool = False) -> str | None:
    if not source.exists():
        raise SyncConflict(f"source does not exist: {source}")
    if destination.is_symlink():
        if resolved_link(destination) == source.resolve():
            return None
        if is_previous_nanokit_link(destination):
            return "relink"
        raise SyncConflict(f"refusing to replace foreign symlink: {destination} -> {os.readlink(destination)}")
    if destination.exists():
        if replace_empty_file and destination.is_file() and destination.stat().st_size == 0:
            return "replace empty file"
        if source.is_dir() and destination.is_dir() and tree_snapshot(source) == tree_snapshot(destination):
            return "replace identical directory"
        if source.is_file() and destination.is_file() and source.read_bytes() == destination.read_bytes():
            return "replace identical file"
        raise SyncConflict(f"refusing to replace non-symlink path: {destination}")
    return "link"


def desired_links() -> list[tuple[Path, Path, bool]]:
    links: list[tuple[Path, Path, bool]] = [
        (INSTRUCTIONS_SOURCE, codex_home() / "AGENTS.md", True),
    ]
    skill_dirs = sorted(
        path for path in SKILLS_SOURCE.iterdir() if path.is_dir() and (path / "SKILL.md").is_file()
    )
    for source in skill_dirs:
        links.append((source, home_path() / ".claude" / "skills" / source.name, False))
        links.append((source, home_path() / ".agents" / "skills" / source.name, False))
    return links


def apply_link(source: Path, destination: Path, action: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if action == "replace identical directory":
        shutil.rmtree(destination)
    elif action in {"relink", "replace empty file", "replace identical file"}:
        destination.unlink()
    destination.symlink_to(source, target_is_directory=source.is_dir())


def print_config_diff(live: Path, old_text: str, new_text: str) -> None:
    diff = "".join(
        difflib.unified_diff(
            old_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=str(live),
            tofile=f"{live} (after sync)",
        )
    )
    if diff:
        print(diff, end="")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--diff", action="store_true", help="preview without writing")
    args = parser.parse_args()

    try:
        live, old_text, new_text = config_change()
        link_actions = [
            (source, destination, action)
            for source, destination, replace_empty in desired_links()
            if (action := plan_link(source, destination, replace_empty_file=replace_empty))
        ]
    except (OSError, SyncConflict) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    config_changed = old_text != new_text
    if args.diff:
        print_config_diff(live, old_text, new_text)
        for source, destination, action in link_actions:
            print(f"{action}: {destination} -> {source}")
        if not config_changed and not link_actions:
            print("All shared agent settings are already in sync.")
        return 0

    if config_changed:
        live.parent.mkdir(parents=True, exist_ok=True)
        live.write_text(new_text)
        print(f"✓ synced portable Codex config: {live}")
    else:
        print(f"✓ portable Codex config already in sync: {live}")

    for source, destination, action in link_actions:
        apply_link(source, destination, action)
        print(f"✓ {action}: {destination} -> {source}")
    if not link_actions:
        print("✓ shared instructions and skills already in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
