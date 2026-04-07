---
name: notion-writing
description: >
  Notion MCP (mcp__notion__) でページにコンテンツを書き込むときのルール。
  ブロックタイプの使い分け（heading, code, callout, divider 等）、
  一括削除→再作成パターン、ページネーション、
  update-a-block の制約、コードブロックの書き方を参照する。
user-invocable: true
---

# Notion MCP 書き込みガイド

Notion MCP（`mcp__notion__`）経由でNotion ページにコンテンツを作成・更新する際の実践知見。

## ブロックタイプ一覧

MCP ツールのスキーマ定義では `paragraph` と `bulleted_list_item` しか記載されていないが、**実際には以下のブロックタイプがすべて動作する**。

### テキスト系

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

### 装飾系

| タイプ | 用途 | JSON 例 |
|---|---|---|
| `callout` | 注意・警告・ヒント | `{"type": "callout", "callout": {"rich_text": [...], "icon": {"type": "emoji", "emoji": "..."}}}` |
| `code` | コードブロック | `{"type": "code", "code": {"rich_text": [...], "language": "bash"}}` |
| `divider` | 区切り線 | `{"type": "divider", "divider": {}}` |

### rich_text の書き方

```json
{"type": "text", "text": {"content": "テキスト内容"}}
```

> **注意**: MCP スキーマでは `richTextRequest` に `additionalProperties: false` が
> 設定されており、`annotations`（bold, italic, code 等）を渡しても
> 無視される可能性がある。装飾が必要な場合は Notion UI で手動調整するか、
> callout / heading 等のブロックタイプで視覚的に区別する。

## コードブロック

シェルコマンドやコードスニペットは必ず `code` ブロックで囲む。
Notion でシンタックスハイライトが有効になり、ワンクリックでコピーできる。

```json
{
  "type": "code",
  "code": {
    "rich_text": [{"type": "text", "text": {"content": "gocryptfs ~/.encrypted ~/Documents"}}],
    "language": "bash"
  }
}
```

複数行コマンドは `\n` で改行する:

```json
{
  "type": "code",
  "code": {
    "rich_text": [{"type": "text", "text": {"content": "# マウント\ngocryptfs ~/.encrypted ~/Documents\n\n# アンマウント\nfusermount -u ~/Documents"}}],
    "language": "bash"
  }
}
```

主な `language` 値: `bash`, `python`, `javascript`, `typescript`, `json`, `yaml`, `sql`, `plain text`

## callout ブロック

重要な注意事項を目立たせるために使う。`icon` で絵文字を設定可能。

```json
{
  "type": "callout",
  "callout": {
    "rich_text": [{"type": "text", "text": {"content": "警告メッセージ"}}],
    "icon": {"type": "emoji", "emoji": "\u26a0\ufe0f"}
  }
}
```

よく使うアイコン:
- `\u26a0\ufe0f` — 警告・注意
- `\ud83d\udea8` — 重大な警告
- `\ud83d\udca1` — ヒント・補足

## ページ構造のベストプラクティス

### 階層構造

```
heading_1: 大章タイトル
  heading_2: 中節タイトル
    heading_3: 小節タイトル
      paragraph / bullet / code: 内容
divider
heading_1: 次の大章
```

- `heading_1` で大章を区切る（UI上で明確にサイズが異なり視認性が高い）
- `heading_2` で中節、`heading_3` で小節を作る
- 大章の間に `divider` を入れて視覚的に分離する

### コマンド付きドキュメントの構造

説明テキストとコマンドを分離し、コマンドは `code` ブロックにする:

```
heading_3: 手順タイトル
paragraph: 説明テキスト
code: コマンド（bash）
bulleted_list_item: 補足・注意事項
```

## API 操作パターン

### ブロックの追加（append）

`mcp__notion__API-patch-block-children` を使用。

- `block_id`: ページ ID を指定（ページ直下に追加）
- `children`: ブロックの配列（最大 100 ブロック/リクエスト）
- `after`: 既存ブロック ID の後に挿入する場合に指定

**1 回のリクエストで 20〜25 ブロック程度が安全**。大量のコンテンツは複数回に分ける。

### ブロックの取得（read）

`mcp__notion__API-get-block-children` を使用。

- `page_size`: 最大 100（デフォルト）
- `start_cursor`: 次ページ取得用。レスポンスの `next_cursor` を使う
- `has_more`: true の場合、次ページが存在する

> 100 ブロックを超えるページは **必ずページネーション** が必要。
> `has_more` を確認し、`next_cursor` で次のページを取得する。

### ブロックの削除

`mcp__notion__API-delete-a-block` は 1 ブロックずつ。
大量削除（50+）の場合は **Agent ツールで並列実行** するのが効率的:

```
Agent(
  description="Delete N Notion blocks",
  prompt="Delete these block IDs using mcp__notion__API-delete-a-block. Run in parallel. IDs:\n..."
)
```

### ブロックの更新（update）の制約

`mcp__notion__API-update-a-block` には重要な制約がある:

- `type` パラメータはオブジェクト型だが、Notion API は `heading_2` 等を
  **ボディのトップレベル** に期待する。MCP ツールは `type` キーの下に
  ネストしてしまうため、**ブロックタイプの変更はできない**
- `archived: true` でブロックを削除（ゴミ箱に移動）することは可能
- テキスト内容の更新も MCP 経由では制約がある

**結論: 大規模な修正は「全削除→再作成」パターンが最も確実。**

## 大規模更新の推奨ワークフロー

### 1. 現在のブロック ID を取得

```
get-block-children → bash で block ID とテキストの一覧を抽出
（ページネーションに注意）
```

### 2. 保持するブロックと削除するブロックを特定

クレデンシャル等の機密情報ブロックは保持し、コンテンツブロックを特定する。

### 3. Agent で一括削除

```
Agent で全 block ID を渡し、並列で delete-a-block を実行
```

### 4. patch-block-children で再作成

20〜25 ブロックずつバッチで append する。構造化されたブロックタイプを使う:

- `heading_2` / `heading_3` で見出し
- `divider` で章の区切り
- `code` でコマンド（`language: "bash"` 等）
- `callout` で重要な注意事項
- `paragraph` / `bulleted_list_item` で説明テキスト

## 注意事項

- **children パラメータ**: JSON 配列として渡す。文字列化されるとエラーになる
- **空の rich_text**: 空行を作るには `{"type": "paragraph", "paragraph": {"rich_text": []}}`
- **Unicode エスケープ**: 日本語テキストは Unicode エスケープ（`\uXXXX`）でも
  そのままの文字でも動作する
- **レート制限**: Notion API にはレート制限があるため、大量操作時は注意
- **ゴミ箱**: 削除したブロックはゴミ箱に移動される（完全削除ではない）
