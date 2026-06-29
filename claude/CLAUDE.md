# グローバル設定

## シンボリックリンク構造

このファイル (`~/.claude/CLAUDE.md`) は nanokit リポジトリから dotter によってシンボリックリンクされている。
編集元は `<nanokit>/claude/CLAUDE.md` であり、`~/.claude/` 配下の以下のファイルも同様:

| リポジトリ内パス | シンボリックリンク先 |
|---|---|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/scripts/zotero-mcp-server.sh` | `~/.claude/scripts/zotero-mcp-server.sh` |
| `claude/scripts/scrapling-mcp-server.sh` | `~/.claude/scripts/scrapling-mcp-server.sh` |
| `claude/scripts/workspace-mcp-hdt-server.sh` | `~/.claude/scripts/workspace-mcp-hdt-server.sh` |
| `claude/scripts/vision-reminder.sh` | `~/.claude/scripts/vision-reminder.sh` |
| `claude/scripts/memory-extract-reminder.sh` | `~/.claude/scripts/memory-extract-reminder.sh` |
| `claude/scripts/mmdc` | `~/.pixi/bin/mmdc` |
| `claude/ccstatusline/settings.json` | `~/.config/ccstatusline/settings.json` |
| `claude/skills/*` | `~/.claude/skills/*` |

したがって `~/.claude/` 配下のファイルを直接編集すると nanokit リポジトリのワーキングツリーが変更される。
設定を変更する場合は nanokit リポジトリ側で編集し `dotter deploy` で反映するのが正しいワークフロー。

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

ユーザーの好み・背景・作業スタイルを**能動的に収集し、全プロジェクトの回答に反映する**。3 層で管理:

- **グローバル個人メモリ** `~/.claude/memory/personal/` — 全プロジェクト共通の恒久的事実。下の `@import` で全セッションに読み込まれる。新しい恒久事実は 1 ファイル 1 事実で追記し `MEMORY.md` にポインタを足す。
- **プロジェクト固有メモリ** 各プロジェクトの `memory/`（ネイティブ auto-memory が自動追記）。
- **確定した好みの昇格**は人手で CLAUDE.md へ（スクリプトは自動編集しない）。

セッション終了時に `Stop` hook (`memory-extract-reminder.sh`) が恒久的な好み/事実の保存を促す（非ブロッキング・2h クールダウン）。

@~/.claude/memory/personal/MEMORY.md

## 環境管理ポリシー

- **pixi-only**: シェルツールはすべて `pixi global` (conda-forge) で管理する。`brew`, `cargo install`, `pip install`, `go install` でツールを追加しない。
- `~/.zshenv` で `unsetopt GLOBAL_RCS` を設定しているため、`/etc/zprofile` の `path_helper` がスキップされ、`/opt/homebrew/bin` 等は PATH に含まれない。これは意図的な設計。

## ハマりポイント

- github.com にアクセスする際には、`gh`コマンドを利用する

## 参照すべき情報源

- CLAUDE.md を編集する時
  - https://code.claude.com/docs/en/best-practices
  - https://nyosegawa.com/posts/harness-engineering-best-practices-2026/

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

### symlink 破壊からの復旧

万一 `~/.claude/settings.json` が通常ファイル化していたら:

```bash
# 1. ~/.claude 側の最新内容を nanokit に取り込み (通常ファイル → リポジトリへ)
cp ~/.claude/settings.json "$NANOKIT/claude/settings.json"
# 2. 通常ファイルを削除して dotter で symlink を回復
rm ~/.claude/settings.json
cd "$NANOKIT" && dotter deploy
# 3. 検証
readlink ~/.claude/settings.json   # → $NANOKIT/claude/settings.json が出れば OK
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
