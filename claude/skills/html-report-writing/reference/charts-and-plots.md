# グラフ・チャート (定量データの可視化)

D2 はノード・矢印・配置の「構造図」用。**数値データのチャート (line / bar / heatmap / scatter)** は
matplotlib で SVG を書き出し、`docs/assets/` に置いて HTML から `<img>` で参照する。

D2 と同じ運用 (外部 SVG → `<img>` 参照) で統一できる。

## Contents
- ツール選定 (matplotlib SVG vs Plotly vs Vega-Lite)
- インストール
- 基本 snippets (line / bar / heatmap)
- ダーク / ライト両対応のコントラスト
- HTML 埋込パターン
- アンチパターン

## ツール選定

| ツール | 静的/対話 | 単一ファイル原則との相性 | 採用判断 |
|---|---|---|---|
| **matplotlib (SVG 出力)** | 静的 | ◎ 外部依存ゼロ | **基本採用** |
| Plotly (HTML 単体) | 対話 | △ JS が重い (3MB+) | 数値詳細を hover で見たいときのみ |
| Vega-Lite (declarative) | 対話 | △ vega.min.js + vega-lite.min.js 同梱必要 | 比較的軽量だが、本スキルでは未採用 |
| Chart.js (CDN) | 対話 | ✗ 外部 CDN | 本スキルでは使わない |
| seaborn → matplotlib | 静的 | ◎ matplotlib と同 | 統計図 (boxplot, violin) で採用可 |

**結論:** matplotlib SVG が基本。レポートは "印刷して読む人 / PDF 化する人" がいる前提で、
静的 SVG が最も安全 (PDF 印刷も保証される)。

## インストール

```bash
pixi global install matplotlib seaborn   # conda-forge 経由
```

## 基本 snippets

### Line chart (loss 曲線、metric 推移)

```python
import matplotlib.pyplot as plt

fig, ax = plt.subplots(figsize=(7, 3.2))
ax.plot(epochs, loss_a, label="A (baseline)", color="#94a3b8", linewidth=1.5)
ax.plot(epochs, loss_b, label="B (proposed)", color="#22d3a0", linewidth=2)
ax.set_xlabel("epoch")
ax.set_ylabel("loss")
ax.legend()
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("docs/assets/2026-MM-DD_loss.svg", bbox_inches="tight", transparent=True)
```

### Bar chart (選択肢比較、指標一覧)

```python
fig, ax = plt.subplots(figsize=(6, 3))
labels = ["A", "B", "C", "D"]
values = [0.82, 0.91, 0.76, 0.43]
colors = ["#94a3b8", "#22d3a0", "#fb923c", "#ef4444"]   # pill 色と統一
ax.bar(labels, values, color=colors)
ax.set_ylabel("score")
ax.set_ylim(0, 1)
for i, v in enumerate(values):
    ax.text(i, v + 0.02, f"{v:.2f}", ha="center", fontsize=9)
fig.tight_layout()
fig.savefig("docs/assets/2026-MM-DD_score.svg", bbox_inches="tight", transparent=True)
```

### Heatmap (相関行列、混同行列、ablation grid)

```python
import seaborn as sns

fig, ax = plt.subplots(figsize=(5, 4))
sns.heatmap(matrix, annot=True, fmt=".2f", cmap="RdYlGn",
            xticklabels=labels, yticklabels=labels, ax=ax,
            cbar_kws={"shrink": 0.6})
fig.tight_layout()
fig.savefig("docs/assets/2026-MM-DD_ablation.svg", bbox_inches="tight", transparent=True)
```

## ダーク / ライト両対応のコントラスト

HTML 側が `prefers-color-scheme: dark` 対応のため、SVG も両方の背景で読める必要がある。

**ルール:**
- `transparent=True` で背景透過 (HTML 側背景が透ける)
- 軸ラベル・tick・タイトルは **ニュートラルな中間色** で書く (`#64748b` 等)
- 線色は **どちらの背景でも見える彩度** を選ぶ (`#22d3a0`, `#fb923c`, `#94a3b8`)
- 純白 `#fff` / 純黒 `#000` は片方で消える → 使わない

```python
plt.rcParams.update({
    "axes.edgecolor": "#64748b",
    "axes.labelcolor": "#64748b",
    "xtick.color": "#64748b",
    "ytick.color": "#64748b",
    "text.color": "#64748b",
    "grid.color": "#64748b",
    "grid.alpha": 0.3,
    "axes.facecolor": "none",        # transparent
    "savefig.facecolor": "none",
    "figure.facecolor": "none",
})
```

これを cell 冒頭で一度実行すれば、以降の plot に共通で適用される。

## HTML 埋込パターン

D2 ダイアグラムと同じ。`<figure>` + `<img>` + `<figcaption>` で囲み、クリック原寸表示を付ける。

```html
<figure style="margin: 0;">
  <div class="diagram-scroll">
    <a href="assets/2026-MM-DD_loss.svg"
       target="_blank" rel="noopener"
       title="クリックで原寸を新タブで開く">
      <img src="assets/2026-MM-DD_loss.svg"
           alt="A と B の loss 曲線の比較。B は epoch 10 以降で A を継続的に下回る。"
           loading="lazy">
    </a>
  </div>
  <figcaption class="footnote">
    Fig. 1: loss 推移。<strong>B</strong> が <strong>baseline + 23%</strong>。
    ソース: <code>docs/assets/2026-MM-DD_loss.svg</code>
  </figcaption>
</figure>
```

`alt` は **何が読み取れるか** を書く ("loss グラフ" だけではダメ)。
スクリーンリーダー利用者と検索エンジンが図の主旨を把握できる必要がある。

## アンチパターン

- **chart 用に外部 JS (Plotly/Chart.js) を CDN 経由で読み込む** — 単一ファイル原則と衝突
- **PNG で出力** — 印刷で粗くなる、ズームできない → SVG
- **Excel で作ったグラフをスクショ** — 解像度・配色・タイポが資料全体と乖離 → matplotlib で書く
- **alt 属性なし** — アクセシビリティ違反、検索性低下
- **小さすぎる figsize** — レポート幅 (~1100px) で見たときに字が読めない → 7×3 inch 程度
- **`transparent=False`** — ライト/ダーク切替で背景色が乖離 → 必ず透過
