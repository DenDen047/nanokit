---
name: notion-writing
description: >
  Guide for writing content to Notion pages via the mcp__notion__ MCP server.
  Covers block type selection (heading_1-3, paragraph, bulleted_list_item,
  to_do, callout, code, divider, bookmark), URL embedding as bookmark cards
  instead of raw text, the Task Description / Result / Notes page template
  with colored heading backgrounds, safe batch sizes for
  patch-block-children, and common failures including the intermittent
  "body.children should be an array" serialization error, delete-a-block
  permission denials for blocks the agent did not create, and update-a-block
  limitations. Use when adding or updating Notion pages via mcp__notion__,
  writing task or project templates, embedding URLs, or debugging Notion
  write failures.
user-invocable: true
---

# Notion MCP 書き込みガイド

Notion MCP (`mcp__notion__`) でページにコンテンツを作成・更新するときの実践知見。詳細は `reference/` 以下のファイルを参照する。

## Quick navigation

| やりたいこと | 参照 |
|---|---|
| どのブロックタイプを使うか / JSON の書き方 | [reference/block-types.md](reference/block-types.md) |
| URL を埋め込む（カード / iframe / リンク） | [reference/urls-and-bookmarks.md](reference/urls-and-bookmarks.md) |
| タスク / プロジェクトページの雛形 | [reference/task-template.md](reference/task-template.md) |
| エラーが出た / 権限拒否 / 再試行 | [reference/troubleshooting.md](reference/troubleshooting.md) |

## 最低限の原則

### 1. ブロックタイプは豊富に使える

MCP ツールスキーマには `paragraph` と `bulleted_list_item` しか明示されていないが、**実際には `heading_1/2/3/4` / `to_do` / `callout` / `code` / `divider` / `bookmark` / `embed` / `quote` / `numbered_list_item` すべてが通る**（本プロジェクトで実測済み）。セクション構造をつけるには `heading_*` と `divider` を積極的に使う。装飾（太字・斜体等）は `annotations` を渡しても無視されるため、`callout` や `heading` のような別ブロックで視覚的に区別する。

見出しには `color: "gray_background"` などの**背景色**を付けられる。Task Description / Result / Notes のセクション区切りに有効（[task-template.md](reference/task-template.md) 参照）。

### 2. URL は必ず `bookmark` ブロック

生の URL 文字列や `bulleted_list_item` 内のテキストリンクではなく、`bookmark` ブロックとしてカード形式で埋め込む。参考リンク集は `heading_2 "Related Links"` + `bookmark` 連続のパターンが基本形。詳細と例外（`embed` / `rich_text.link`）は [urls-and-bookmarks.md](reference/urls-and-bookmarks.md)。

### 3. タスクページは Task Description / Result / Notes の 3 パート

ユーザーの Tasks DB で確立しているパターン。冒頭に背景色付き `heading_1` で 3 セクションを立て、Notes 配下に `heading_2` で情報・To Do・Related Links を配置する。To Do は `heading_3` でフェーズ分け → `to_do` ブロック列挙。全体の雛形 JSON は [task-template.md](reference/task-template.md) に置いてある。

## API 操作の要点

### append: `mcp__notion__API-patch-block-children`

- `block_id`: ページ ID（ページ末尾に追加）または既存ブロック ID（そのブロック配下に追加）
- `children`: ブロック配列
- `after`: 既存ブロック ID の直後に挿入する場合

**バッチサイズは 20〜25 ブロック** が保守的に安全。30 超で `body.children should be an array` エラーが増える（[troubleshooting.md](reference/troubleshooting.md)）。

### read: `mcp__notion__API-get-block-children`

- `page_size`: 最大 100
- `has_more` が true なら `next_cursor` で次ページを取得
- **100 ブロック超のページはページネーション必須**

### delete: `mcp__notion__API-delete-a-block`

1 ブロックずつ。**エージェントが同一セッション内で作成したブロック以外は harness が削除を拒否する** 点に注意（Notion API の制約ではない）。削除に頼らず **append-only で設計** するのが基本。対処は [troubleshooting.md](reference/troubleshooting.md)。

### update: `mcp__notion__API-update-a-block`

MCP ツールのスキーマ都合で **ブロックタイプ変更は事実上不可**。大規模な修正は「新規作成 → 旧ブロック削除（可能なら）」のほうが確実。

## よくあるエラー

- **`body.children should be an array`** — MCP シリアライズの断続的失敗。同じ payload でリトライすれば通る。
- **`delete-a-block` Permission denied** — harness ポリシー。append-only 戦略で回避。
- **並列 `patch-block-children` の順序乱れ** — 同一ページに並列 append すると順序が保証されない。

詳細と対処は [troubleshooting.md](reference/troubleshooting.md)。

## その他の小ネタ

- **空行**: `{"type": "paragraph", "paragraph": {"rich_text": []}}`
- **Unicode**: エスケープ `\uXXXX` でもそのままの文字でも動作
- **レート制限**: 同一ワークスペースで並列数を 5-10 程度に抑える
- **ゴミ箱**: `delete-a-block` / `archived: true` はゴミ箱移動で完全削除ではない
