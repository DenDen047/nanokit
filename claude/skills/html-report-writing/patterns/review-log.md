# 議論ログ (review-log) レポート pattern

別モデル (Codex / Gemini / 同僚) と複数ラウンドの **外部レビュー** を経て深化させた
技術検討を、優先度 pill・第二視点ボックス・改訂履歴付きで **1 レポート内に議論ログとして残す** pattern。

論文の自プロジェクト応用、技術選択肢の比較、設計案のレビュー、
**v1 → v2 → v2.x で結論や前提が変わる検討** に最適。

> **用語注意:** ここでの "反復" は「HTML 本体の見栄えを磨き直すサイクル」ではなく、
> **外部レビュー (Codex 等) を取り込んで結論や設計が動くサイクル**を指す。
> 見栄え調整は全レポート共通の作業なので pattern として切り出さない。

## Contents
- いつ使うか / 単発レポートとの違い
- スターター: `scripts/review-log-template.html`
- 12 セクション構造 (順序重要)
- 専用ビジュアルコンポーネント (.codex)
- Stage-gate テーブル
- 議論ログを残すプロセス (Codex 投入手順、改訂履歴の書き方)
- アンチパターン
- Claude への依頼例

## いつ使うか

| 兆候 | 使うべき pattern |
|---|---|
| 結論が 1 ラウンドで決まる単発分析 | 汎用 [scripts/template.html](../scripts/template.html) |
| 別モデル / 同僚にレビューさせて取り込みたい | **本 pattern** |
| 選択肢を pill で優先度付けして比較したい | **本 pattern** |
| 改訂履歴を読者に見せて「思考の透明性」を示したい | **本 pattern** |
| CTO / 投資家向けに What/Why だけ伝えたい | `cto-briefing` skill (別スキル) |

## スターター

`scripts/review-log-template.html` をコピー。以下が組み込み済み:

- `.codex` callout (紫、`::before` で「Codex 第二視点」自動ラベル)
- v1.0 badge (議論ログとして版を重ねる前提の version 表示)
- 12 セクション TOC
- 優先度 pill p1-p5 + Stage-gate テーブル雛形
- Pass 条件 / やらないこと / 改訂履歴セクション

汎用 [`scripts/template.html`](../scripts/template.html) との違い: `.codex` CSS、`v1.0` badge、12 段の TOC、改訂履歴の詳細フォーマット。

## 12 セクション構造 (順序重要)

1. **ヘッダー** — タイトル / サブタイトル / バージョン badge / 作成日 / 対象論文 / 読了時間
2. **TOC** — `position: sticky` のサイドバー (デスクトップのみ)
3. **TL;DR — Nugget** — 結論先出し。`<p class="lead">` 強調 + `<div class="intent">` で具体的優先度/Action
4. **対象の 1 分要約** — 元論文・元手法を凝縮。数式は KaTeX (`$...$`) — [`reference/math-and-code.md`](../reference/math-and-code.md) 参照
5. **接合点 / 整合性分析** — 自プロジェクトとの関係を表で見せる。✅/⚠/❌ のシンボル
6. **応用案 / 選択肢列挙** — 各案に `<span class="pill p1-p5">` で優先度、`.risk` / `.codex` / `.ok` ボックスで議論
7. **根本リスク** (オプション、レビューで見えてきた本質懸念があるなら独立セクション化)
8. **第二視点 (Codex 等)** — 別モデルレビューの「ラウンド N の経緯」を記録。最辛口指摘は blockquote
9. **実装ロードマップ** — Stage-gate テーブル (Stage / 作業 / 所要 / Pass / Fail 時)
10. **やらないこと** — 明示的に棄却した選択肢の理由
11. **Pass 条件** — 指標と数値の閾値テーブル (定量化された成功条件)
12. **参考文献 + 改訂履歴** — 元論文・関連資料、各版で何を変えたか

## 専用ビジュアルコンポーネント: `.codex` ボックス

`scripts/review-log-template.html` の `<style>` には以下が組み込み済み (汎用 template には無い):

```css
.codex {
  background: var(--codex-bg); border-left: 4px solid var(--codex-border);
  padding: 12px 16px; margin: 16px 0; font-size: 0.95rem;
}
.codex strong { color: var(--codex-border); }
.codex::before {
  content: "Codex 第二視点";
  display: block; font-size: 0.7rem; letter-spacing: 0.08em;
  text-transform: uppercase; color: var(--codex-border);
  font-weight: 700; margin-bottom: 4px;
}
```

CSS 変数 (light / dark):

```css
:root {
  --codex-bg: #f5f3ff;
  --codex-border: #8b5cf6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --codex-bg: #2e1065;
    --codex-border: #a78bfa;
  }
}
```

**レビュー元が Codex でない場合**: `.codex` を `.review` 等にリネームし、
`::before` の content を変更する (例: `"Gemini 視点"`, `"同僚レビュー"`)。
ソース明示が誠実さの担保になる。

## Stage-gate テーブル

各 stage で **Pass 条件 (定量)** と **Fail 時の対処** を必ず書く。
「改善する」「同等以上」など曖昧な claim は禁止。

