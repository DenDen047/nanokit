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
| 設計壁打ち `/codex-discuss`、lgtm-loop の threadId 継続レビュー、ultrasurvey 検索レッグ、ARIS レビュアー | `codex mcp-server` (MCP, user スコープ登録) |

- 両経路とも `~/.codex/config.toml` を継承する (モデル・effort・approval_policy の**単一ソース**。呼び出し側で上書きしない)。
- そのポータブル設定 (model / model_reasoning_effort / approval_policy / web_search 等) は **nanokit が管理**する。編集元は `<nanokit>/codex/config.toml`、反映は `./nanokit agent-config-sync` (`--diff` でプレビュー)。実ファイルは Codex デスクトップアプリが `[projects.*]` の trust_level 等の端末・クライアント固有状態を書き戻して共有するため symlink 不可 (nanokit は公開リポジトリなので載せられない) → sync が管理キーだけを冪等 upsert し、他セクションは保持する。`codex-install` 内でも自動実行される。
- **review gate (`/codex:setup --enable-review-gate`) は使わない** — Stop フックの自動ループが usage を急速消費するため。明示ループは `/lgtm-loop`。
- 自然文「GPT にレビューして」の受け皿は `codex-review` skill (誘導シム)。プラグインコマンドは `disable-model-invocation` のため Claude からは起動できず、必要時は companion script を直接叩く。
- 新ホスト: プラグインは `claude/settings.json` の `extraKnownMarketplaces` + `enabledPlugins` で宣言済み (dotter 配布)。自動導入されなければ `claude plugin install codex@openai-codex`。MCP 登録は `./nanokit codex-install`。

## Zotero MCP 運用

ホスト横断で 1 つの Zotero ライブラリを参照するために、`zotero-mcp` は HTTP サーバー (`localhost:8321`) として `~/.claude/scripts/zotero-mcp-server.sh` 経由で起動される。バイナリは pixi env (`~/nanokit/claude/mcp-servers/zotero-mcp/`) 内。

### モードの自動切替

- **`mode=local`** (Zotero.app 起動中) — `curl http://localhost:23119/connector/ping` が通ったとき。`ZOTERO_LOCAL=true` で起動。メタデータ + PDF 本体 + 注釈作成が可能。
- **`mode=web`** (Zotero.app なし or Linux サーバー) — 上記が通らないとき。`ZOTERO_LOCAL=false` + `ZOTERO_API_KEY` + `ZOTERO_LIBRARY_ID` で起動。メタデータ + フルテキスト（Zotero クラウドの索引）+ ノート + タグ + semantic search が可能。PDF バイナリは取得不可（WebDAV 運用のため）。

判定は `detect_zotero_mode()` が担当。ログの先頭に `mode=local` / `mode=web` が記録される。

### credentials

Web API モードで必要。OS-native な secret store に保存:
- macOS: Keychain (`security find-generic-password -s claude-zotero -a api-key`)
- Linux GUI: GNOME Keyring (`secret-tool lookup service claude-zotero account api-key`)
- fallback: `~/.config/nanokit/secrets.env`

登録は `nanokit zotero-mcp-install` で対話的に行う。

### トラブルシュート

```bash
# 現状確認
bash ~/.claude/scripts/zotero-mcp-server.sh status
tail -20 ~/.claude/debug/zotero-mcp.log

# mode がどちらで立ち上がったか
grep 'mode=' ~/.claude/debug/zotero-mcp.log | tail -5

# 再起動
bash ~/.claude/scripts/zotero-mcp-server.sh stop
bash ~/.claude/scripts/zotero-mcp-server.sh start

# 旧 uv tool 経路への一時切り戻し（もし残っていれば）
ZOTERO_MCP_BINARY=$HOME/.local/bin/zotero-mcp bash ~/.claude/scripts/zotero-mcp-server.sh start
```

### 制約

- **PDF バイナリ取得は Web API モード経由では不可**。ファイル同期を WebDAV (pCloud 等) に設定しているため、api.zotero.org は本体 PDF を保持していない。画像ベースの処理が必要になったら `rclone mount pcloud:` 等で WebDAV を直接マウントする（spec Appendix A 参照）。
- 複数 PC に Zotero アプリを入れて `zotero.sqlite` を同時に書き込む構成は **DB 破損** の危険があるため禁止。Zotero.app は Mac のみ、他ホストは Web API モード専用。

