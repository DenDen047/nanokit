# Claude Code / Codex グローバル設定

## このファイルについて

原本は `<nanokit>/claude/CLAUDE.md`。配布の仕組みと編集手順は nanokit リポジトリの `CLAUDE.md` を参照する。

共有 skill では利用中のクライアントに実在する tool を選ぶ。Claude Code plugin や account-level Connector にしかない tool を Codex 側で推測して呼ばず、代替 adapter が無ければ利用不能と明示する。組織固有の `workspace-hdt` / `workspace-personal` は Codex user scope へ入れず、claude-settings の project adapter で認証境界を保つ。

## コーディング基本則 (Karpathy 4 tenets)

すべてのコード作成・修正・レビューで守る。詳細・例外は `~/.claude/skills/karpathy-guidelines/SKILL.md` を参照。

1. **Think before coding** — 仮定を明示し、不明点は実装前に質問する
2. **Simplicity first** — 投機的機能を入れない。最小コードで解く
3. **Surgical changes** — 関係ない箇所のリファクタや整形を勝手にしない
4. **Goal-driven** — 検証可能な成功条件を先に決める

コード拡張子のファイルを編集する際は、各セッション初回に `PreToolUse` hook (`~/.claude/scripts/karpathy-reminder.sh`) がリマインダを注入する。

## 文章の書き方 (第三者が読むもの)

レポート・コミットメッセージ・PR 説明・ドキュメント・Slack / Notion 投稿など第三者が読む文章では、**見た目の幅を抑えるためだけの改行を入れない**。1 段落 = 1 行で書き、改行は段落の区切り・箇条書きの項目・コードブロックなど構造上の意味がある位置にだけ使う。意味のない改行は貼り付け先で不自然に折り返され、diff も行単位で汚れる。折り返し表示はエディタや閲覧側の役目。

## 視覚確認の徹底 (Max プラン)

Max プランなので画像認識を惜しまない。**UI・図・ブラウザ画面・生成画像 (プロット/SVG/PDF 含む) に触れたら、完了を宣言する前に必ずスクリーンショットを撮って `Read` で自分の目で確認する。**コードからの推測で済ませず、崩れ・はみ出し・重なり・コントラスト不足・見切れを見て、NG なら直して再確認する。

- フロントエンド編集・プロット生成・ブラウザ操作の後は `PostToolUse` hook (`vision-reminder.sh`) が促す。
- 明示的に確認したいときは `/visual-verify <url|file>` でスクショ→チェックリスト採点。
- SVG/PDF は Vision が直接読めない → PNG 化してから `Read`。
- 人物3D再構成・生成の比較報告では、定量指標に加えて固定定性ケース X-Humans `00039/train/Take4/f00063` を全比較条件で必ず出す。比較図・3D viewer・SyncHuman 外部 baseline・provenance の手順は `qualitative-3d-evaluation` skill に従う。

## メモリ・パーソナライゼーション

ユーザーの好み・背景・作業スタイルは SessionEnd hook が無音で捕捉し、全プロジェクトの回答に反映する。会話中にメモリファイルを書いたり「保存しました」と実況したりしない。明示的に「覚えて」と言われた時だけ手動で書き、そのときは索引 `MEMORY.md` にも 1 行足してよい。自動捕捉分は索引に直接載せず、人が週次レビューで選んだものだけを載せる。層・置き場・確認手順は `~/nanokit/specs/memory-layers.md`。

@~/.config/claude-memory/personal/MEMORY.md

## 環境管理ポリシー

