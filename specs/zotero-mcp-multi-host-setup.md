# Zotero MCP マルチホスト対応: 実装方針

## 背景・目的

現在、`zotero-mcp` は Mac 上の Zotero アプリに依存するローカル HTTP サーバー（port 8321）として動作している。本作業では、**Mac 以外（Linux サーバー等）の Claude Code からも、同じ Zotero ライブラリを参照可能**にする。

### ユーザーの運用前提
- Zotero アカウントは **1 つ**（業務・研究すべてをこれ 1 つに集約）
- Zotero アプリは **Mac のみ**にインストール
- ファイル同期は **pCloud WebDAV** を利用中（`https://webdav.pcloud.com:443/zotero/`）
- "Sync full-text content" は **ON** → PDF のインデックス化済みテキストは Zotero クラウドに存在
- 添付ファイル実体は WebDAV 上に ZIP 形式で存在

### リポジトリ境界のポリシー
- **nanokit** = 共通インフラ（single-tenant）← **Zotero はここ**
- **claude-settings** = 組織別設定（multi-tenant、Slack/Notion などマルチテナントなもののみ）

Zotero は 1 アカウントで全用途をカバーするため、nanokit 側に配置する。

### 今回のスコープ確定

本作業では **「フルテキスト取得までを完成形」** とする。PDF バイナリ取得はスコープ外とし、実運用で不足が判明した時点で Appendix の選択肢から追加する。

---

## アーキテクチャ方針

### モード自動切替

| 実行環境 | モード | 取得可能なデータ |
|---|---|---|
| Mac（Zotero.app 起動中） | `ZOTERO_LOCAL=true` | メタデータ + PDF 本体 + 注釈作成可 |
| Mac（Zotero.app 停止中）/ Linux 他 | `ZOTERO_LOCAL=false` | メタデータ + フルテキスト（インデックス）+ ノート + タグ |

**判定ロジック**: `curl -sf -m 2 http://localhost:23119/connector/ping` の成否

### Web API モードで取れること / 取れないこと

`zotero-mcp`（54yyyu/zotero-mcp）の各ツールのリモート動作可否:

| ツール | Web API モード | 備考 |
|---|---|---|
| `zotero_search_*` | ◎ | メタデータ検索 |
| `zotero_get_item_metadata` | ◎ | |
| `zotero_get_notes` / `zotero_get_annotations` | ◎ | |
| `zotero_get_item_fulltext` | ◎ | `zot.fulltext_item()` で Zotero クラウドのインデックスから取得（full-text sync 必須） |
| `zotero_semantic_search` | ◎ | ChromaDB をリモート側で構築可能 |
| `zotero_create_annotation` | ✗ | ローカル Zotero (port 23119) 必須 |
| PDF 生バイト取得 | ✗ | `zot.dump()` は Zotero Storage 専用。**本ユーザーは pCloud WebDAV 運用のため、Web API モードでは PDF バイナリを取得不可**（→ Appendix A 参照） |

論文の読解・議論・引用・要約用途なら Web API モードで十分。

### WebDAV 運用下での PDF 可視性（補足）

Zotero の Web UI（zotero.org）に WebDAV 保管ファイルは表示されない（PDF プレビュー不可）。これは正常動作で、**フルテキストインデックスは Zotero クラウド側に独立して存在するため、zotero-mcp の `zotero_get_item_fulltext` は問題なく動作する**。

---

## パッケージ管理方針（pixi-only 準拠）

### 決定: 専用 pixi project として配置

`zotero-mcp` は conda-forge 非登録のため PyPI 取得。本家 54yyyu 版は PyPI 上で **`zotero-mcp-server`** という別名で公開されている（PyPI `zotero-mcp` は kujenga 氏の別プロジェクトで混同厳禁、→ 詳細は「参考情報」参照）。nanokit 内の既存 scrapling-mcp と同じパターン。

**配置**: `~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml`

