# URL 埋め込みリファレンス

URL を Notion に書き込むときは **必ず `bookmark` ブロックでカード形式のプレビューとして埋め込む**。生の URL 文字列を貼ったり、`rich_text` の `link` 属性でタイトル文字列に埋め込む形式は極力避ける。コンパクトにまとまり、一覧性・視認性が高いため。

## Contents

- 優先順位早見表
- `bookmark` の書き方（caption 付き含む）
- 参考リンク集パターン
- インライン `link_preview` mention が作れない理由
- 本文中の文脈リンク

## 優先順位早見表

| 方式 | 表示 | API で作成可能 | 採用 |
|---|---|---|---|
| **`bookmark` ブロック** | カード形式のプレビュー（アイコン・タイトル・説明・サムネイル） | OK | **これを使う** |
| `embed` ブロック | iframe 埋め込み（YouTube は動画プレーヤー） | OK | 動画/埋め込みコンテンツを展開したいときのみ |
| インライン `link_preview` mention | 箇条書き内に compact なプレビュー（アイコン + タイトル） | NG（read-only） | API から作成不可（後述） |
| `rich_text` に `link` 属性 | 普通のハイパーリンク | OK | 本文中の文脈リンクのみに限定 |
| 生の URL 文字列 | URL がそのまま表示される | OK | **使わない** |

## `bookmark` の書き方

最小形:

```json
{
  "type": "bookmark",
  "bookmark": {"url": "https://www.youtube.com/watch?v=G1MDYlbY-Ak"}
}
```

caption 付き:

```json
{
  "type": "bookmark",
  "bookmark": {
    "url": "https://www.youtube.com/watch?v=G1MDYlbY-Ak",
    "caption": [{"type": "text", "text": {"content": "Ollama で始めるローカル LLM"}}]
  }
}
```

## 参考リンク集パターン

`numbered_list_item` / `bulleted_list_item` に URL を並べるのではなく、**`bookmark` ブロックを連続させる**のが推奨。番号は失われるがカード形式で十分視認できる。

```json
[
  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "Related Links"}}]}},
  {"type": "bookmark", "bookmark": {"url": "https://www.youtube.com/watch?v=G1MDYlbY-Ak"}},
  {"type": "bookmark", "bookmark": {"url": "https://ollama.com"}},
  {"type": "bookmark", "bookmark": {"url": "https://zenn.dev/..."}}
]
```

## インライン `link_preview` mention が作れない理由

Notion UI で URL を貼って「メンション」を選ぶと、箇条書き内に compact なインラインプレビュー（YouTube アイコン + チャンネル名 + 動画タイトルが 1 行に収まる形式）が作れる。これは `link_preview` mention タイプで、Notion 公式 API ドキュメントでは **read-only** と明記されている:

> The `link_preview` block can only be returned as part of a response. The API does not support creating or appending `link_preview` blocks.

したがって **MCP 経由でこの形式は作れない**。どうしてもこの形式が必要なら、まず `bookmark` で埋め込んだ後にユーザーが Notion UI 上で「メンションに変換」する必要がある。通常は `bookmark` で視認性は十分確保できる。

## 本文中の文脈リンク

段落内の文中に URL を混ぜる場合（プレビューを出したくないケース）は、`rich_text` の `link` 属性を使う:

```json
{
  "type": "paragraph",
  "paragraph": {
    "rich_text": [
      {"type": "text", "text": {"content": "詳細は "}},
      {"type": "text", "text": {"content": "Ollama 公式", "link": {"url": "https://ollama.com"}}},
      {"type": "text", "text": {"content": " を参照。"}}
    ]
  }
}
```

この形式は本文の流れを崩さない場面に限定する。URL 一覧や参考リンク集では必ず `bookmark` を優先する。
