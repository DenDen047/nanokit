# Claude Code / Codex グローバル設定

## このファイルについて

原本は `<nanokit>/claude/CLAUDE.md`。配布の仕組みと編集手順は nanokit リポジトリの `CLAUDE.md` を参照する。

共有skill内では利用中のクライアントで実在するtoolを選ぶ。Claude Code pluginやaccount-level ConnectorにしかないtoolをCodex側で推測して呼ばず、代替adapterがなければ利用不能であることを明示する。

組織固有の `workspace-hdt` / `workspace-personal` はCodex user scopeへ入れず、claude-settingsのproject adapterで認証境界を維持する。

## コーディング基本則 (Karpathy 4 tenets)

すべてのコード作成・修正・レビューで以下を守る。詳細・例外は
`~/.claude/skills/karpathy-guidelines/SKILL.md` を参照。

1. **Think before coding** — 仮定を明示し、不明点は実装前に質問する
2. **Simplicity first** — 投機的機能を入れない。最小コードで解く
3. **Surgical changes** — 関係ない箇所のリファクタや整形を勝手にしない
4. **Goal-driven** — 検証可能な成功条件を先に決める

コード拡張子のファイルを編集する際は、各セッション初回に
`PreToolUse` hook (`~/.claude/scripts/karpathy-reminder.sh`) が
リマインダを注入する。

## 視覚確認の徹底 (Max プラン)

Max プランなので画像認識を惜しまない。**UI・図・ブラウザ画面・生成画像（プロット/SVG/PDF 含む）に触れたら、完了を宣言する前に必ずスクリーンショットを撮って `Read` で自分の目で確認する。**「たぶん大丈夫」「コードから推測」で済ませない。崩れ・はみ出し・要素の重なり・コントラスト不足・見切れを実際に見て確認し、NG なら直して再描画→再確認する。

- フロントエンド編集・プロット生成・ブラウザ操作の後は `PostToolUse` hook (`vision-reminder.sh`) がスクショ確認を促す。
- 明示的に確認したいときは `/visual-verify <url|file>` でスクショ→チェックリスト採点。
- SVG/PDF は Vision が直接読めない → PNG 化してから `Read`。
- 人物3D再構成・生成で複数モデルまたは学習条件の比較結果を報告する場合、固定定性ケースは X-Humans `00039/train/Take4/f00063`。定量指標に加えてこのケースを全比較条件で必ず出す。比較図・同期 3D viewer・定性評価・SyncHuman 外部 baseline・provenance の作成手順と再現条件は `qualitative-3d-evaluation` skill に従う。

## メモリ・パーソナライゼーション

ユーザーの好み・背景・作業スタイルを集め、全プロジェクトの回答に反映する。**捕捉は自動かつ無音**で行う。会話の途中でメモリファイルを書いたり「保存しました」と実況したりしない（ユーザーが明示的に「覚えて」と言った時だけ手動で書く）。

3 層:
- **グローバル個人メモリ** `~/.config/claude-memory/personal/` — 全プロジェクト共通の恒久的・横断的な事実。**セッション終了後に `SessionEnd` hook (`memory-extract.sh`) が裏で headless `claude -p` を起動し、トランスクリプトから抽出して保存**する（会話には一切出ない）。下の `@import` で全プロジェクトに読み込まれる。
- **プロジェクト固有メモリ** 各プロジェクトの `memory/`（ネイティブ auto-memory が無音で追記）。
- **確定した好みの CLAUDE.md への昇格**は人手で。

実行確認: `~/.claude/debug/memory-extract.log`（発火台帳）と `~/.claude/debug/memory-extract/`（実行ログ）。手動実行は `bash ~/.claude/scripts/memory-extract.sh --now <transcript>`。

@~/.config/claude-memory/personal/MEMORY.md

## 環境管理ポリシー