```toml
[workspace]
name = "zotero-mcp"
channels = ["conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64"]

[dependencies]
python = ">=3.11,<3.13"

[pypi-dependencies]
# 本家 54yyyu/zotero-mcp の PyPI 配布名は "zotero-mcp-server"。
# [semantic] extras で ChromaDB + sentence-transformers + OpenAI/Gemini クライアントが入り、
# zotero_semantic_search が有効化される（大量ライブラリでの概念検索用）。
zotero-mcp-server = { version = ">=0.3.0", extras = ["semantic"] }

[tasks]
# CLI エントリポイント名は "zotero-mcp"（パッケージ名と異なる点に注意）
serve = "zotero-mcp serve --transport streamable-http --host localhost --port 8321"
version = "zotero-mcp version"
```

#### extras の選定理由（`[semantic]`）

| extras | 追加内容 | 本計画での採否 |
|---|---|---|
| （なし） | 検索・メタデータ・fulltext・notes・annotations・write ops | — |
| **`[semantic]`** | ChromaDB, sentence-transformers, openai, google-genai, tiktoken | ✅ **採用**。大量ライブラリを概念検索するため |
| `[pdf]` | PyMuPDF + ebooklib（PDF outline / EPUB 注釈） | 将来 PDF バイナリ取得を始めるときに追加検討 |
| `[scite]` | requests（Scite 引用強度） | 必要になったら追加 |
| `[all]` | 上記すべて | pixi env サイズが大きくなる割に `[semantic]` 以上のメリットは用途次第 |

`[semantic]` により pixi env サイズは数百 MB 増える（主に `sentence-transformers` のモデル関連依存）。`zotero_semantic_search` 初回実行時にさらに embedding モデルがダウンロードされる（デフォルトは `all-MiniLM-L6-v2`、約 80 MB）。

### この方針のメリット

| 観点 | `uv tool install`（旧計画） | **pixi project（本計画）** |
|---|---|---|
| pixi-only ポリシー | ❌ 例外扱い | ✅ 準拠 |
| `uv` の別途インストール | 必要 | 不要 |
| ロックファイル | uv.lock 非追跡 | `pixi.lock` を git で管理 |
| バージョン固定 | install 時のみ | lock で厳密固定 |
| cross-platform | `~/.local/bin` の PATH 汚染 | 環境内完結 |
| 既存 scrapling-mcp との統一 | — | ✅ 同一フロー |
| semantic search extras | 手動管理 | pixi.toml に宣言して lock に反映 |

---

## 実装タスク

### Phase 1: nanokit 側 — secret 基盤の新設

**1.1 `~/nanokit/lib/secret.sh` を新規作成**

claude-settings の `lib/secret.sh` を **API 互換のままそのまま移設**する。以下の機能を維持:

- OS 自動検出:
  - macOS → `security find-generic-password` (Keychain)
  - Linux (GUI) → `secret-tool lookup` (GNOME Keyring)
  - fallback → `$HOME/.config/nanokit/secrets.env`
- 公開 API:
  - `get_secret <service> <account>` — 値を stdout に返す（見つからなければ空文字 + exit 0）
  - `store_secret <service> <account> <value>`
  - `has_secret <service> <account>` — 存在チェック
- env-file バックエンドのキー形式: `SERVICE__ACCOUNT`（ハイフン/ドットはアンダースコアに変換、大文字化）

参考元ファイル: `~/Documents/Projects/claude-settings/lib/secret.sh`（150 行）

**1.2 fallback パスの変更メモ**

env-file パスは claude-settings の `~/.config/claude-settings/secrets.env` から `~/.config/nanokit/secrets.env` に変更。Mac（Keychain）/ Linux GUI（secret-tool）ユーザーには影響なし。env-file fallback を使う Linux サーバー環境では新規登録が必要（旧パスからの手動移行で対応可）。

**1.3 dotter での公開は不要**

`lib/secret.sh` は nanokit リポジトリ内のスクリプトからのみ参照されるため、`~/.claude/` 等へのシンボリックリンク作成は **不要**。将来必要になった場合のみ `.dotter/global.toml` に追記する。

