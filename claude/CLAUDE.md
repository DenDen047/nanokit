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
