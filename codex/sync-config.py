#!/usr/bin/env python3
"""nanokit のポータブル Codex 設定を実ファイル ~/.codex/config.toml へ冪等に反映する。

nanokit が単一ソースとして管理するのは、同ディレクトリの config.toml に書かれた
トップレベルキー (model / model_reasoning_effort / approval_policy 等) だけ。
実ファイルは Codex デスクトップアプリが端末/クライアント固有の状態
([projects.*] の trust_level, [marketplaces.*], node_repl のパス等) を書き戻して
共有するため symlink できず、また nanokit は公開リポジトリなのでそれらを載せられない。

そこで symlink の代わりに、このスクリプトが管理キーだけを実ファイルの
トップレベル領域 (最初の [section] より上) へ upsert する。他のセクション・コメント・
notify 行などには一切触らない。何度実行しても結果が変わらない (冪等)。

  python3 sync-config.py           # 実ファイルへ反映
  python3 sync-config.py --diff    # 変更内容をプレビューするだけ (書き込まない)
"""

from __future__ import annotations

import difflib
import os
import re
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parent / "config.toml"

# トップレベルの `key = value` 行を1行だけ拾う (配列など複数行値は対象外)。
KEY_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*=")
SECTION_RE = re.compile(r"^\s*\[")


def live_path() -> Path:
    codex_home = os.environ.get("CODEX_HOME", "~/.codex")
    return Path(os.path.expanduser(codex_home)) / "config.toml"


def managed_lines() -> dict[str, str]:
    """ソース config.toml のトップレベル `key = value` 行を key→行文字列 で返す。"""
    managed: dict[str, str] = {}
    for raw in SOURCE.read_text().splitlines():
        m = KEY_RE.match(raw)
        if m:
            managed[m.group(1)] = raw.rstrip("\n")
    if not managed:
        sys.exit(f"error: no top-level keys found in {SOURCE}")
    return managed


def upsert(live_text: str, managed: dict[str, str]) -> str:
    lines = live_text.splitlines()

    # トップレベル領域 = 最初のセクションヘッダより前。無ければ全体。
    section_start = next(
        (i for i, ln in enumerate(lines) if SECTION_RE.match(ln)), len(lines)
    )

    remaining = dict(managed)
    for i in range(section_start):
        m = KEY_RE.match(lines[i])
        if m and m.group(1) in remaining:
            lines[i] = remaining.pop(m.group(1))

    if remaining:
        # 未登録キーはトップレベル領域の末尾 (最後の非空行の直後) に挿入する。
        insert_at = section_start
        while insert_at > 0 and lines[insert_at - 1].strip() == "":
            insert_at -= 1
        for key in managed:  # ソースの並び順を保つ
            if key in remaining:
                lines.insert(insert_at, remaining[key])
                insert_at += 1

    return "\n".join(lines) + "\n"


def main() -> int:
    diff_only = "--diff" in sys.argv[1:]
    live = live_path()
    managed = managed_lines()

    if not live.exists():
        new_text = SOURCE.read_text()
        action = f"create {live} from nanokit source"
    else:
        old_text = live.read_text()
        new_text = upsert(old_text, managed)
        action = f"upsert {len(managed)} managed key(s) into {live}"
        if new_text == old_text:
            print(f"✓ {live} already in sync — no change.")
            return 0

    old_text = live.read_text() if live.exists() else ""
    diff = "".join(
        difflib.unified_diff(
            old_text.splitlines(keepends=True),
            new_text.splitlines(keepends=True),
            fromfile=str(live),
            tofile=f"{live} (after sync)",
        )
    )

    if diff_only:
        print(f"# --diff: would {action}\n")
        print(diff or "(no change)")
        return 0

    live.parent.mkdir(parents=True, exist_ok=True)
    live.write_text(new_text)
    print(f"✓ {action}\n")
    print(diff)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