---

### Phase 2: zotero-mcp pixi project の新設

**2.1 `~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml` を新規作成**

「パッケージ管理方針」セクションの toml をそのまま配置。

**2.2 `pixi install` で lockfile を生成し git にコミット**

```bash
pixi install --manifest-path ~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml
```

→ `pixi.lock` が同ディレクトリに生成される（コミット対象）。

**2.3 `~/.local/bin/zotero-mcp` (uv tool) は最終的に不要**

旧インストールの掃除は Phase 5.1 で実施。動作確認まで残しても害はないので並行稼動 → 切り替え完了後に撤去。

---

### Phase 3: nanokit コマンドへのサブコマンド追加

**3.1 `~/nanokit/nanokit` に以下を追加**

- `show_help()` のコマンド一覧に下記 3 行を追加:
  ```
  zotero-mcp-install    📚 Install zotero-mcp pixi env and register Zotero Web API credentials
  zotero-mcp-update     🔄 Update zotero-mcp to latest git HEAD
  zotero-mcp-uninstall  🧹 Remove zotero-mcp env and credentials
  ```

- `zotero_mcp_install()` 関数を新規実装:
  1. `pixi install --manifest-path "$NANOKIT_ROOT/claude/mcp-servers/zotero-mcp/pixi.toml"`
  2. `. "$NANOKIT_ROOT/lib/secret.sh"` で secret lib を読み込み
  3. 以下の案内を表示:
     ```
     📋 Zotero API Key 取得手順:
        URL: https://www.zotero.org/settings/keys/new

        推奨パーミッション:
          [x] Personal Library:  Allow library access
          [x] Personal Library:  Allow notes access
          [ ] Personal Library:  Allow write access  (読み取り専用なら OFF 推奨)
          [ ] Personal Library:  Allow file access   (将来 PDF バイナリ取得が必要になったとき ON)
          [ ] Default Group Permissions: Read Only  (Group ライブラリがあれば)

     📋 Library ID (userID):
        URL: https://www.zotero.org/settings/keys
        → ページ上部 "Your userID for use in API calls is XXXXXXX" の数字
     ```
     > 「Allow file access」を発行時点で ON にしておくと、将来 Zotero Storage 移行時にキー再発行が不要。WebDAV 運用のままでは無効化だが無害。
  4. `has_secret "claude-zotero" "api-key"` が false なら対話的に入力を受けて `store_secret`
  5. `has_secret "claude-zotero" "library-id"` も同様
  6. 最後に `bash ~/.claude/scripts/zotero-mcp-server.sh start` を呼んでヘルスチェック

- `zotero_mcp_update()`:
  ```bash
  pixi update --manifest-path "$NANOKIT_ROOT/claude/mcp-servers/zotero-mcp/pixi.toml"
  ```
- `zotero_mcp_uninstall()`:
  - `.pixi/envs/` 配下を削除（`rm -rf "$NANOKIT_ROOT/claude/mcp-servers/zotero-mcp/.pixi"`）
  - 対話で credentials 削除確認（`security delete-generic-password` / `secret-tool clear` / env-file 行削除）

- `main()` の case 文に 3 つのルーティングを追加

---

### Phase 4: zotero-mcp-server.sh のモード分岐実装

**4.1 `~/nanokit/claude/scripts/zotero-mcp-server.sh` を改修**

**① nanokit root と secret lib の読み込み**

macOS の BSD `readlink` は `-f` 非対応版があるため、POSIX-portable な symlink 解決関数を使う:

```bash
# POSIX-portable symlink resolver (BSD/GNU 両対応)
_resolve_link() {
  local p="$1"
  while [[ -L "$p" ]]; do
    local l
    l="$(readlink "$p")"
    [[ "$l" = /* ]] && p="$l" || p="$(dirname "$p")/$l"
  done
  echo "$p"
}

NANOKIT_ROOT="$(cd "$(dirname "$(_resolve_link "$0")")/../.." && pwd)"
[[ -f "$NANOKIT_ROOT/lib/secret.sh" ]] && . "$NANOKIT_ROOT/lib/secret.sh"
```

