# Notion ブロックタイプ完全リファレンス

MCP ツール (`mcp__notion__API-patch-block-children`) のスキーマ定義では `paragraph` と `bulleted_list_item` しか明示されていないが、**実際には以下すべてのブロックタイプが通る**（本プロジェクトで実測済み）。

## Contents

- テキスト系
- 装飾系
- URL 埋め込み系（詳細は [urls-and-bookmarks.md](urls-and-bookmarks.md)）
- rich_text の書き方
- 見出しに背景色を付ける
- callout のアイコン早見
- code ブロックの `language` 値

## テキスト系

| タイプ | 用途 | JSON 例 |
|---|---|---|
| `heading_1` | 大見出し（H1） | `{"type": "heading_1", "heading_1": {"rich_text": [...]}}` |
| `heading_2` | 中見出し（H2） | `{"type": "heading_2", "heading_2": {"rich_text": [...]}}` |
| `heading_3` | 小見出し（H3） | `{"type": "heading_3", "heading_3": {"rich_text": [...]}}` |
| `heading_4` | 小見出し（H4） | `{"type": "heading_4", "heading_4": {"rich_text": [...]}}` |
| `paragraph` | 通常テキスト | `{"type": "paragraph", "paragraph": {"rich_text": [...]}}` |
| `bulleted_list_item` | 箇条書き | `{"type": "bulleted_list_item", "bulleted_list_item": {"rich_text": [...]}}` |
| `numbered_list_item` | 番号付きリスト | `{"type": "numbered_list_item", "numbered_list_item": {"rich_text": [...]}}` |
| `quote` | 引用 | `{"type": "quote", "quote": {"rich_text": [...]}}` |
| `to_do` | チェックボックス | `{"type": "to_do", "to_do": {"rich_text": [...], "checked": false}}` |

## 装飾系

| タイプ | 用途 | JSON 例 |
|---|---|---|
| `callout` | 注意・警告・ヒント | `{"type": "callout", "callout": {"rich_text": [...], "icon": {"type": "emoji", "emoji": "..."}}}` |
| `code` | コードブロック | `{"type": "code", "code": {"rich_text": [...], "language": "bash"}}` |
| `divider` | 区切り線 | `{"type": "divider", "divider": {}}` |

## URL 埋め込み系

| タイプ | 用途 |
|---|---|
| `bookmark` | URL プレビュー（推奨） |
| `embed` | iframe 埋め込み（YouTube 等は動画プレーヤー） |

詳細な使い分けは [urls-and-bookmarks.md](urls-and-bookmarks.md) 参照。

## rich_text の書き方

最小形:

```json
{"type": "text", "text": {"content": "テキスト内容"}}
```

> **注意**: MCP スキーマでは `richTextRequest` に `additionalProperties: false` が設定されており、`annotations`（bold, italic, code 等）を渡しても無視される可能性がある。装飾が必要な場合は Notion UI で手動調整するか、`callout` / `heading` / `code` 等のブロックタイプで視覚的に区別する。

## 見出しに背景色を付ける

`heading_1` / `heading_2` / `heading_3` は `color` プロパティで背景色を指定できる。Task Description / Result / Notes のようなセクション区切りに有効（[task-template.md](task-template.md) 参照）。

```json
{
  "type": "heading_1",
  "heading_1": {
    "rich_text": [{"type": "text", "text": {"content": "Task Description"}}],
    "color": "gray_background"
  }
}
```

使える背景色:

- `default`（デフォルト、背景なし）
- `gray_background`
- `brown_background`
- `orange_background`
- `yellow_background`
- `green_background`
- `blue_background`
- `purple_background`
- `pink_background`
- `red_background`

文字色のみは `_background` を外す（例: `"color": "red"`）。

## callout のアイコン早見

```json
{
  "type": "callout",
  "callout": {
    "rich_text": [{"type": "text", "text": {"content": "警告メッセージ"}}],
    "icon": {"type": "emoji", "emoji": "⚠️"}
  }
}
```

よく使うアイコン（Unicode エスケープ表記で記載、生の絵文字でも可）:

| エスケープ | 絵文字 | 用途 |
|---|---|---|
| `⚠️` | ⚠️ | 警告・注意 |
| `🚨` | 🚨 | 重大な警告 |
| `💡` | 💡 | ヒント・補足 |
| `📌` | 📌 | 重要メモ |
| `✅` | ✅ | 成功・完了 |
| `❌` | ❌ | 失敗・禁止 |

`color` プロパティも受け付ける（`gray_background` 等）。

## code ブロックの `language` 値

```json
{
  "type": "code",
  "code": {
    "rich_text": [{"type": "text", "text": {"content": "gocryptfs ~/.encrypted ~/Documents"}}],
    "language": "bash"
  }
}
```

複数行コマンドは `\n` で改行:

```json
{
  "type": "code",
  "code": {
    "rich_text": [{"type": "text", "text": {"content": "# マウント\ngocryptfs ~/.encrypted ~/Documents\n\n# アンマウント\nfusermount -u ~/Documents"}}],
    "language": "bash"
  }
}
```

主な `language` 値: `bash`, `shell`, `python`, `javascript`, `typescript`, `json`, `yaml`, `sql`, `markdown`, `html`, `css`, `rust`, `go`, `java`, `c`, `c++`, `plain text`.

## to_do ブロックの典型パターン

タスク管理系ページでは、`heading_3` でグループ化 → `to_do` を列挙する形が読みやすい。

```json
[
  {"type": "heading_3", "heading_3": {"rich_text": [{"type": "text", "text": {"content": "Preparation"}}]}},
  {"type": "to_do", "to_do": {"rich_text": [{"type": "text", "text": {"content": "パスポートの残存有効期限を確認"}}], "checked": false}},
  {"type": "to_do", "to_do": {"rich_text": [{"type": "text", "text": {"content": "宿泊ホテルの住所を確認"}}], "checked": false}}
]
```

詳しい使い方は [task-template.md](task-template.md) 参照。
