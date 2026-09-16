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

## 選ぶ目安 (索引は「人でしか判断できない横断的な好み」だけの置き場)

`feedback` 型の行は、載せる前に「どこに置けば次から機械か skill が守るか」を考える。

| 指摘の性質 | 置き場 | 索引 |
|---|---|---|
| grep で拾える (記号・定型句・置き忘れ) | `~/.claude/scripts/prose-lint.py` のルール、または hook / lint | 載せない |
| 特定 skill の手順の問題 | その `SKILL.md` に箇条書きを 1 行足す | 載せない |
| プロジェクト固有の事実 | `okf/` かそのプロジェクトの memory | 載せない |
| 上のどれでもない横断的な好み | `MEMORY.md` | 載せる |

同じ指摘が 2 回目なら成果物ではなく skill か lint を直す。機械が止めるようになった規則は索引と skill 本文から消してよい。移し先の編集は `--review-apply` の後に別ターンで行う。

## 規則

- `MEMORY.md` / `ARCHIVE.md` / `PENDING.md` をこの skill の中で手で編集しない。移動はスクリプトが行う。
- レビュー中に項目を統合・要約・書き換えしない。それは別の明示的な依頼で行う。