**② バイナリ呼び出しの変更**

既存の `BINARY="${ZOTERO_MCP_BINARY:-$HOME/.local/bin/zotero-mcp}"` を pixi project 呼び出しに置換:

```bash
ZOTERO_MCP_MANIFEST="$NANOKIT_ROOT/claude/mcp-servers/zotero-mcp/pixi.toml"
BINARY_CMD=(pixi run --manifest-path "$ZOTERO_MCP_MANIFEST" zotero-mcp)
```

**③ モード判定と環境変数注入**

```bash
detect_zotero_mode() {
  if curl -sf -m 2 -o /dev/null "http://localhost:23119/connector/ping" 2>/dev/null; then
    echo "local"
  else
    echo "web"
  fi
}
```

`cmd_start()` 内の起動コマンドを以下に置換:

```bash
local mode
mode=$(detect_zotero_mode)
echo "zotero-mcp starting in mode=$mode" >> "$LOG_FILE"

if [[ "$mode" == "local" ]]; then
  ZOTERO_LOCAL=true nohup "${BINARY_CMD[@]}" serve \
    --transport streamable-http --host "$HOST" --port "$PORT" \
    >> "$LOG_FILE" 2>&1 &
else
  # Web API モード: secret lib から credentials を注入
  local api_key library_id
  api_key=$(get_secret "claude-zotero" "api-key")
  library_id=$(get_secret "claude-zotero" "library-id")

  if [[ -z "$api_key" || -z "$library_id" ]]; then
    echo "ERROR: Zotero API credentials not registered." >&2
    echo "Run: nanokit zotero-mcp-install" >&2
    exit 1
  fi

  ZOTERO_LOCAL=false \
  ZOTERO_API_KEY="$api_key" \
  ZOTERO_LIBRARY_ID="$library_id" \
  ZOTERO_LIBRARY_TYPE="user" \
    nohup "${BINARY_CMD[@]}" serve \
      --transport streamable-http --host "$HOST" --port "$PORT" \
      >> "$LOG_FILE" 2>&1 &
fi
echo $! > "$PID_FILE"
```

---

### Phase 5: 旧インストールのクリーンアップと claude-settings 側の整理

**5.1 旧 uv tool インストールの撤去（動作確認後）**

```bash
uv tool uninstall zotero-mcp  # 存在すれば
rm -f ~/.local/bin/zotero-mcp # uv 以外で symlink されていた場合
```

**5.2 claude-settings 側の状況確認**

grep 結果（`rg -i zotero ~/Documents/Projects/claude-settings`）:
- `setup-secrets.sh` に `claude-zotero` の `register_secret` は **存在しない**
- `.envrc.defaults` に `ZOTERO_API_KEY` の export は **存在しない**
- `README.md` / `shared-mcp-http/SKILL.md` に **zotero の記述が残っている**（HTTP サーバー共有パターンの例として）

→ 削除対象は **README と shared-mcp-http skill の記述のみ**。シークレット／環境変数の移設は不要（そもそも入っていない）。

**5.3 claude-settings 側で削除する記述**

- `~/Documents/Projects/claude-settings/README.md`
  - L66 付近の zotero 関連行
  - L402: `User MCPs` 表の "zotero 等" の記述
  - L524–541: 「Zotero MCP の運用」セクション丸ごと
- `~/Documents/Projects/claude-settings/.claude/skills/shared-mcp-http/SKILL.md`
  - L11, L271, L276–280: zotero を例示している行／ブロック

受入基準の `rg -i zotero ~/Documents/Projects/claude-settings` が 0 件になることを確認。

**5.4 Keychain に登録済みの場合**

既に `claude-zotero` を Keychain/secret-tool に登録済みなら、nanokit 側の secret lib からそのまま参照できる（service/account が同じキーなら OS ストアを共有）。再登録は不要。

