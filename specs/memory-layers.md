# メモリの層と昇格経路

Claude Code のパーソナライゼーション用メモリは、置き場ごとにロードのされ方が違う。どの層も「エージェントが書いたものは、人が選ぶまで常時ロードに入らない」を守る。

## 層

| 層 | 置き場 | ロード | 書く人 |
|---|---|---|---|
| グローバル索引 | `~/.config/claude-memory/personal/MEMORY.md` | 全プロジェクト・毎セッション (`~/.claude/CLAUDE.md` の `@import`) | 人 (週次レビューで昇格。「覚えて」と明示された時は `--add-index` でその場で 1 行) |
| グローバル本体 | 同ディレクトリの `*.md`。1 ファイル 1 事実、frontmatter は `name` / `description` / `metadata.type` (user / feedback / reference) | 索引・保留・退避のポインタから辿ったときだけ | SessionEnd の抽出 |
| 保留 | 同ディレクトリの `PENDING.md` | ロードされない | SessionEnd の抽出 |
| 退避 | 同ディレクトリの `ARCHIVE.md` | ロードされない。必要なとき grep | 剪定と週次レビュー |
| プロジェクト固有 | `~/.claude/projects/<slug>/memory/` | そのプロジェクトのセッション (ネイティブ auto-memory) | セッション中のエージェント |

## 抽出 (SessionEnd)

`~/.claude/settings.json` の SessionEnd hook が `~/.claude/scripts/memory-extract.sh` (実体 `claude/scripts/memory-extract.sh`) を呼び、切り離した子プロセス (`--run`) が次を順に行う。

1. `personal/.lock` に flock (カーネル管理の排他ロック) を取る (最長 30 分待つ)。索引・退避・キューに書く処理 (`--review-apply`、`--add-index`、剪定) は全てこのロックの下で走る。持ち主のプロセスが死ねばカーネルが解放するので、stale なロックは生じない
2. `MEMORY.md` / `ARCHIVE.md` / `PENDING.md` のスナップショットを `personal/.staging/<session>.snap/` に取る
3. headless `claude -p` がトランスクリプトを読み、新しい事実を本体ファイルに書き、ポインタ行を `personal/.staging/<session>.md` に積む。重複判定は `MEMORY.md` と `PENDING.md` を読み、`ARCHIVE.md` は grep する
4. モデルが `PENDING.md` に直接書いた行があれば staging へ退避したうえで、スナップショットと比べて `MEMORY.md` / `ARCHIVE.md` / `PENDING.md` が変わっていれば元に戻し (事前に無かったファイルを作っていれば消す)、台帳に WARN を書いて通知センターに出す (モデルが門を迂回した場合の機械的な差し戻し)。スナップショットが取れなければ抽出自体を行わない
5. staging の行を `PENDING.md` へ追記する (キュー・索引・退避のうち存在するファイルに同じ行があれば捨てる)。追記に失敗したら staging を残して止まる。前回途中で死んだ run の staging も同時に拾う
6. 統合が済んだ状態を個人メモリの git にコミットする。索引が予算を超えていれば剪定を走らせる。剪定の前にもコミットしてその commit id をチェックポイントにし、コミットできなければ (git でない、git が失敗) 剪定しない。剪定が失敗・タイムアウトしたら curated 3 ファイルをスナップショットから、追跡ファイルをチェックポイントから戻し、どちらかが戻せなければ ROLLBACK INCOMPLETE として commit id とスナップショットの場所を台帳に残す。成功時も `PENDING.md` が触られていたら戻す

- 発火台帳 `~/.claude/debug/memory-extract.log`
- 実行ログ `~/.claude/debug/memory-extract/<ts>_<sid>.log`
- 手動実行 `bash ~/.claude/scripts/memory-extract.sh --now <transcript.jsonl>`
- 予算確認 `bash ~/.claude/scripts/memory-extract.sh --budget` (索引の上限は 200 行 / 25 KB)
- 保留の一覧 `bash ~/.claude/scripts/memory-extract.sh --pending`

## 週次レビュー (昇格ゲート)

`/memory-review` skill (`claude/skills/memory-review`) が `PENDING.md` を番号付きで提示し、選ばれた行を `MEMORY.md` へ、それ以外を `ARCHIVE.md` へ移す (`--review-apply`)。既定は「載せない」。抽出は毎セッション走るので、確認の頻度を落としても取りこぼしは起きない。移動は同じロックの下で、各ファイルを一時ファイルに書いて rename し、移動先に既にある行は飛ばし、キューを最後に書く。途中で止まっても、もう一度実行すれば収束する。抽出が走っている間は 30 秒待って「後で再実行」と返す。

索引が予算を超えると剪定 (`--prune-if-over`) が走り、ポインタ行を短縮・統合・`ARCHIVE.md` へ降格する。本体ファイルは消さない。

## 索引の書き方

1 行 1 メモリ `- [Title](file.md) — hook`。同じマシンの環境制約のように常に束で効く事実は、ハブ 1 行 (`env-mac-profile.md`) にまとめ、個別の行は `ARCHIVE.md` に置く。本体ファイル同士は `[[slug]]` で相互参照しているので、統合してもファイルは消さない。

## 履歴

`~/.config/claude-memory` はローカルだけの git リポジトリ。個人情報を含むので remote は付けない。週次レビューの差分は `git log` で見る。
