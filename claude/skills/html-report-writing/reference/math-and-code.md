# 数式 (KaTeX) とコードハイライト (Prism)

レポート内の数式は **KaTeX**、コードブロックは **Prism** で表示する。
両者ともテンプレート (`scripts/template.html` / `scripts/review-log-template.html`) に組み込み済み。

## Contents
- デフォルト: CDN 読み込み (ネット前提)
- air-gap / 配布時: `scripts/setup-libs.sh` でローカル化
- 数式の書き方 (KaTeX)
- コードハイライトの書き方 (Prism)
- 対応言語リスト

## デフォルト動作: CDN 読み込み

テンプレートには KaTeX と Prism の **CDN link** が `<head>` と `<body>` 末尾に書かれている。
受信者にネット接続があれば、ダブルクリック → ブラウザ → 数式とハイライトが動く。

ネット断時のフォールバック:
- KaTeX: 数式が生のソース (`$\sum x_i$` のような text) として表示される
- Prism: コードはハイライトなしのプレーン表示

**つまりネット断でも読める** — 情報は失われない、見栄えが落ちるだけ。

## air-gap / 配布時のローカル化

社内 air-gap 環境や、CDN に依存させたくない外部配布の場合は、
`scripts/setup-libs.sh` を実行して KaTeX/Prism を `docs/assets/lib/` に取得する。

```bash
bash <repo>/claude/skills/html-report-writing/scripts/setup-libs.sh docs/assets/lib
```

その上で、生成 HTML の CDN url を相対 path に置換:

| CDN url | → | ローカル path |
|---|---|---|
| `https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css` | → | `assets/lib/katex.min.css` |
| `https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js` | → | `assets/lib/katex.min.js` |
| `https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js` | → | `assets/lib/auto-render.min.js` |
| `https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism-tomorrow.min.css` | → | `assets/lib/prism.min.css` |
| `https://cdn.jsdelivr.net/npm/prismjs@1.29.0/...` | → | `assets/lib/prism-*.min.js` |

`sed` で一括置換するスニペット:

```bash
sed -i.bak \
  -e 's|https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/|assets/lib/|g' \
  -e 's|/contrib/auto-render|/auto-render|g' \
  -e 's|https://cdn.jsdelivr.net/npm/prismjs@1.29.0/themes/prism-tomorrow|assets/lib/prism|g' \
  -e 's|https://cdn.jsdelivr.net/npm/prismjs@1.29.0/components/|assets/lib/|g' \
  docs/YYYY-MM-DD_<topic>.html
```

これで `docs/` ディレクトリを zip で配ればオフラインで完全に動く。

## 数式の書き方 (KaTeX)

テンプレートでは KaTeX `auto-render` が body 末尾で走る。以下の delimiter を認識:

| 種類 | delimiter | 例 |
|---|---|---|
| インライン | `$...$` または `\(...\)` | `エラーは $\epsilon = y - \hat{y}$ で定義` |
| ブロック | `$$...$$` または `\[...\]` | `$$L = \frac{1}{N} \sum_{i=1}^{N} (y_i - \hat{y}_i)^2$$` |

**注意:**
- `$` と数式の間にスペースを入れない (`$ x $` ✗ → `$x$` ✓)
- ブロック数式 `$$...$$` は行頭 / 行末を改行で囲む
- マクロは `\newcommand` で `<script>` 内に事前定義可

サポートされる構文 (主要):
- 上付き・下付き: `x^2`, `x_i`, `x_{i,j}`
- 分数: `\frac{a}{b}`
- 総和・積分: `\sum_{i=1}^{N}`, `\int_0^\infty`
- 行列: `\begin{bmatrix} a & b \\ c & d \end{bmatrix}`
- ギリシャ文字: `\alpha`, `\beta`, `\theta`
- フォント: `\mathbb{R}`, `\mathcal{L}`, `\mathbf{x}`

完全な対応関数リスト: https://katex.org/docs/supported.html

### 既存の `<div class="formula">` との使い分け

| ブロック | 用途 |
|---|---|
| `<div class="formula">` (等幅) | 疑似コード / アルゴリズム / 1 行で済む式 |
| KaTeX `$$...$$` | 真の数式 (添字・分数・総和・行列を含む) |

数式が複雑になるなら KaTeX、algorithm-style なら `.formula`。

## コードハイライトの書き方 (Prism)

Prism は `<pre><code class="language-XXX">` を見て、自動でハイライトする。

```html
<pre><code class="language-python">
def loss(y, y_hat):
    return ((y - y_hat) ** 2).mean()
</code></pre>
```

Markdown ライクに書くなら HTML 上で:

```html
<pre><code class="language-bash">
pixi global install d2
d2 --layout=tala -t 200 input.d2 output.svg
</code></pre>
```

### 対応言語 (本スキルが同梱する Prism component)

`scripts/setup-libs.sh` でデフォルト取得されるのは:

- `bash`, `python`, `javascript`, `typescript`, `json`, `yaml`
- `markup` (HTML/XML), `css`, `clike` (C/C++ 系の基礎)
- `rust`, `go`

不足言語がある場合は `setup-libs.sh` を編集して `for lang in ...` に追加。

### テーマ

デフォルトは `prism-tomorrow` (ダーク系)。ライトテーマでも視認性は確保される。
別テーマ (例: `prism-okaidia`, `prism-twilight`) を使いたい場合は CDN url の `prism-tomorrow` を差し替える。

## アンチパターン

- **数式を画像 (PNG) で貼る** — 拡大で粗くなる、検索・コピペ不可、ダーク背景で潰れる → KaTeX を使う
- **数式を `<div class="formula">` の等幅 text で書く** — 添字・分数・総和が崩れる → KaTeX を使う
- **コードブロックに `language-*` class を付け忘れる** — ハイライトされない → 必ず明示
- **CDN を読み込んだまま air-gap 配布** — 受信側で数式が壊れる → `setup-libs.sh` でローカル化
- **KaTeX の `<script>` を `<head>` に置く** — DOM 解析前に走って render されない → `<body>` 末尾 (`defer` 付き)