---

### Phase 6: ドキュメント更新

**6.1 `~/nanokit/claude/CLAUDE.md`**
- 「シンボリックリンク構造」表への変更は不要（`lib/secret.sh` も `claude/mcp-servers/zotero-mcp/` も非 symlink）
- 下部に「Zotero MCP 運用」セクションを追記:
  - モード切替の仕組み（local / web）
  - WebDAV 運用下では PDF バイナリ取得不可、フルテキストは取得可（Appendix 参照）
  - トラブルシュート（ログ確認、credentials 再登録）

**6.2 `~/nanokit/README.md`**
- Commands 一覧に `zotero-mcp-install` を追記
- 使用例として「新規マシンセットアップ後、`nanokit zotero-mcp-install` で API キー登録」を記載

---

## 受入基準 (Done Criteria)

- [ ] `~/nanokit/lib/secret.sh` が存在し、`get_secret` / `store_secret` / `has_secret` が動作する
- [ ] `~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml` と `pixi.lock` が存在
- [ ] `pixi run --manifest-path <...>/pixi.toml zotero-mcp version` が成功
- [ ] `zotero-mcp-server[semantic]` が解決され、`chromadb` / `sentence-transformers` が env に含まれる
- [ ] リモートから `mcp__zotero__zotero_semantic_search` がエラーなく応答する（初回は embedding DB 構築が必要）
- [ ] `nanokit zotero-mcp-install` を新規マシンで実行 → pixi env 構築 + API キー登録まで対話的に完了
- [ ] Mac で Zotero アプリ起動中 → `zotero-mcp-server.sh start` のログに `mode=local` が出る
- [ ] Mac で Zotero アプリ停止 → 同コマンドが自動で `mode=web` に切替
- [ ] Linux サーバーで同コマンド実行 → `mode=web` で起動、`ZOTERO_API_KEY` が Keychain/secret-tool から注入される
- [ ] リモートから `mcp__zotero__zotero_search_items` / `zotero_get_item_fulltext` / `zotero_get_notes` が非空で返る
- [ ] `~/.local/bin/zotero-mcp`（旧 uv tool）が撤去されている
- [ ] claude-settings から Zotero 関連記述が消えている（`rg -i zotero ~/Documents/Projects/claude-settings` で 0 件）

---

## テスト方法

### ユニット
```bash
# secret lib
. ~/nanokit/lib/secret.sh
store_secret test-ns foo bar
[[ "$(get_secret test-ns foo)" == "bar" ]] && echo OK

# pixi env
pixi run --manifest-path ~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml zotero-mcp version
```

### 統合（Mac）
```bash
# Zotero 停止状態で検出
pkill -x Zotero; sleep 2
~/.claude/scripts/zotero-mcp-server.sh stop
~/.claude/scripts/zotero-mcp-server.sh start
tail ~/.claude/debug/zotero-mcp.log | grep "mode=web"
```

### E2E（リモート）
1. Linux サーバーで `nanokit install` → `nanokit zotero-mcp-install` を実行して API キー登録
2. Claude Code セッションを開始
3. `mcp__zotero__zotero_search_items` で既知の論文タイトルを検索 → ヒット確認
4. `mcp__zotero__zotero_get_item_fulltext` で PDF の本文テキストが返ることを確認
5. `mcp__zotero__zotero_update_search_database` で semantic index を構築（初回のみ、数分〜数十分）
6. `mcp__zotero__zotero_semantic_search` で概念クエリ（例: "scene reconstruction with diffusion models"）を投げ、関連論文が返ることを確認

---

## 参考情報

### 現在の nanokit Zotero 関連ファイル
- `~/nanokit/claude/scripts/zotero-mcp-server.sh` — HTTP サーバーライフサイクル管理（今回改修対象）
- `~/nanokit/claude/settings.json` — SessionStart フック + `ECC_MCP_RECONNECT_ZOTERO` env で起動
- （新規）`~/nanokit/claude/mcp-servers/zotero-mcp/pixi.toml` — pixi project 定義
- （新規）`~/nanokit/lib/secret.sh` — OS 非依存 secret 取得 lib