### バージョンアップ時の同期手順

rtk が新版 (新しい hook 仕様等) を出した場合のみ:

```bash
# tmpdir で新版の rtk init -g を走らせて期待される設定を取得
TMPHOME=$(mktemp -d)
mkdir -p "$TMPHOME/.claude"
HOME="$TMPHOME" rtk init -g --auto-patch

# 出力された $TMPHOME/.claude/{settings.json,CLAUDE.md,RTK.md}
# と nanokit/claude/{settings.json,CLAUDE.md,RTK.md} を diff し、
# 必要な変更だけ手動で nanokit 側に反映してコミット → dotter deploy
diff -u "$TMPHOME/.claude/RTK.md" "$NANOKIT/claude/RTK.md"
```

### settings.json の反映モデル (symlink ではなく管理反映)

`~/.claude/settings.json` は **Claude Code 自身が所有する読み書きファイル**。UI での設定変更 (`/model` `/vim` 出力スタイル プラグイン有効化 など) やキー正規化のたびにアプリが atomic replace で書き戻すため、symlink にすると壊れる (実体ファイル化する)。よって dotter 管理せず、`agent-config-sync` (`codex/sync-config.py` の `settings_change()`) が **nanokit 原本の宣言キーを権威として live へマージ反映**する (Codex `config.toml` と同じ思想)。

- 原本が宣言するトップレベルキーは原本が勝つ。**live 側だけのアプリ由来キー (`hasCompletedOnboarding` 等) は保持**する (データ損失なし)。
- 反映は毎セッション `SessionStart` hook (`agent-config-sync-reconnect.sh`) が冪等に自己修復。実体ファイルがズレても次セッションで自動的に再マージされるので **手動復旧は不要**。
- 含意: アプリ内で管理キーを変えても次の同期で原本値に戻る。恒久化したい変更は **nanokit 原本の `settings.json` を編集**する (単一ソース)。

```bash
# 手動反映したいとき (通常は不要 — SessionStart で自動)
cd "$NANOKIT" && ./nanokit agent-config-sync        # --diff で事前確認可
```

## Scrapling MCP 運用 (Claude Code ⇄ Codex 共有)

`scrapling-mcp` は streamable-http サーバー (`http://127.0.0.1:8323/mcp`) として `~/.claude/scripts/scrapling-mcp-server.sh` 経由で常駐起動される。バイナリは pixi env (`~/nanokit/claude/mcp-servers/scrapling/`) 内、起動コマンドは `pixi run --manifest-path … mcp --http`。

**狙い**: stdio だと Claude Code と Codex がそれぞれ別プロセス (= Playwright/Chromium を二重に) 起動してしまう。HTTP 化して **1 プロセスを両クライアントが同一 URL で共有** する。zotero (`8321`) / workspace-personal (`8322`) と同じ常駐パターン。bind は `127.0.0.1` のみ、認証なし (ローカル専用)。

### ポート割り当て

| サーバー | ポート | ランチャ |
|---|---|---|
| zotero-mcp | `8321` | `zotero-mcp-server.sh` |
| workspace-mcp (personal) | `8322` | `workspace-mcp-personal-server.sh` |
| scrapling-mcp | `8323` | `scrapling-mcp-server.sh` |
| workspace-mcp (HDT) | `8324` | `workspace-mcp-hdt-server.sh` |

### クライアント登録 (どちらも dotter 管理外の state ファイル)

新ホストでは `dotter deploy` 後に **両方を手動で登録** する必要がある:

```bash
# Claude Code (~/.claude.json) — user scope の HTTP として登録
claude mcp add --transport http -s user scrapling http://127.0.0.1:8323/mcp

# Codex (~/.codex/config.toml) — [mcp_servers.scrapling] に url を追記
codex mcp add ...   # または config.toml に直接:
#   [mcp_servers.scrapling]
#   url = "http://127.0.0.1:8323/mcp"
```

起動自体は `settings.json` の SessionStart hook + `ECC_MCP_RECONNECT_SCRAPLING` が担当 (冪等: 既に healthy なら no-op)。

### トラブルシュート

