# タスク / プロジェクトページ テンプレート

ユーザーが Notion Tasks DB で使っているタスク/プロジェクトページの標準構造。**Task Description → Result → Notes → Related Links** の 4 パートで、見出しに背景色を付けてセクションを強調する。本セッション (CVPR 2026 タスク群) で実測した、そのまま動く形。

## Contents

- 全体構造
- 各セクションの書き方
- JSON テンプレート (最小形)
- 実例 (抜粋)
- バリエーション

## 全体構造

```
heading_1 "Task Description" [gray_background]
  paragraph: タスクの目的を 1-2 文で
heading_1 "Result"           [red_background]
  callout (💡): 完了後にここに何を記録するかの placeholder
heading_1 "Notes"            [blue_background]
  heading_2 "<セクション名>"
    bulleted_list_item × N: 事実・仕様・補足
  heading_2 "To Do"
    heading_3 "<フェーズ名>"
      to_do × N
    heading_3 "<フェーズ名>"
      to_do × N
  heading_2 "Related Links"
    bookmark × N
```

## 各セクションの書き方

### Task Description (gray_background)

そのタスクが何で、なぜやるかを 1-2 文で書く。長い背景や仕様は Notes に送る。

### Result (red_background) + callout

完了時に埋めるべき情報のプレースホルダを callout で置く。例: 予約確認番号 / Registration ID / 提出ファイルのリンク / コスト / 気付いた異常など。

### Notes (blue_background)

セクションを `heading_2` で作り、中身を bullets・to_do・さらなる heading_3 で構成する。

- **情報セクション** (`<Task名> Info` など): `bulleted_list_item` で仕様・締切・相場等をリストアップ
- **To Do**: `heading_3` でフェーズ分割 (例: Before Registration / Registration / After) → `to_do` を列挙
- **Related Links**: 必ず末尾、`bookmark` を連続させる

## JSON テンプレート (最小形)

```json
[
  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Task Description"}}], "color": "gray_background"}},
  {"type": "paragraph", "paragraph": {"rich_text": [{"type": "text", "text": {"content": "<タスクの目的を 1-2 文で>"}}]}},

  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Result"}}], "color": "red_background"}},
  {"type": "callout", "callout": {"rich_text": [{"type": "text", "text": {"content": "<完了後に記録すべきもの>"}}], "icon": {"type": "emoji", "emoji": "💡"}}},

  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Notes"}}], "color": "blue_background"}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "<Topic> Info"}}]}},
  {"type": "bulleted_list_item", "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "<事実・仕様>"}}]}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "To Do"}}]}},
  {"type": "heading_3", "heading_3": {"rich_text": [{"type": "text", "text": {"content": "<Phase>"}}]}},
  {"type": "to_do", "to_do": {"rich_text": [{"type": "text", "text": {"content": "<アクション>"}}], "checked": false}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "Related Links"}}]}},
  {"type": "bookmark", "bookmark": {"url": "https://..."}}
]
```

## 実例 (抜粋)

CVPR 2026 Early Bird Registration タスク用の子ブロック配列（抜粋）:

```json
[
  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Task Description"}}], "color": "gray_background"}},
  {"type": "paragraph", "paragraph": {"rich_text": [{"type": "text", "text": {"content": "CVPR 2026 の早期登録を 2026-04-23 11:59 PM Mountain Time までに完了する。採択論文の Poster 発表のため発表者登録としても必須。"}}]}},

  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Result"}}], "color": "red_background"}},
  {"type": "callout", "callout": {"rich_text": [{"type": "text", "text": {"content": "登録完了後、Registration ID / 領収書 / 支払額をここに記録する。"}}], "icon": {"type": "emoji", "emoji": "💡"}}},

  {"type": "heading_1", "heading_1": {"rich_text": [{"type": "text", "text": {"content": "Notes"}}], "color": "blue_background"}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "Registration Info"}}]}},
  {"type": "bulleted_list_item", "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "Early Bird 締切: 2026-04-23 11:59 PM Mountain Time"}}]}},
  {"type": "bulleted_list_item", "bulleted_list_item": {"rich_text": [{"type": "text", "text": {"content": "Cancellation 締切: 2026-05-13 (AoE)"}}]}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "To Do"}}]}},
  {"type": "heading_3", "heading_3": {"rich_text": [{"type": "text", "text": {"content": "Before Registration"}}]}},
  {"type": "to_do", "to_do": {"rich_text": [{"type": "text", "text": {"content": "参加タイプ（Student / Regular / Full-week）を確認"}}], "checked": false}},
  {"type": "heading_3", "heading_3": {"rich_text": [{"type": "text", "text": {"content": "Registration"}}]}},
  {"type": "to_do", "to_do": {"rich_text": [{"type": "text", "text": {"content": "フォーム入力 → 決済 → 領収書保存"}}], "checked": false}},

  {"type": "heading_2", "heading_2": {"rich_text": [{"type": "text", "text": {"content": "Related Links"}}]}},
  {"type": "bookmark", "bookmark": {"url": "https://cvpr.thecvf.com/Conferences/2026/Pricing2"}}
]
```

## バリエーション

タスクの性質で Notes の中身を変える。

- **Trip 系** (出張・旅行準備): `Trip Overview` / `To Do: Before the Trip`（Documents / Insurance / Mobile / Money / Transport / Packing で `heading_3` 分割）/ `To Do: Closer to Departure`
- **Paper 系** (論文提出・camera-ready): `Paper Info` / `To Do`（Await details / Revision / Submission の `heading_3` 分割）
- **Ops 系** (登録・予約・申請): `<Topic> Info` / `To Do`（Preparation / Application / After の `heading_3` 分割）

共通して **冒頭 4 行は常に固定**（Task Description + gray / Result + callout / Notes 開始）。Notes 内のセクション名だけタスクに合わせて差し替える。

## 関連

- ブロック型の詳細: [block-types.md](block-types.md)
- URL 埋め込みの詳細: [urls-and-bookmarks.md](urls-and-bookmarks.md)
- 失敗時のリトライ方針: [troubleshooting.md](troubleshooting.md)
