#!/usr/bin/env python3
"""prose-lint: 文章成果物の「機械で拾える」AI 文体と置き忘れを検出する。

成果物 (Markdown / HTML / プレーンテキスト) を出す前の機械チェック層。1 件でも出れば exit 1。
でっち上げや一次情報の裏付けといった中身の確認は扱わない。それは人が見る。

使い方:
  prose-lint.py FILE [FILE ...]           全ルールで検査
  prose-lint.py --skip hard-wrap FILE     ルールを外す (カンマ区切り)
  prose-lint.py --only em-dash,hype FILE  ルールを絞る
  prose-lint.py --list-rules              ルール一覧
"""
from __future__ import annotations

import argparse
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

# (id, 正規表現, 直し方)。書きぶりの好みは ~/.config/claude-memory/personal/prose-*.md と対応する。
RULES: list[tuple[str, str, str]] = [
    ("em-dash", r"—", "em dash は使わない。文を分けるか読点にする"),
    ("fw-colon-semicolon", r"[：；]", "全角コロン・セミコロンは使わない。文に直す"),
    ("semicolon", r"(?<=[^\s&]);\s", "セミコロンで文をつながない"),
    ("slash-pair", r"[぀-ヿ㐀-鿿]{2,}(?<![円件人回枚本台個])/(?![時日月年週回件人秒分])[぀-ヿ㐀-鿿]{2,}|\b[A-Z][a-z]+/[A-Z][a-z]+\b", "語をスラッシュで束ねない (単位の 円/時 は対象外)。並べて書く"),
    ("placeholder", r"\b(TODO|TBD|FIXME|XXX)\b|\{\{[^}]*\}\}|lorem ipsum|\[要確認\]|<placeholder>", "書き換え忘れ"),
    (
        "ai-preamble",
        r"^(以下に|以下では|本記事では|本稿では|この記事では)|いかがでしょうか|いかがでしたか|ぜひ|ご参考まで|お役に立て"
        r"|について(解説|説明|紹介)(し|する)"
        r"|^(Certainly|Sure|Absolutely)\b|\bHere['’]?s (a|an|the|how|what)\b|\bIn this (article|post|guide)\b"
        r"|\bLet['’]?s dive\b|\bdelve\b|\bIn conclusion\b|\bIt['’]?s worth noting\b|\bI hope this helps\b",
        "AI らしい前置きや締め。本文から始める",
    ),
    (
        "hype",
        r"革命的|画期的|圧倒的|劇的に|究極の|最強の"
        r"|\bseamless(ly)?\b|\bgame[- ]chang(er|ing)\b|\bcutting[- ]edge\b|\bleverag(e|es|ing)\b"
        r"|\brevolutioniz|\bsupercharge|\beffortless(ly)?\b|\bunlock(s|ing)? the\b",
        "誇張語。事実と数字で書く",
    ),
    ("hard-wrap", None, "段落の途中で改行しない。1 段落 1 行 (Markdown / テキストのみ)"),
]

BLOCK_TAGS = {"p", "li", "h1", "h2", "h3", "h4", "h5", "h6", "td", "th", "blockquote", "figcaption", "summary", "dt", "dd", "caption", "label"}
SKIP_TAGS = {"pre", "code", "script", "style", "svg", "textarea"}


class BlockText(HTMLParser):
    """ブロック要素ごとにテキストを 1 行にまとめ、開始タグの行番号を付ける。"""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.blocks: list[tuple[int, str]] = []
        self._stack: list[tuple[str, int, list[str]]] = []
        self._skip = 0

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag in SKIP_TAGS:
            self._skip += 1
        elif tag in BLOCK_TAGS:
            self._stack.append((tag, self.getpos()[0], []))

    def handle_endtag(self, tag: str) -> None:
        if tag in SKIP_TAGS:
            self._skip = max(0, self._skip - 1)
        elif tag in BLOCK_TAGS and self._stack and self._stack[-1][0] == tag:
            _, line, buf = self._stack.pop()
            text = re.sub(r"\s+", " ", "".join(buf)).strip()
            if text:
                self.blocks.append((line, text))

    def handle_data(self, data: str) -> None:
        if self._stack and not self._skip:
            self._stack[-1][2].append(data)


