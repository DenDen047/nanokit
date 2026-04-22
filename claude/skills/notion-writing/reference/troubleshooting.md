# Notion MCP トラブルシューティング

Notion MCP (`mcp__notion__`) 経由で書き込むときに実際に遭遇したエラーとその対処。

## Contents

- `body.children should be an array` エラー
- `delete-a-block` の Permission denied
- `update-a-block` の制約
- バッチサイズの目安
- 並列 `patch-block-children` の順序保証
- 空行・Unicode・レート制限

## `body.children should be an array` エラー

**症状**: `patch-block-children` を呼ぶと次のエラー:

```
{"status":400,"object":"error","code":"validation_error",
 "message":"body failed validation: body.children should be an array,
   instead was `\"[{\\\"type\\\": \\\"heading_1\\\"...`."}
```

渡した `children` が JSON 配列ではなく文字列化された状態で届いている。

**原因**: MCP のパラメータシリアライズで断続的に起こる。同じ payload でも発生する/しないが変わる。

**対処**: **まったく同じ payload でもう一度呼ぶ**（本プロジェクトでの実測: 1 回目失敗 → 2 回目成功）。複数ブロックを並列に投げているうち 1 つだけ失敗するケースが多いので、失敗したものだけ再試行すればよい。

**予防**:
- 1 バッチが 30 ブロックを超えるときは分割すると発生率が下がる傾向
- 並列呼び出し数を減らしても発生するので、純粋にリトライで対処する

## `delete-a-block` の Permission denied

**症状**: `mcp__notion__API-delete-a-block` が次のエラーを返す:

```
Permission for this action has been denied. Reason: Deleting a Notion block
the agent did not create in this session is a modification of a shared
external resource without explicit user authorization for that specific
deletion.
```

**原因**: Claude Code harness のセキュリティポリシー。Notion API 側の問題ではない。エージェントが**同一セッション内で作成した**ブロック以外は、削除にユーザーの明示的承認が必要。

**対処方針**:

1. **Append-only で設計する**: 既存ページを作り直すより、新規ページ作成時に最初から正しいブロックを入れるほうが確実。
2. **自分が直前に作成したブロックだけ消す**: `patch-block-children` 直後のレスポンスに含まれる block ID なら通常削除できる。
3. **削除不可なブロックが残ったら、ユーザーに Notion UI 上での手動削除を依頼**する。`divider` を挟んで視覚的に分離するなど、残存ブロックが邪魔にならない工夫をする。
4. **`Agent` ツール経由でも同じ制約**がかかる。並列実行で回避できない。

## `update-a-block` の制約

**症状**: `mcp__notion__API-update-a-block` でブロックタイプを変更しようとしても効かない。

**原因**: Notion API はボディのトップレベルに `heading_2: {...}` のようなキーを期待するが、MCP ツールは `type` キーの下にネストしてしまう。

**影響**:
- ブロックタイプの変更 (例: `paragraph` → `heading_2`) は不可
- `archived: true` でのアーカイブ移動は可能
- テキスト更新も MCP 経由では制約あり

**対処**: **大規模修正は「archive / delete → 再作成」パターンが確実**。ブロックタイプを変えたいなら、新ブロックを `patch-block-children` で追加 → 旧ブロックを `delete-a-block` で削除（削除権限があるならば）。

## バッチサイズの目安

`patch-block-children` の `children` 配列長:

| 個数 | 挙動 |
|---|---|
| ≤ 20 | 安定 |
| 20〜30 | ほぼ安定、稀に `children should be an array` エラー |
| 30〜40 | エラー率が体感上昇、リトライで通る |
| > 40 | 分割推奨 |

保守的には **20〜25** を目安にし、失敗時は上記セクションに従いリトライするか、前後 2 つに割る。

## 並列 `patch-block-children` の順序保証なし

同一ページに対して **複数の `patch-block-children` を並列実行すると、ブロックの出現順は保証されない**。後続で呼んだ側が先にページ末尾に追加されることがある。

- **順序が重要** なら逐次実行する
- 別々のページに並列 append するのは全く問題ない

## 空行を作る

```json
{"type": "paragraph", "paragraph": {"rich_text": []}}
```

## Unicode

日本語テキストはエスケープ (`\uXXXX`) でもそのままの文字でも動作する。どちらでも同じ結果。

## レート制限

Notion API にはレート制限があるので、一気に数十リクエストを並列に投げるとエラーになる可能性がある。経験上、同一ワークスペースで 5-10 並列までなら実用上問題ない。大量の append / delete を走らせるときは 1 秒程度のインターバルを挟むと安全。

## ゴミ箱

`delete-a-block` は完全削除ではなく、ゴミ箱 (Trash) に移動する。`archived: true` も同様。復元は Notion UI から可能。