```bash
# 現状確認
bash ~/.claude/scripts/scrapling-mcp-server.sh status
tail -20 ~/.claude/debug/scrapling-mcp.log

# 再起動
bash ~/.claude/scripts/scrapling-mcp-server.sh stop
bash ~/.claude/scripts/scrapling-mcp-server.sh start

# 接続確認 (両クライアント)
claude mcp list | grep scrapling      # → http://127.0.0.1:8323/mcp (HTTP) - ✓ Connected
codex mcp get scrapling               # → transport: streamable_http
```

ポート変更は `SCRAPLING_MCP_PORT` 環境変数で上書き可 (変更時は両クライアントの登録 URL も更新)。

## Google Workspace MCP 運用 (複数アカウント・全フォルダ直接)

個人アカウントのどのフォルダからも複数の Google アカウントへ直接届くよう、`workspace-mcp` を **アカウント別の常駐 HTTP シングルトン** として立て、**user スコープ**で登録する。

> **関連リポジトリ (責務分担)**: クライアント (HDT / OpenHeart / uSonar / Lagoon / personal …) ごとの振り分け — direnv `.envrc`・per-client `.mcp.json`・Team アカウントの `CLAUDE_CONFIG_DIR` 隔離 (`~/.claude-hdt`) — は別リポジトリ [`claude-settings`](https://github.com/DenDen047/claude-settings) (private) が担う。nanokit は **個人 `~/.claude` の共通基盤と、ここに挙げた常駐 MCP サーバ (プロセス) の実体**を提供する側。`claude-settings/setup-config-dirs.sh` は `~/.claude-hdt` を作る際に nanokit の `~/.claude/{settings.json,skills,scripts,CLAUDE.md,…}` を symlink するので、HDT の Claude アカウントも nanokit の基盤を継承する。全体像は [`ARCHITECTURE.md`](./ARCHITECTURE.md) の §3.3。

| サーバ名 | ポート | creds dir | Google アカウント | ツール接頭辞 |
|---|---|---|---|---|
| `workspace-personal` | `8322` | `personal` | `sh.mn.nat@gmail.com` (= frogiraffe) | `mcp__workspace-personal__*` |
| `workspace-hdt` | `8324` | `HDT` | `n.muramatsu@hyper-digitaltwins.com` | `mcp__workspace-hdt__*` |

**設計**: いずれも **ポータブルな OAuth creds (タイプA)** を使うため、HDT の **Claude アカウント (軸A, `CLAUDE_CONFIG_DIR=~/.claude-hdt`)** とは独立に HDT の Google データへ到達できる (越境スケジューリングの核心)。OAuth クライアントは両者共通 (`claude-google-oauth`)、creds dir と USER_GOOGLE_EMAIL だけが異なる。常駐は冪等シングルトン、並列 Claude で 1 プロセス共有 (zotero/scrapling と同じ)。

> `workspace` という名前は Claude Code の**予約名**なので使えない → 個人側は `workspace-personal`。

### クライアント登録 (dotter 管理外の state — 新ホストでは手動)

`dotter deploy` 後、`~/.claude.json` に user スコープで手動登録する (scrapling と同じ):

```bash
claude mcp add --transport http -s user workspace-personal http://127.0.0.1:8322/mcp
claude mcp add --transport http -s user workspace-hdt        http://127.0.0.1:8324/mcp
```

起動自体は `settings.json` の SessionStart hook + `ECC_MCP_RECONNECT_WORKSPACE_HDT` が担当 (冪等)。HDT は `CLAUDE_CONFIG_DIR=~/.claude-hdt` 配下の設定を読むため、この user スコープ登録は **個人アカウントのセッションにのみ**効く (HDT フォルダには波及しない)。

### トラブルシュート

```bash
bash ~/.claude/scripts/workspace-mcp-hdt-server.sh status
tail -20 ~/.claude/debug/workspace-mcp-hdt.log
claude mcp list | grep workspace        # → ✔ Connected を確認
# 接続アカウントの確認 (initialize が "Connected Google account: …" を返す)
curl -s -X POST http://127.0.0.1:8324/mcp -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"0"}}}'
```

HDT の OAuth トークンが失効したら creds dir (`~/.config/google-workspace-mcp/HDT`) を削除し、`workspace-mcp` の再認証フローを通す。

@RTK.md
