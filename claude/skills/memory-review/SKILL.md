---
name: memory-review
description: Weekly promotion gate for the personal memory queue. Shows the PENDING.md entries the SessionEnd extractor wrote, lets the user pick which reach the always-loaded MEMORY.md, archives the rest. Use when the user asks to review pending memories — 「保留メモリ」「メモリのレビュー」「memory review」「/memory-review」.
---

# memory-review

`~/.config/claude-memory/personal/` の昇格ゲート。抽出は `MEMORY.md` に書かず `PENDING.md` に積む。ここで人が選んだ行だけが索引に載る。既定は「載せない」。

## 手順

1. `bash ~/.claude/scripts/memory-extract.sh --pending` を実行する。`(empty)` なら、そう伝えて終わる。
2. 番号付きの一覧をそのまま見せる（要約・並べ替え・言い換えをしない）。「索引に残す番号をカンマ区切りで。無ければ none」と 1 行で聞く。推薦はしない。選ぶのはユーザー。
3. `bash ~/.claude/scripts/memory-extract.sh --review-apply <番号,番号,…|none>` を実行する。選ばれた行は `MEMORY.md` の末尾へ、残りは `ARCHIVE.md` の型ごとの節へ移り、キューは空になり、ローカル git にコミットされる。
4. スクリプトが出す `REVIEWED:` 行と予算の行を報告する。予算超過なら次の剪定で降格されると添える。

## 規則

- `MEMORY.md` / `ARCHIVE.md` / `PENDING.md` をこの skill の中で手で編集しない。移動はスクリプトが行う。
- レビュー中に項目を統合・要約・書き換えしない。それは別の明示的な依頼で行う。
