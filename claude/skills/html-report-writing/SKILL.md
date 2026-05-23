---
name: html-report-writing
description: 人間が読む長めの文章・レポート・ドキュメント・資料を生成するときに使用する。単一の HTML ファイル (+ 必要なら assets/) として出力し、Markdown が 100 行を超えると読まれなくなる問題を sticky TOC・構造化 callout・優先度 pill・数式 (KaTeX)・コードハイライト (Prism)・D2 ダイアグラム・チャート (matplotlib SVG) で解決する。技術分析・応用検討・設計レポート・選択肢比較・サーベイ・議論ログ (Codex 等の第二視点を取り込む review-log 型) など、500 字を超える / 図表を伴う / 改訂を重ねる文書には必ず使用する。"レポート", "ドキュメント", "資料", "サーベイ", "技術レポート", "HTMLレポート", "応用検討", "選択肢比較", "議論ログ", "review log", "Codex レビュー反復" などのトリガーで発動する。
user-invocable: true
---

# HTML レポート作成ガイド

人間が読む **長めの文章・レポート** を **単一の HTML ファイル** として出力するスキル。
Markdown は 100 行を超えるとスキャンされ判断が形骸化するが、HTML は
sticky TOC / 折りたたみ / 図表並列 / 数式 / コードハイライトで **engagement が上がり最後まで読まれる**。

> **発動条件:** 500 字を超える / 図表 (数式・コード・図) を伴う / 改訂を重ねる文書を書くときは
> 必ず本スキルを使う。短い memo や 1 リクエストの回答には不要。

参考: Thariq Shihipar "Using Claude Code: The Unreasonable Effectiveness of HTML" (Anthropic, 2026-05-08)

## レポート type 別 navigation

| 用途 | スターター | 詳細 pattern |
|---|---|---|
| 単発の技術分析 / 応用検討 / 設計説明 / 長めのドキュメント全般 | [`scripts/template.html`](scripts/template.html) | (この SKILL.md の共通骨格で十分) |
| 議論ログ (外部レビューを取り込み版を重ねる検討、v1→v2→v2.x, Codex 第二視点, Stage-gate) | [`scripts/review-log-template.html`](scripts/review-log-template.html) | [`patterns/review-log.md`](patterns/review-log.md) |
| ダッシュボード / 比較マトリクスなど他形式 | — | 必要になったら `patterns/` に追加 |

**判断基準:** 別モデル / 同僚レビューを取り込みながら結論や設計を動かすなら議論ログ型、結論が 1 ラウンドで決まるなら汎用型。

> **用語注意:** ここでの「議論ログ (review-log)」は **外部レビュー (Codex 等) のラウンドを 1 レポート内に取り込んで結論を動かす pattern**。
> 「HTML の見栄えを磨き直すサイクル」のことではない (それは全レポート共通の作業)。

## 既存スキルとの関係

| スキル | 役割 | 読者 | 形式 |
|---|---|---|---|
| `cto-briefing` | アルゴリズム俯瞰、What/Why の説明、実装詳細禁止 | CTO / 投資家 | HTML (読者層特化) |
| **`html-report-writing` (本スキル)** | HTML レポート全般の基盤、type 別 pattern を navigate | テックリード / 共同設計者 / 自分 | HTML (形式特化) |

cto-briefing が **読者層特化** (= 「CTO 向けに何を書くか」)、本スキルは **形式特化** (= 「HTML でどう書くか」)。
両者は直交する。CTO 向け資料なら cto-briefing、それ以外の技術レポートなら本スキル。

## 単一ファイル原則 (Thariq の原則)

「受け取った人がダブルクリックすればネット接続なしで完璧に開ける」状態を守る:

| 項目 | ルール |
|---|---|
| CSS | `<head>` 内の `<style>` にインライン |
| JavaScript | 本体ロジックはインライン。**KaTeX / Prism は例外** (下記) |
| 画像 | **D2 SVG と matplotlib SVG は `assets/` 外部参照可** (詳細は §図表) |
| フォント | system フォントのみ (`system-ui, "Hiragino Sans", "Noto Sans JP", ...`) |
| フレームワーク | Tailwind / Bootstrap / React 等は使わない。プレーン CSS で書く |
| 出力 | **1 ファイルのみ** (+ 必要なら `assets/` と `assets/lib/` ディレクトリ) |

**KaTeX / Prism の扱い (例外):**
- デフォルトはテンプレに **CDN link 埋込** (ネット接続があれば動く、なくても情報は失われない)
- 完全 air-gap 配布が必要なら [`scripts/setup-libs.sh`](scripts/setup-libs.sh) で `docs/assets/lib/` にローカル化
- 詳細: [`reference/math-and-code.md`](reference/math-and-code.md)

