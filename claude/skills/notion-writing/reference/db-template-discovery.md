# DB 新規ページ作成時のテンプレート確認

Notion DB に新しいページを追加する場合、**いきなり書き出さない**。まずその DB に登録されているテンプレートページを確認し、その構造に合わせて新ページを作ってから執筆する。

## なぜか

Notion DB は「テンプレート」機能でページ初期構造を統一している。テンプレート無視で書くと:

- 既存ページとセクション順序・見出し色がズレて DB 内の統一感が崩れる
- 必須セクション（例: Tasks DB の Result callout）を取りこぼす
- ユーザーが手動で構造を直す手戻りが発生する

逆にテンプレートに沿うと、追記が DB 全体の運用に自然に溶け込む。

## 手順

1. **DB の場所を特定**: 新規ページの追加先となる DB の URL / ID を確定する。ユーザーが「○○ DB に追加して」と言ったときは、まず `mcp__notion__notion-search` で同名 DB の候補を絞る。
2. **DB のテンプレート / 既存ページを取得**: `mcp__notion__notion-fetch` に DB ID を渡すと、子ページ一覧と DB のテンプレートが返る。Notion API 上テンプレートページは通常ページに混ざって列挙されるため、`is_template: true` 相当の印か、ページタイトルが "Template" や "雛形" を含むものを優先候補にする。判別が曖昧なら **直近に作られた数ページの構造を 2〜3 件 fetch して共通項を取る**。
3. **テンプレート本文を fetch**: 候補ページに対し `mcp__notion__notion-fetch` を実行し、heading 構成・背景色・セクション順序・必須 callout / placeholder を全部書き出す。
4. **新ページ作成**: `mcp__notion__notion-create-pages` で空ページを作り、テンプレートの heading / divider / callout 骨格を **同じ順序・同じ色** でコピーした children 配列を `mcp__notion__API-patch-block-children` で append する。`mcp__notion__notion-duplicate-page` が使える場合はテンプレートを複製してタイトルだけ書き換えるのが最短。
5. **本文を執筆**: 骨格ができてから、各セクション配下にコンテンツを足していく。テンプレートの placeholder（例: `<完了後に記録すべきもの>`）は実値で置き換えるか、未確定なら callout のまま残す。

## テンプレートが見つからない / DB にテンプレートが未登録のとき

優先順:

1. **DB 内の既存ページから推測**: `notion-fetch` で直近 3〜5 ページを取得し、共通する見出し列があればそれを暫定テンプレートとして踏襲する。
2. **同種 DB の規約に依存**: その DB が "Tasks" 系であれば [task-template.md](task-template.md) の Task Description / Result / Notes / Related Links 構造を流用する。
3. **どれも当てはまらない場合のみ**: ユーザーに「テンプレートが見つからなかった。この構造で作って良いか」と確認してから書き出す。何も確認せず独自構造で書き始めない。

## やってはいけない

- **テンプレート確認を飛ばして書き始める**: 既存運用とのドリフトを生む最大の原因。
- **テンプレートの見出し色を勝手に変える**: `gray_background` / `red_background` / `blue_background` などはユーザーの視認動線になっている。色を落とすと識別性が下がる。
- **テンプレートの placeholder ブロックを削除する**: 削除権限が無いことが多い ([troubleshooting.md](troubleshooting.md))。中身を上書きする方向で対処する。

## 関連

- Tasks DB の具体テンプレート: [task-template.md](task-template.md)
- ブロック型と色指定の詳細: [block-types.md](block-types.md)
- 削除権限拒否の回避: [troubleshooting.md](troubleshooting.md)