def strip_noise(text: str) -> str:
    text = re.sub(r"`[^`]*`", "", text)
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"<!--.*?-->", "", text)
    return text


def markdown_lines(raw: str) -> tuple[list[tuple[int, str]], list[tuple[int, str]]]:
    """(検査対象の行, 段落改行チェック対象の行) を返す。コードブロックと frontmatter は除く。"""
    lines = raw.splitlines()
    checkable: list[tuple[int, str]] = []
    prose: list[tuple[int, str]] = []
    in_fence = False
    i = 0
    if lines and lines[0].strip() == "---":
        j = next((k for k in range(1, len(lines)) if lines[k].strip() == "---"), None)
        if j is not None:
            i = j + 1
    for n in range(i, len(lines)):
        line = lines[n]
        if re.match(r"^\s*(```|~~~)", line):
            in_fence = not in_fence
            continue
        if in_fence or not line.strip():
            continue
        checkable.append((n + 1, strip_noise(line)))
        structural = re.match(r"^(\s{2,}|\t|#|[-*+]\s|\d+[.)]\s|>|\||<|!\[|\[.+\]:)", line)
        if not structural and not line.rstrip("\n").endswith(("  ", "\\", "<br>")):
            prose.append((n + 1, line))
    return checkable, prose


def hard_wraps(prose: list[tuple[int, str]]) -> list[int]:
    """連続する散文行の各かたまりについて、先頭行だけを返す。"""
    starts: list[int] = []
    prev = None
    for (a, _), (b, _) in zip(prose, prose[1:]):
        if b == a + 1 and prev != a:
            starts.append(a)
        prev = b if b == a + 1 else None
    return starts


def lint_file(path: Path, active: set[str]) -> list[tuple[int, str, str]]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    suffix = path.suffix.lower()
    findings: list[tuple[int, str, str]] = []
    if suffix in {".html", ".htm"}:
        parser = BlockText()
        parser.feed(raw)
        checkable = [(n, strip_noise(t)) for n, t in parser.blocks]
        prose: list[tuple[int, str]] = []
    else:
        checkable, prose = markdown_lines(raw)
    for rule_id, pattern, _ in RULES:
        if rule_id not in active or pattern is None:
            continue
        rx = re.compile(pattern)
        for n, text in checkable:
            m = rx.search(text)
            if m:
                s = max(0, m.start() - 30)
                findings.append((n, rule_id, text[s : m.end() + 30].strip()))
    if "hard-wrap" in active and prose:
        for n in hard_wraps(prose):
            findings.append((n, "hard-wrap", next(t for k, t in prose if k == n)[:60]))
    return sorted(findings)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--skip", default="", help="外すルール (カンマ区切り)")
    ap.add_argument("--only", default="", help="このルールだけ (カンマ区切り)")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args()
    ids = [r[0] for r in RULES]
    if args.list_rules:
        for rule_id, _, how in RULES:
            print(f"{rule_id:20s} {how}")
        return 0
    if not args.files:
        ap.error("FILE を指定する")
    active = set(args.only.split(",")) if args.only else set(ids)
    active -= set(filter(None, args.skip.split(",")))
    unknown = active - set(ids)
    if unknown:
        ap.error(f"不明なルール: {', '.join(sorted(unknown))}")
    total = 0
    counts: dict[str, int] = {}
    for path in args.files:
        for n, rule_id, excerpt in lint_file(path, active):
            print(f"{path}:{n}: [{rule_id}] {excerpt}")
            total += 1
            counts[rule_id] = counts.get(rule_id, 0) + 1
    sys.stdout.flush()
    if total:
        detail = ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
        print(f"\nNG {total} 件 ({detail})", file=sys.stderr)
        return 1
    print("OK", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
