# Notion MCP トラブルシューティング

Notion MCP (`mcp__notion__`) 経由で書き込むときに実際に遭遇したエラーとその対処。

## Contents

- `body.children should be an array` エラー
- `delete-a-block` の Permission denied
- `update-a-block` は本文更新に使えない
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

## `update-a-block` は本文更新に使えない（既存ブロックの rich_text は書き換え不可）

**症状**: `mcp__notion__API-update-a-block` で既存ブロックのテキスト (`rich_text`) を書き換えようとすると、渡し方を問わず必ず 400 で弾かれる。例（空の callout に本文を入れようとしたケース）:

```
{"status":400,"object":"error","code":"validation_error",
 "message":"body failed validation. Fix one:
   ... body.callout should be defined, instead was `undefined`.
   ... body.type should be not present, instead was `{\"callout\":{\"rich_text\":...`."}
```

**根本原因**（実測で確定、断続現象ではなく決定論的）:

- Notion REST API の `PATCH /v1/blocks/{block_id}` は、ボディの **トップレベルにブロックタイプ名のキー**（`callout` / `paragraph` / `heading_2` …）を置くことを期待し、`type` というキーが present だと**明示的に拒否**する。
- ところがこの MCP ツールは、引数 `type` に渡した値を**そのまま `body.type` にネスト**して送る。したがって `type` に何を入れても（`{"callout":{"rich_text":[...]}}` でも `{"rich_text":[...]}` でも）Notion 側は「`type` は不可、`callout` が無い」と 400 を返す。
- **ツール経由では `body.callout`（＝トップレベルのタイプキー）に到達する経路が存在しない**。ゆえに rich_text 更新もブロックタイプ変更も一律で不可能。権限やシリアライズの問題ではないので**リトライしても通らない**。
- 唯一通るのは `archived: true`（アーカイブ = ゴミ箱移動）だけ。

**対処 — 「その場更新」を諦めて append で回す**:

1. **対象が自分（integration bot）が同一セッションで作ったブロックなら**: 旧ブロックを `delete-a-block` で消して `patch-block-children` で作り直す。
2. **対象が人間作成 or 別セッション作成のブロックなら**: 上の「`delete-a-block` の Permission denied」により**削除もできない**。この場合は**触らずに残し、`after` 指定で直後に同内容の兄弟ブロック（通常は `paragraph`）を `patch-block-children` する**のが唯一確実な手。
   - 具体例: Task テンプレートに最初から入っている**空の callout (💡) は人間作成なので中身を埋められない**。callout はそのまま残し、その直後に本文 paragraph を足す。後続で同じ `after` に別ブロックを足すなら、順序を保つため**本文 paragraph を先頭にまとめて 1 回の patch で挿入**する。
3. 見た目上どうしても callout の枠内に入れたい等の要件があれば、ユーザーに Notion UI での手当てを依頼する（ツールでは不可能なため）。

**要点**: このツールは「作る（append）」専用と割り切る。**既存ブロックの中身を書き換える設計にしない**（append-only + 兄弟追加）。

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
