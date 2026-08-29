# メモリの層と昇格経路

Claude Code のパーソナライゼーション用メモリは、置き場ごとにロードのされ方が違う。どの層も「エージェントが書いたものは、人が選ぶまで常時ロードに入らない」を守る。

## 層

| 層 | 置き場 | ロード | 書く人 |
|---|---|---|---|
| グローバル索引 | `~/.config/claude-memory/personal/MEMORY.md` | 全プロジェクト・毎セッション (`~/.claude/CLAUDE.md` の `@import`) | 人 (週次レビューで昇格。「覚えて」と明示された時はその場で 1 行) |
| グローバル本体 | 同ディレクトリの `*.md`。1 ファイル 1 事実、frontmatter は `name` / `description` / `metadata.type` (user / feedback / reference) | 索引・保留・退避のポインタから辿ったときだけ | SessionEnd の抽出 |
| 保留 | 同ディレクトリの `PENDING.md` | ロードされない | SessionEnd の抽出 |
| 退避 | 同ディレクトリの `ARCHIVE.md` | ロードされない。必要なとき grep | 剪定と週次レビュー |
| プロジェクト固有 | `~/.claude/projects/<slug>/memory/` | そのプロジェクトのセッション (ネイティブ auto-memory) | セッション中のエージェント |

## 抽出 (SessionEnd)

`~/.claude/settings.json` の SessionEnd hook が `~/.claude/scripts/memory-extract.sh` (実体 `claude/scripts/memory-extract.sh`) を呼ぶ。切り離した headless `claude -p` がトランスクリプトを読み、新しい事実を本体ファイルに書き、ポインタ行を `PENDING.md` に積む。`MEMORY.md` には書かない。重複判定は `MEMORY.md`、`ARCHIVE.md`、`PENDING.md` の 3 つを読んで行う。

- 発火台帳 `~/.claude/debug/memory-extract.log`
- 実行ログ `~/.claude/debug/memory-extract/<ts>_<sid>.log`
- 手動実行 `bash ~/.claude/scripts/memory-extract.sh --now <transcript.jsonl>`
- 予算確認 `bash ~/.claude/scripts/memory-extract.sh --budget` (索引の上限は 200 行 / 25 KB)
- 保留の一覧 `bash ~/.claude/scripts/memory-extract.sh --pending`

## 週次レビュー (昇格ゲート)

`/memory-review` skill (`claude/skills/memory-review`) が `PENDING.md` を番号付きで提示し、選ばれた行を `MEMORY.md` へ、それ以外を `ARCHIVE.md` へ移す。既定は「載せない」。抽出は毎セッション走るので、確認の頻度を落としても取りこぼしは起きない。

索引が予算を超えると剪定 (`--prune-if-over`) が走り、ポインタ行を短縮・統合・`ARCHIVE.md` へ降格する。本体ファイルは消さない。

## 索引の書き方

1 行 1 メモリ `- [Title](file.md) — hook`。同じマシンの環境制約のように常に束で効く事実は、ハブ 1 行 (`env-mac-profile.md`) にまとめ、個別の行は `ARCHIVE.md` に置く。本体ファイル同士は `[[slug]]` で相互参照しているので、統合してもファイルは消さない。

## 履歴

`~/.config/claude-memory` はローカルだけの git リポジトリ。個人情報を含むので remote は付けない。週次レビューの差分は `git log` で見る。
