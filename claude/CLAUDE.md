# グローバル設定

## シンボリックリンク構造

このファイル (`~/.claude/CLAUDE.md`) は nanokit リポジトリから dotter によってシンボリックリンクされている。
編集元は `<nanokit>/claude/CLAUDE.md` であり、`~/.claude/` 配下の以下のファイルも同様:

| リポジトリ内パス | シンボリックリンク先 |
|---|---|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/scripts/zotero-mcp-server.sh` | `~/.claude/scripts/zotero-mcp-server.sh` |
| `claude/scripts/mmdc` | `~/.pixi/bin/mmdc` |
| `claude/ccstatusline/settings.json` | `~/.config/ccstatusline/settings.json` |
| `claude/skills/*` | `~/.claude/skills/*` |

したがって `~/.claude/` 配下のファイルを直接編集すると nanokit リポジトリのワーキングツリーが変更される。
設定を変更する場合は nanokit リポジトリ側で編集し `dotter deploy` で反映するのが正しいワークフロー。

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