**D2 / matplotlib SVG の扱い (例外):**
- HTML 内 inline SVG はソース保守が辛く、クリックで原寸表示する UX のため `<a href="...svg">` の link target が必要
- → SVG は `docs/assets/` に外部ファイルとして置く

理由 (Thariq): 受信側のネット環境・社内プロキシ・CDN の rot・バージョン破壊に晒されない。

## ファイル配置規約

```
<project root>/docs/
├── YYYY-MM-DD_<topic>.html               # 本体レポート
└── assets/
    ├── YYYY-MM-DD_<topic-short>.d2       # D2 ソース
    ├── YYYY-MM-DD_<topic-short>.svg      # D2 / matplotlib SVG 出力
    └── lib/                              # (オプション) KaTeX/Prism ローカル化時のみ
```

- 日付は作成日 (改訂しても元の日付は維持、改訂履歴セクションでバージョン管理)
- topic は kebab-case で短く (`points2-3d-application`, `multiview-extension-survey` 等)
- アセットは `docs/assets/` 配下に固定

## 共通ページ構造

スターター ([`scripts/template.html`](scripts/template.html)) は次の骨格を持つ。
type 別 pattern は必要に応じてセクションを追加する。

1. **ヘッダー** — タイトル / サブタイトル / バージョン badge / 作成日 / 読了時間
2. **TOC** — `position: sticky` のサイドバー (デスクトップのみ)
3. **TL;DR** — 結論先出し。`<p class="lead">` 強調 + `<div class="intent">` で Action
4. **本文セクション** — レポート type 固有 (議論ログなら [`patterns/review-log.md`](patterns/review-log.md) 参照)
5. **参考文献 + 改訂履歴** — 元資料、各版で何を変えたか

TL;DR は **本文確定後に最後に書く**。結論を 1-2 文で、`<strong>` で本質的選択を強調。

## ビジュアルコンポーネント

### Callout / Pill (汎用 template に組込済)

| コンポーネント | 用途 | クラス |
|---|---|---|
| Lead 段落 | TL;DR の冒頭 1-2 文 | `<p class="lead">` |
| Intent callout (オレンジ) | 結論 / Action / 「だから何をするか」 | `<div class="intent">` |
| Risk callout (赤) | 既知リスク / 反証 / 懸念 | `<div class="risk">` |
| OK callout (緑) | 合意事項 / Pass 判定 / 「これは成立する」 | `<div class="ok">` |
| 優先度 pill | 案の優先度を色で scan させる | `<span class="pill p1-p5">` |
| Formula ブロック (等幅) | 疑似コード / アルゴリズム / 1 行で済む式 | `<div class="formula">` |
| Stage-gate テーブル | 計画フェーズ | `<table>` + `<tr class="win">` |

`.pill` 優先度の色対応:

| クラス | 色 | 用途 |
|---|---|---|
| `.pill.p1` | 緑 | 先行 / 最優先 |
| `.pill.p2` | 青 | 本命 |
| `.pill.p3` | オレンジ | 補助 |
| `.pill.p4` | グレー | 統合済 / 削除 |
| `.pill.p5` | 赤 | 破棄 |

### 数式 (KaTeX) とコードハイライト (Prism)

汎用 template に組込済:

- 数式: `$x_i$` (インライン) / `$$L = \sum (y - \hat{y})^2$$` (ブロック)
- コード: `<pre><code class="language-python">...</code></pre>`

書き方の詳細・delimiter 一覧・対応言語・air-gap ローカル化手順は
[`reference/math-and-code.md`](reference/math-and-code.md)。

### 議論ログ専用コンポーネント

別モデル視点を残す `.codex` callout、Stage-gate / Pass 条件の運用は
[`patterns/review-log.md`](patterns/review-log.md) に集約。本骨格には含まない。

## 図表 (可視化を最優先する)

レポート内では **情報をできるだけ可視化** する (文章で長々書くより図表で scan させる)。
2 種類のツールを使い分ける。

| 種類 | ツール | 用途 | 詳細 |
|---|---|---|---|
| 構造図 (ノード・矢印・配置) | D2 (TALA layout 基本) | データフロー、アーキ図、依存図 | [`reference/d2-diagrams.md`](reference/d2-diagrams.md) |
| 定量グラフ | matplotlib (SVG 出力) | line / bar / heatmap / scatter | [`reference/charts-and-plots.md`](reference/charts-and-plots.md) |

共通運用: 出力は `docs/assets/*.svg` に置き、HTML から `<img>` + クリック原寸表示で参照。
インライン SVG ではなく外部ファイル。

