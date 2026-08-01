# MCP 運用 runbook (Zotero / Scrapling / Workspace)

常駐 HTTP シングルトン MCP の起動・登録・認証・トラブルシュートの詳細。
原則は `claude/CLAUDE.md` の「MCP 運用」節にあり、ここは構成表と故障時に開く手順書。

いずれも Claude Code と Codex が 1 プロセスを共有する常駐 HTTP サーバ。bind は `127.0.0.1`
のみ、認証なし (ローカル専用)。起動は `settings.json` の SessionStart hook +
`ECC_MCP_RECONNECT_*` が冪等に担当 (既に healthy なら no-op)。

| サーバ | ポート | ランチャ (`~/.claude/scripts/`) | 用途 |
|---|---|---|---|
| zotero-mcp | 8321 | `zotero-mcp-server.sh` | 文献。local/web 自動切替 |
| workspace-personal | 8322 | `workspace-mcp-personal-server.sh` | 個人 Google (`sh.mn.nat@gmail.com`) |
| scrapling-mcp | 8323 | `scrapling-mcp-server.sh` | ブラウザ取得 (Playwright) |
| workspace-hdt | 8324 | `workspace-mcp-hdt-server.sh` | HDT Google (ポータブル OAuth) |

### 登録先の振り分け

新ホストでは `dotter deploy` 後に HTTP MCP を手動登録する (`~/.claude.json` /
`~/.codex/config.toml` は dotter 管理外の state)。登録先はサービスで分ける。

- **`scrapling` / `zotero` / `deepwiki`** — `agent-config-sync` が両 CLI (Claude / Codex の user scope) へ登録する。
- **`workspace-*`** — Claude 個人アカウントの user scope のみ。Codex user scope へは入れない (認証境界は claude-settings の project adapter が維持する)。

---

## Zotero MCP

ホスト横断で 1 つの Zotero ライブラリを参照する。バイナリは pixi env
(`~/nanokit/claude/mcp-servers/zotero-mcp/`) 内。

### モードの自動切替

判定は `detect_zotero_mode()` が担当。ログ先頭に `mode=local` / `mode=web` が記録される。

- **`mode=local`** (Zotero.app 起動中) — `curl http://localhost:23119/connector/ping` が
  通ったとき。`ZOTERO_LOCAL=true` で起動。メタデータ + PDF 本体 + 注釈作成が可能。
- **`mode=web`** (Zotero.app なし or Linux サーバー) — 上記が通らないとき。
  `ZOTERO_LOCAL=false` + `ZOTERO_API_KEY` + `ZOTERO_LIBRARY_ID` で起動。メタデータ +
  フルテキスト (Zotero クラウドの索引) + ノート + タグ + semantic search が可能。
  PDF バイナリは取得不可 (WebDAV 運用のため)。

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

- **PDF バイナリ取得は Web API モード経由では不可**。ファイル同期を WebDAV (pCloud 等) に
  設定しているため、api.zotero.org は本体 PDF を保持していない。画像ベースの処理が必要に
  なったら `rclone mount pcloud:` 等で WebDAV を直接マウントする
  ([`zotero-mcp-multi-host-setup.md`](zotero-mcp-multi-host-setup.md) 参照)。
- 複数 PC に Zotero アプリを入れて `zotero.sqlite` を同時に書き込む構成は **DB 破損** の
  危険があるため禁止。Zotero.app は Mac のみ、他ホストは Web API モード専用。

---

## Scrapling MCP (Claude Code ⇄ Codex 共有)

`scrapling-mcp` は streamable-http サーバー (`http://127.0.0.1:8323/mcp`)。バイナリは
pixi env (`~/nanokit/claude/mcp-servers/scrapling/`) 内、起動は `pixi run --manifest-path … mcp --http`。

**狙い**: stdio だと Claude Code と Codex がそれぞれ Playwright/Chromium を二重に起動する。
HTTP 化して 1 プロセスを両クライアントが同一 URL で共有する。

### クライアント登録 (dotter 管理外の state ファイル)

新ホストでは `dotter deploy` 後に **両方を手動で登録** する:

```bash
# Claude Code (~/.claude.json) — user scope の HTTP として登録
claude mcp add --transport http -s user scrapling http://127.0.0.1:8323/mcp

# Codex (~/.codex/config.toml) — [mcp_servers.scrapling] に url を追記
codex mcp add ...   # または config.toml に直接:
#   [mcp_servers.scrapling]
#   url = "http://127.0.0.1:8323/mcp"
```

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

ポート変更は `SCRAPLING_MCP_PORT` で上書き可 (変更時は両クライアントの登録 URL も更新)。

---

## Google Workspace MCP (複数アカウント・全フォルダ直接)

個人アカウントのどのフォルダからも複数の Google アカウントへ直接届くよう、`workspace-mcp` を
**アカウント別の常駐 HTTP シングルトン** として立て、**user スコープ**で登録する。

| サーバ名 | ポート | creds dir | Google アカウント | ツール接頭辞 |
|---|---|---|---|---|
| `workspace-personal` | 8322 | `personal` | `sh.mn.nat@gmail.com` (= frogiraffe) | `mcp__workspace-personal__*` |
| `workspace-hdt` | 8324 | `HDT` | `n.muramatsu@hyper-digitaltwins.com` | `mcp__workspace-hdt__*` |

**設計**: いずれも **ポータブルな OAuth creds (タイプA)** を使うため、HDT の Claude アカウント
(軸A, `CLAUDE_CONFIG_DIR=~/.claude-hdt`) とは独立に HDT の Google データへ到達できる (越境
スケジューリングの核心)。OAuth クライアントは両者共通 (`claude-google-oauth`)、creds dir と
USER_GOOGLE_EMAIL だけが異なる。`workspace` は Claude Code の予約名なので個人側は
`workspace-personal`。

**責務分担**: クライアント (HDT / OpenHeart / uSonar / Lagoon / personal …) ごとの振り分け —
direnv `.envrc`・per-client `.mcp.json`・Team アカウントの `CLAUDE_CONFIG_DIR` 隔離
(`~/.claude-hdt`) — は別リポジトリ [`claude-settings`](https://github.com/DenDen047/claude-settings)
(private) が担う。nanokit は個人 `~/.claude` の共通基盤と常駐 MCP サーバの実体を提供する側。
`claude-settings/setup-config-dirs.sh` は `~/.claude-hdt` を作る際に nanokit の
`~/.claude/{settings.json,skills,scripts,CLAUDE.md,…}` を symlink するので、HDT の Claude
アカウントも nanokit の基盤を継承する。

### クライアント登録 (dotter 管理外の state — 新ホストでは手動)

`dotter deploy` 後、`~/.claude.json` に user スコープで手動登録する (scrapling と同じ):

```bash
claude mcp add --transport http -s user workspace-personal http://127.0.0.1:8322/mcp
claude mcp add --transport http -s user workspace-hdt        http://127.0.0.1:8324/mcp
```

この user スコープ登録は **個人アカウントのセッションにのみ**効く (HDT フォルダには波及しない)。
HDT は `CLAUDE_CONFIG_DIR=~/.claude-hdt` 配下の設定を読むため。

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

HDT の OAuth トークンが失効したら creds dir (`~/.config/google-workspace-mcp/HDT`) を削除し、
`workspace-mcp` の再認証フローを通す。