| Stage | 作業 | 所要 | Pass | Fail 時 |
|---|---|---|---|---|
| S0 prep | 実物確認、データ準備、ツール整備 | 1–2 wk | データ N 件、tool が動く | スコープ見直し |
| S1 probe | 案 B を最小実装 | 1 wk | 指標 X が baseline 同等 | A 本実装中止 |
| S2 main | 案 A 本実装 | 3–4 wk | 指標 X が baseline + N% | scope 削減 |
| S3 統合 | C を A に接合 | 2 wk | 既存指標が劣化しない | C を切り離す |

## 議論ログを残すプロセス

### 基本サイクル

```
v1 (初稿)
  ↓ Codex / Gemini / 同僚 に投入
v1 review (辛口指摘 N 件)
  ↓ 取り込み
v2 (反映版)
  ↓ 必要なら再ラウンド
v2 review (より深い構造的指摘)
  ↓ 取り込み
v2.x (削り込み版)
```

### 各ラウンドで記録すべきもの

1. **指摘総数** と **取り込み件数** (誠実さの担保。「不採用 = 0 件」等)
2. **最辛口指摘** を blockquote で原文引用 (思考の透明性)
3. **取り込みによる scope 変更** を改訂履歴に明示 ("v2.1 → v2.2 で何が変わったか")
4. **棄却された案** は `<span class="pill p5">破棄</span>` 付きで残す (なぜ捨てたかの記録)

### Codex への投入手順 (推奨)

別ターミナルで `codex-review` / `codex-discuss` スキルを使う。本 pattern は結果を取り込む「保管庫」役。

```text
# Codex 側プロンプト例
docs/YYYY-MM-DD_<topic>.html (v2.0) を読んで、以下の観点で辛口にレビューしてください:
  - 隠れた依存変数 (= 失敗時に原因分解できない設計)
  - 楽観的すぎる Pass 条件
  - 「壊さない」「同等以上」など曖昧な claim
  - 案同士の独立性が崩れている箇所
  - 規模・データ前提の妥当性

指摘は番号付きで、各指摘の根拠を 1-2 文で示してください。
```

返ってきた指摘を `.codex` ボックスにまとめ、根本的なものは
**独立 §根本リスク セクション**を新設して書く。

### 改訂履歴セクションの書き方

```html
<h3>本書の改訂履歴</h3>
<ul>
  <li><strong>v1.0 (初稿):</strong> 前提 X で設計。Codex が「Y は冗長」を指摘し...</li>
  <li><strong>v2.0:</strong> ユーザー指摘により Z 前提に再設計。優先度を A → B に...</li>
  <li><strong>v2.1:</strong> depth backend 選定を ... 撤回。... を追加</li>
  <li><strong>v2.2 (本書):</strong> Codex 第二ラウンドの 9 件指摘を全面反映、<strong>大幅な scope 削減</strong>。
    ① ... ② ... ③ ...
    <strong>核心思想:</strong> 「賭けを分解する」— X / Y / Z の 3 変数を 1 つずつ動かして測定可能に。
  </li>
</ul>
```

各版の `<li>` には:
- 動かした前提 (= 何が変わったか)
- 反映した指摘 (= 誰に言われたか)
- 「核心思想」(= この版で読者に伝わってほしい一行)

を書く。

## 作成手順 (本 pattern 特化)

1. `scripts/review-log-template.html` をコピー
2. TOC の 12 セクション骨格を残したまま本文を書く
3. 接合点表で整合性を見せる (✅/⚠/❌)
4. 応用案を pill 付きで列挙 (優先度を明示)
5. (必要なら) D2 ダイアグラム / matplotlib SVG を `docs/assets/` に — [`reference/d2-diagrams.md`](../reference/d2-diagrams.md), [`reference/charts-and-plots.md`](../reference/charts-and-plots.md)
6. TL;DR を最後に書く (本文確定後に結論先出しで上に貼る)
7. **Codex / 別モデルに投入** — 上記プロンプトで辛口レビュー
8. 指摘を `.codex` ボックスに取り込み、`v2.x` として保存
9. 改訂履歴セクションを更新
10. 検証: ブラウザ表示・印刷プレビュー・リンク切れ・色覚

## アンチパターン (本 pattern 固有)

- **外部レビュー指摘を非表示で取り込み** — 誠実さが伝わらない、思考が浅く見える → `.codex` ボックスでラベル付き引用
- **改訂履歴なし** — 「なぜこの結論か」が読者に伝わらない → 各版で動かした前提を書く
- **pill なしで優先度を文章で書く** — scan できない → 必ず色付き pill
- **Pass 条件を「改善する」で済ます** — 定量化されていない → 数値の閾値
- **「やらないこと」セクションなし** — scope creep を後から正当化できない → 明示棄却
- **TL;DR が長い** — 結論先出しの意味がなくなる → 2 段落以内

## Claude への依頼例

```text
arXiv:XXXX を読んで、@<repo パス> プロジェクトに応用できないか
HTML 議論ログとして検討して。

要件:
- html-report-writing skill の patterns/review-log.md に従う
- docs/YYYY-MM-DD_<topic>.html に出力
- scripts/review-log-template.html をスターターに使う
- 接合点を表で見せる、応用案は pill で優先度明示
- 全体のデータフローを docs/assets/<topic>.d2 + .svg で描く (TALA layout)
- 初稿を Codex に投入する想定で、改訂しやすい構造で書く

検討観点:
- 元論文の前提と自プロジェクトの相性
- 統合方法の選択肢 (3-5 案、pill で優先度)
- リスク・反証
- 実装ロードマップ (stage-gate)
- 定量 Pass 条件
```
