# Claude Code / Codex グローバル設定

## シンボリックリンク構造

このファイル (`<nanokit>/claude/CLAUDE.md`) がグローバル指示の本体。

- Claude Code: dotter が `~/.claude/CLAUDE.md` へ symlink する。
- Codex: `./nanokit agent-config-sync` が `~/.codex/AGENTS.md` へ symlink する。
- 共有スキル: `<nanokit>/claude/skills/<name>` を原本として、同コマンドが `~/.claude/skills/<name>` と `~/.agents/skills/<name>` の両方へ symlink する。配布は毎セッション `SessionStart` hook (`agent-config-sync-reconnect.sh`) が冪等に自己修復し、**成功時は無音・未同期が出た時だけ** `systemMessage` で警告する (手動同期漏れによる 2026-07 のスキル配布ドリフト再発防止)。`sync-config.py` は1件の衝突で全体を止めず、該当項目だけスキップして残りを配布し明示報告する (`rc=2`)。

共有skill内では利用中のクライアントで実在するtoolを選ぶ。Claude Code pluginやaccount-level ConnectorにしかないtoolをCodex側で推測して呼ばず、代替adapterがなければ利用不能であることを明示する。

`agent-config-sync` はclient-safeなHTTP MCP (`scrapling`, `zotero`, `deepwiki`) も両CLIへ登録する。組織固有の `workspace-hdt` / `workspace-personal` はCodex user scopeへ入れず、claude-settingsのproject adapterで認証境界を維持する。

`~/.claude/` 配下のツール固有設定は次のようにdotterで配る。