要点:
- **D2 は `--layout=tala -t 200` を基本** に使う (個人/OSS 無料、商用は要ライセンス)
- **direction: down** を基本にして aspect 比 < 2:1 を保つ
- **凡例は HTML figcaption 側に書く** (D2 内 legend は viewBox を壊す)
- **D2 ノードは saturated fill + 白テキスト + bold + ≥16px** で light/dark 両対応 (pastel fill + 暗色テキストは dark mode browser で読めなくなる、`reference/d2-diagrams.md` 参照)
- matplotlib は **`transparent=True`** + ニュートラル軸色で light/dark 両対応

## 作成手順 (汎用フロー)

1. **レポート type を決める** — 上の navigation table から
2. **スターターをコピー** — 汎用なら `scripts/template.html`、議論ログなら `scripts/review-log-template.html`
3. **TOC を骨格として配置** — 本文 section を先に列挙
4. **本文を書く** — 共通骨格 (TL;DR / 本文 / 参考文献) + type 固有セクション
5. **可視化で情報を整理** — 構造は D2、定量は matplotlib SVG を `docs/assets/` に生成
6. **数式は KaTeX で、コードは `language-XXX` class 付きで** — `reference/math-and-code.md` 参照
7. **TL;DR を最後に書く** — 結論先出しで上に貼る
8. **検証:**
   - ブラウザで開く (D2/matplotlib SVG が assets/ にあるか、KaTeX/Prism が render されるか)
   - ダーク / ライト両方で色コントラスト OK
   - クリックで SVG 原寸表示が動く
   - `Ctrl+P` で印刷プレビュー → PDF 化に耐える
   - リンク切れがないか

## 共通アンチパターン

- **CDN から Tailwind / Bootstrap を読み込む** — ネット断時に壊れる → プレーン CSS
- **Google Fonts を使う** — 同上 + プライバシー懸念 → system フォント
- **手書き SVG をインラインで埋める** — ノード重なり / 矢印交差で破綻、保守不能 → D2 を使う
- **チャートを PNG スクショで貼る** — 解像度・配色・タイポが資料と乖離 → matplotlib SVG
- **数式を画像 / 等幅 text で書く** — KaTeX で書く (添字・分数・総和が綺麗)
- **コードに `language-*` class を付け忘れる** — Prism がハイライトしない → 必ず明示
- **Markdown で済ます** — 100 行超えると読まれない → HTML + sticky TOC
- **TL;DR が長い** — 結論先出しの意味がなくなる → 2 段落以内
- **判断基準なし** — 「スコアリングする」だけで数式・閾値がない → 数値で書く
- **直接編集** (ローカル開発時) — このスキル自体は `claude/skills/` にあり dotter で `~/.claude/` に symlink されている。`~/.claude/skills/html-report-writing/` を編集すると nanokit が変更される

## 共有方法

- 受信者にファイルを直接渡す (`open foo.html`)。**assets/ ディレクトリも同梱**
- Slack には添付ファイル (`.html` + `assets/foo.svg`) として
- 公開可なら GitHub Pages

## セキュリティ注意

生成された HTML を新しい Claude セッションのコンテキストに食わせる場合は、
コメントや `data-*` 属性にプロンプトインジェクションが仕込まれていないか確認。
社外公開する場合は内部固有名詞 (人名 / 内部 ticket ID / API キー類) を確認。

## 同梱ファイル

| ファイル | 用途 |
|---|---|
| [`scripts/template.html`](scripts/template.html) | 汎用スターター (基本 callout + sticky TOC + KaTeX/Prism + 印刷 CSS) |
| [`scripts/review-log-template.html`](scripts/review-log-template.html) | 議論ログ特化スターター (.codex callout + 12 セクション + v1 badge) |
| [`scripts/diagram-template.d2`](scripts/diagram-template.d2) | D2 ボイラープレート (theme 200 + 4 classes) |
| [`scripts/setup-libs.sh`](scripts/setup-libs.sh) | KaTeX/Prism を `docs/assets/lib/` にローカル化する 1-shot スクリプト (air-gap 配布用) |
| [`patterns/review-log.md`](patterns/review-log.md) | 議論ログ (外部レビュー取り込み) レポートの作り方 |
| [`reference/d2-diagrams.md`](reference/d2-diagrams.md) | D2 詳細 (TALA, レイアウト, HTML 埋込) |
| [`reference/charts-and-plots.md`](reference/charts-and-plots.md) | matplotlib SVG での定量データ可視化 |
| [`reference/math-and-code.md`](reference/math-and-code.md) | KaTeX (数式) + Prism (コードハイライト) の組込方法 |