- **pixi-only**: シェルツールはすべて `pixi global` (conda-forge) で管理する。`brew`, `cargo install`, `pip install`, `go install` で追加しない。
- **conda-forge に無い CLI**: `pixi global` は conda パッケージしか入れられない ([pixi#2261](https://github.com/prefix-dev/pixi/issues/2261) は未解決)。PyPI/npm 専売の CLI は `tools/<name>/pixi.toml` に pixi プロジェクトを作り (`[pypi-dependencies]` で固定、`pixi.lock` をコミット)、`pixi run --manifest-path` を exec するだけの薄いラッパを dotter で `~/.pixi/bin/<cmd>` へ symlink する。実装例は `tools/jarvislabs/` (`jl`)、`tools/agent-reach/` (`agent-reach` / `twitter` / `rdt` を 1 env に同居、共有ラッパ `run-in-env`)、`claude/scripts/mmdc` (npm の mermaid-cli)。`uv tool install` / `npm -g` で入れ直さない。
- `~/.zshenv` の `unsetopt GLOBAL_RCS` により `/etc/zprofile` の `path_helper` がスキップされ、`/opt/homebrew/bin` 等は PATH に入らない。これは意図的な設計。

## Jarvis Labs 利用許可

- ユーザー自身が契約・管理する信頼済みリモート GPU 環境。タスクに必要なワークスペースファイルは `jl upload` で事前確認なくアップロードしてよい (認証情報やタスクと無関係なファイルは除く)。
- `jl upload` の Codex 実行許可は nanokit 管理の `codex/rules/jarvislabs.rules` を `agent-config-sync` が user scope へ配る。

## ハマりポイント

- github.com にアクセスする際には `gh` コマンドを利用する。

## 参照すべき情報源

- CLAUDE.md を編集する時
  - https://code.claude.com/docs/en/best-practices
  - https://nyosegawa.com/posts/harness-engineering-best-practices-2026/
- Google プロダクト (Cloud / Ads / Analytics / Android / Flutter / Firebase …) の API・CLI・SDK を扱う時
  - 公式ハブ https://github.com/google/skills。**ローカルに入れず都度 GitHub の最新を読む** (`npx skills add`・marketplace 追加はしない)。`gh api -H "Accept: application/vnd.github.raw" repos/google/skills/contents/<path>` で README (索引) → `skills/<cloud|ads|analytics>/<name>/SKILL.md`。README から Android/Flutter/Firebase 等の別リポジトリへも辿れる。
  - `plugins/cloud/data-agent-kit/` は submodule で再帰取得しても展開されない。本文は upstream (`gemini-cli-extensions/<name>` 等) を直接読む。
  - Workspace (Gmail/Calendar/Drive) のスキルは無い → `workspace-*` MCP を使う。

## Codex 連携 (公式プラグイン + MCP の二経路)

用途で使い分ける。

| 用途 | 経路 |
|---|---|
| コードレビュー `/codex:review` (`--background` 推奨)、観点指定レビュー `/codex:adversarial-review`、タスク委譲 `/codex:rescue`、ジョブ管理 `/codex:status` `/codex:result` | 公式プラグイン `codex@openai-codex` (Codex app server 直結) |
| 設計壁打ち `/codex-discuss`、lgtm-loop の threadId 継続レビュー、ultrasurvey 検索レッグ | `codex mcp-server` (MCP, user スコープ登録) |

- 両経路とも `~/.codex/config.toml` を継承する (モデル・effort・approval_policy の**単一ソース**。呼び出し側で上書きしない)。編集元と反映手順は nanokit の `CLAUDE.md` を参照。
- **review gate (`/codex:setup --enable-review-gate`) は使わない** — Stop フックの自動ループが usage を急速消費するため。明示ループは `/lgtm-loop`。
- 自然文「GPT にレビューして」の受け皿は `codex-review` skill (誘導シム)。プラグインコマンドは `disable-model-invocation` で Claude からは起動できず、必要時は companion script を直接叩く。

## MCP 運用

zotero / scrapling / workspace-mcp は Claude Code と Codex が 1 プロセスを共有する常駐 HTTP サーバで、SessionStart hook が冪等に起動する。**bind は `127.0.0.1` のみで認証なし（ローカル専用）。外部インターフェースへ公開する変更はしない。**workspace-* の user スコープ登録は個人アカウントにだけ効き、HDT (`CLAUDE_CONFIG_DIR=~/.claude-hdt`) には波及しない。ポート表・登録先・起動・トラブルシュート・認証は `~/nanokit/specs/mcp-operations.md`。