| リポジトリ内パス | シンボリックリンク先 |
|---|---|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/scripts/zotero-mcp-server.sh` | `~/.claude/scripts/zotero-mcp-server.sh` |
| `claude/scripts/scrapling-mcp-server.sh` | `~/.claude/scripts/scrapling-mcp-server.sh` |
| `claude/scripts/workspace-mcp-hdt-server.sh` | `~/.claude/scripts/workspace-mcp-hdt-server.sh` |
| `claude/scripts/vision-reminder.sh` | `~/.claude/scripts/vision-reminder.sh` |
| `claude/scripts/memory-extract-reminder.sh` | `~/.claude/scripts/memory-extract-reminder.sh` |
| `claude/scripts/mmdc` | `~/.pixi/bin/mmdc` |
| `claude/ccstatusline/settings.json` | `~/.config/ccstatusline/settings.json` |
| `claude/output-styles` | `~/.claude/output-styles` |

設定を変更する場合はnanokit側の原本を編集し、ツール固有設定は `dotter deploy`、共有指示・スキル・Codex設定・`settings.json` は `./nanokit agent-config-sync` で反映する。`settings.json` だけは Claude Code 自身がUI変更やキー正規化で書き戻す (= symlink 不可) ため dotter ではなく agent-config-sync が管理する (下記「settings.json の反映モデル」)。

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
- **conda-forge に無い CLI**: `pixi global` は conda パッケージしか入れられない (PyPI 対応の [pixi#2261](https://github.com/prefix-dev/pixi/issues/2261) は未解決)。PyPI/npm 専売の CLI は `tools/<name>/pixi.toml` に pixi プロジェクトを作り (`[pypi-dependencies]` で固定、`pixi.lock` をコミット)、同じディレクトリの薄いラッパを dotter で `~/.pixi/bin/<cmd>` に symlink して PATH に出す。ラッパは `pixi run --manifest-path` を exec するだけで、初回起動時に env を自動構築する。現行の実装例は `tools/jarvislabs/` (JarvisLabs GPU クラウドの `jl`) と `claude/scripts/mmdc` (npm の mermaid-cli)。`uv tool install` / `npm -g` で入れ直さないこと。
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

- 両経路とも `~/.codex/config.toml` を継承する (モデル・effort・approval_policy の**単一ソース**。呼び出し側で上書きしない)。
- そのポータブル設定 (model / model_reasoning_effort / approval_policy / web_search 等) は **nanokit が管理**する。編集元は `<nanokit>/codex/config.toml`、反映は `./nanokit agent-config-sync` (`--diff` でプレビュー)。実ファイルは Codex デスクトップアプリが `[projects.*]` の trust_level 等の端末・クライアント固有状態を書き戻して共有するため symlink 不可 (nanokit は公開リポジトリなので載せられない) → sync が管理キーだけを冪等 upsert し、他セクションは保持する。`codex-install` 内でも自動実行される。
- **review gate (`/codex:setup --enable-review-gate`) は使わない** — Stop フックの自動ループが usage を急速消費するため。明示ループは `/lgtm-loop`。
- 自然文「GPT にレビューして」の受け皿は `codex-review` skill (誘導シム)。プラグインコマンドは `disable-model-invocation` のため Claude からは起動できず、必要時は companion script を直接叩く。
- 新ホスト: プラグインは `claude/settings.json` の `extraKnownMarketplaces` + `enabledPlugins` で宣言済み (dotter 配布)。自動導入されなければ `claude plugin install codex@openai-codex`。MCP 登録は `./nanokit codex-install`。

## MCP 運用 (常駐 HTTP シングルトン)

zotero / scrapling / workspace-mcp は、Claude Code と Codex が **1 プロセスを共有** する常駐 HTTP サーバとして立てる (stdio だと Playwright/Chromium 等を二重起動する)。bind は `127.0.0.1` のみ・認証なし (ローカル専用)。起動は `settings.json` の SessionStart hook + `ECC_MCP_RECONNECT_*` が冪等に担当 (healthy なら no-op)。

| サーバ | ポート | ランチャ (`~/.claude/scripts/`) | 用途 |
|---|---|---|---|
| zotero-mcp | 8321 | `zotero-mcp-server.sh` | 文献。local/web 自動切替 |
| workspace-personal | 8322 | `workspace-mcp-personal-server.sh` | 個人 Google (`sh.mn.nat@gmail.com`) |
| scrapling-mcp | 8323 | `scrapling-mcp-server.sh` | ブラウザ取得 (Playwright) |
| workspace-hdt | 8324 | `workspace-mcp-hdt-server.sh` | HDT Google (ポータブル OAuth) |

- **アカウント境界**: workspace-* の user スコープ登録は個人アカウントのセッションにのみ効き、HDT の Claude アカウント (`CLAUDE_CONFIG_DIR=~/.claude-hdt`) には波及しない。クライアント別の振り分け・認証境界は claude-settings が担う。
- 新ホストでは `dotter deploy` 後に HTTP MCP を手動登録する (`~/.claude.json` / `~/.codex/config.toml` は dotter 管理外の state)。登録先はサービスで分ける: **`scrapling`/`zotero`/`deepwiki` は `agent-config-sync` が両 CLI (Claude/Codex の user scope) へ登録**、**`workspace-*` は Claude 個人アカウントの user scope のみ** に登録する (Codex user scope へは入れない — 認証境界は claude-settings の project adapter が維持。上の「シンボリックリンク構造」節と同じ規則)。
- **起動・登録・トラブルシュート・認証・モード切替・制約の詳細、および RTK バージョンアップ時の設定同期手順は [`specs/mcp-operations.md`](../specs/mcp-operations.md) (実パス `~/nanokit/specs/mcp-operations.md`) を参照。**

## settings.json の反映モデル (symlink ではなく管理反映)

`~/.claude/settings.json` は **Claude Code 自身が所有する読み書きファイル**。UI での設定変更 (`/model` `/vim` 出力スタイル プラグイン有効化 など) やキー正規化のたびにアプリが atomic replace で書き戻すため、symlink にすると壊れる (実体ファイル化する)。よって dotter 管理せず、`agent-config-sync` (`codex/sync-config.py` の `settings_change()`) が **nanokit 原本の宣言キーを権威として live へマージ反映**する (Codex `config.toml` と同じ思想)。

- 原本が宣言するトップレベルキーは原本が勝つ。**live 側だけのアプリ由来キー (`hasCompletedOnboarding` 等) は保持**する (データ損失なし)。
- 反映は毎セッション `SessionStart` hook (`agent-config-sync-reconnect.sh`) が冪等に自己修復。実体ファイルがズレても次セッションで自動的に再マージされるので **手動復旧は不要**。
- 含意: アプリ内で管理キーを変えても次の同期で原本値に戻る。恒久化したい変更は **nanokit 原本の `settings.json` を編集**する (単一ソース)。

```bash
# 手動反映したいとき (通常は不要 — SessionStart で自動)
cd "$NANOKIT" && ./nanokit agent-config-sync        # --diff で事前確認可
```

@RTK.md