- **pixi-only**: シェルツールはすべて `pixi global` (conda-forge) で管理する。`brew`, `cargo install`, `pip install`, `go install` でツールを追加しない。
- **conda-forge に無い CLI**: `pixi global` は conda パッケージしか入れられない (PyPI 対応の [pixi#2261](https://github.com/prefix-dev/pixi/issues/2261) は未解決)。PyPI/npm 専売の CLI は `tools/<name>/pixi.toml` に pixi プロジェクトを作り (`[pypi-dependencies]` で固定、`pixi.lock` をコミット)、同じディレクトリの薄いラッパを dotter で `~/.pixi/bin/<cmd>` に symlink して PATH に出す。ラッパは `pixi run --manifest-path` を exec するだけで、初回起動時に env を自動構築する。現行の実装例は `tools/jarvislabs/` (JarvisLabs GPU クラウドの `jl`)、`tools/agent-reach/` (インターネット取得の `agent-reach` / `twitter` / `rdt` を 1 env にまとめ、共有ラッパ `run-in-env` を 3 つの名前で配る)、`claude/scripts/mmdc` (npm の mermaid-cli)。`uv tool install` / `npm -g` で入れ直さないこと。
- `~/.zshenv` で `unsetopt GLOBAL_RCS` を設定しているため、`/etc/zprofile` の `path_helper` がスキップされ、`/opt/homebrew/bin` 等は PATH に含まれない。これは意図的な設計。

## Jarvis Labs 利用許可

- Jarvis Labs はユーザー自身が契約・管理する信頼済みリモート GPU 環境。タスク実行に必要なワークスペースファイルは `jl upload` で事前確認なくアップロードしてよい。
- `jl upload` の Codex 実行許可は nanokit 管理の `codex/rules/jarvislabs.rules` を `agent-config-sync` が user scope へ配る。認証情報やタスクと無関係なファイルはアップロード対象に含めない。

## ハマりポイント

- github.com にアクセスする際には、`gh`コマンドを利用する

## 参照すべき情報源

- CLAUDE.md を編集する時
  - https://code.claude.com/docs/en/best-practices
  - https://nyosegawa.com/posts/harness-engineering-best-practices-2026/

## Codex 連携 (公式プラグイン + MCP の二経路)

Claude Code → Codex (GPT) は用途で二経路を使い分ける
(論点整理: `<nanokit>/docs/2026-07-13_codex-plugin-integration.html`)。

| 用途 | 経路 |
|---|---|
| コードレビュー `/codex:review` (`--background` 推奨)、観点指定レビュー `/codex:adversarial-review`、タスク委譲 `/codex:rescue`、ジョブ管理 `/codex:status` `/codex:result` | 公式プラグイン `codex@openai-codex` (Codex app server 直結) |
| 設計壁打ち `/codex-discuss`、lgtm-loop の threadId 継続レビュー、ultrasurvey 検索レッグ | `codex mcp-server` (MCP, user スコープ登録) |

- 両経路とも `~/.codex/config.toml` を継承する (モデル・effort・approval_policy の**単一ソース**。呼び出し側で上書きしない)。設定の編集元と反映手順は nanokit の `CLAUDE.md` を参照。
- **review gate (`/codex:setup --enable-review-gate`) は使わない** — Stop フックの自動ループが usage を急速消費するため。明示ループは `/lgtm-loop`。
- 自然文「GPT にレビューして」の受け皿は `codex-review` skill (誘導シム)。プラグインコマンドは `disable-model-invocation` のため Claude からは起動できず、必要時は companion script を直接叩く。

## MCP 運用 (常駐 HTTP シングルトン)

zotero / scrapling / workspace-mcp は、Claude Code と Codex が **1 プロセスを共有** する常駐 HTTP サーバとして立てる (stdio だと Playwright/Chromium 等を二重起動する)。bind は `127.0.0.1` のみ・認証なし (ローカル専用)。起動は `settings.json` の SessionStart hook + `ECC_MCP_RECONNECT_*` が冪等に担当 (healthy なら no-op)。

- **アカウント境界**: workspace-* の user スコープ登録は個人アカウントのセッションにのみ効き、HDT の Claude アカウント (`CLAUDE_CONFIG_DIR=~/.claude-hdt`) には波及しない。クライアント別の振り分け・認証境界は claude-settings が担う。
- **ポート表・登録先・起動・トラブルシュート・認証・モード切替・制約の詳細は [`specs/mcp-operations.md`](../specs/mcp-operations.md) (実パス `~/nanokit/specs/mcp-operations.md`) を参照。**