### zotero-mcp の仕様メモ
- リポジトリ: https://github.com/54yyyu/zotero-mcp
- **PyPI 配布名**: `zotero-mcp-server`（v0.3.0+、作者 54yyyu）。**CLI エントリポイント名は `zotero-mcp`**。
- **PyPI の `zotero-mcp`（同名・別プロジェクト）は kujenga/zotero-mcp（作者 Aaron Taylor）で、機能は search/metadata/fulltext の 3 ツールのみ。混同しないこと。**
- バイナリ: pixi env 内（`pixi run --manifest-path ... zotero-mcp`）
- 起動: `serve --transport streamable-http --host localhost --port 8321`
- ドキュメント: https://stevenyuyy.com/zotero-mcp/

### 54yyyu vs kujenga 比較（選定根拠）

| 項目 | **54yyyu/zotero-mcp**（採用） | kujenga/zotero-mcp |
|---|---|---|
| PyPI 名 | `zotero-mcp-server` | `zotero-mcp` |
| GitHub stars | 2,584 | 145 |
| ツール数 | 約 20（notes/annotations/collections/semantic search/write ops 等） | 3（search / metadata / fulltext のみ） |
| semantic search | ✅ | ❌ |
| 本ユーザーの運用（大量コレクション + 概念検索）との適合 | ✅ | ❌（コレクション構造を読めない） |

### Zotero API キー取得
- 発行: https://www.zotero.org/settings/keys/new
- userID 確認: https://www.zotero.org/settings/keys
- Web API v3 docs: https://www.zotero.org/support/dev/web_api/v3/start

### 重要な制約
- pCloud の WebDAV は旧プランのみ利用可（新規プランでは廃止）。現ユーザーは旧プランで利用中
- WebDAV 同期中は `zotero_get_item_fulltext` の結果がアイテムによってブレる可能性あり（full-text index が未同期の場合）
- Zotero アプリと `zotero.sqlite` を同時に書き込む構成（複数 PC に Zotero アプリをインストールしてローカル DB 同期する運用）は絶対に避けること（DB 破損）

---

## Appendix A: PDF バイナリ取得が必要になった場合の選択肢

本計画のスコープ外。実運用でフルテキストでは不足と判明したときに検討する。

### 判断基準

以下が出てきたら PDF バイナリ取得の検討タイミング:
- 図表や数式を画像として MLLM に渡したい
- PDF に直接注釈を書き戻したい
- `zotero_get_item_fulltext` が空を返すアイテムが多い（= full-text インデックス未同期）

### 選択肢

| 案 | 手間 | コスト | 実装影響 | 備考 |
|---|---|---|---|---|
| **pCloud を rclone でマウント** | 中 | 現 pCloud 契約のみ | nanokit 変更ゼロ | `rclone` は既に `pixi-global.toml` に入っている。必要ホストで `rclone config` → `rclone mount pcloud: ~/pcloud` → Zotero の WebDAV 配下 ZIP を直接展開 |
| **Zotero Storage に移行**（WebDAV 撤去） | 小 | $20/yr 〜（容量次第） | 設定変更のみ、コード変更不要 | `zot.dump()` がそのまま効くようになる。API キーに "Allow file access" があれば即利用可（→ Phase 3.1 の推奨パーミッションで事前 ON 推奨） |
| **Mac を PDF 配信ゲートウェイ化** | 大 | $0 | 新規スクリプト必要 | Mac 上で PDF 提供 HTTP を立てる。Mac が常時起動している必要あり。Tailscale 等 VPN 併用推奨 |

### 推奨優先順位

1. rclone マウント（最小追加コスト、現構成を変えない）
2. 頻度高くなってきたら Zotero Storage 移行を検討
3. ゲートウェイ化はメンテ負荷が大きいため最終手段
