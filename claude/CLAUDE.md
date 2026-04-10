# グローバル設定

## 環境管理ポリシー

- **pixi-only**: シェルツールはすべて `pixi global` (conda-forge) で管理する。`brew`, `cargo install`, `pip install`, `go install` でツールを追加しない。
- `~/.zshenv` で `unsetopt GLOBAL_RCS` を設定しているため、`/etc/zprofile` の `path_helper` がスキップされ、`/opt/homebrew/bin` 等は PATH に含まれない。これは意図的な設計。

## ハマりポイント

- github.com にアクセスする際には、`gh`コマンドを利用する

## 参照すべき情報源

- CLAUDE.md を編集する時
  - https://code.claude.com/docs/en/best-practices
  - https://nyosegawa.com/posts/harness-engineering-best-practices-2026/
