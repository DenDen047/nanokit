# D2 ダイアグラム運用ガイド

HTML レポートに埋め込むダイアグラムは **D2 (https://d2lang.com)** で書き、
SVG として `docs/assets/` 配下に出力し、HTML から外部参照する。

## Contents
- なぜ D2 か (ツール比較)
- インストールとレンダリング
- レイアウト方向 — aspect 比のルール
- 凡例は HTML 側に書く (D2 内部の legend は使わない)
- HTML 埋込パターン (figure + figcaption)
- ボイラープレート

## なぜ D2 か (ツール比較)

| ツール | ダーク + accent | 自動 layout | 数式・添字 | 採用 |
|---|---|---|---|---|
| **D2** | theme 200 番台が綺麗 | direction + grid-rows + near | OK | **採用** |
| Mermaid | 弱い | 弱い | 弱い | 不採用 (AI 生成最容易だが質感が劣る) |
| TikZ | 強い | 弱い (手動) | 強い | 不採用 (論文採用なら最強だが冗長) |
| Graphviz | 弱い | OK | 弱い | 不採用 (ダークテーマ苦手) |
| Excalidraw | 手描き風 | 手動 | 弱い | 不採用 (公式資料に不向き) |

## インストールとレンダリング

D2 本体 + TALA layout engine の両方を入れる。**本スキルは TALA を基本 layout として使う** (dagre より配置が美しい)。

```bash
pixi global install d2                              # D2 本体 (0.7.1 以上)
curl -fsSL https://d2lang.com/install.sh | sh -s -- --tala  # TALA layout engine
```

レンダリング:

```bash
d2 --layout=tala -t 200 input.d2 output.svg         # ✓ 基本
# 短縮形:
d2 -l tala -t 200 input.d2 output.svg
```

**TALA ライセンス:** 個人・OSS 用途は無料 (要登録、`TALA_LICENSE_KEY` 環境変数)。
商用利用は有料 ($60+/月)。詳細: https://terrastruct.com/tala

**TALA が使えない環境 (商用・air-gap でキー無し)** はデフォルトの dagre にフォールバック:

```bash
d2 -t 200 input.d2 output.svg                       # dagre (default)
```

dagre でも見栄えは「許容範囲」だが、ノード配置の重なりや過剰な交差が出やすい。
重要な公開資料 / クライアント向けは TALA で出すこと。

**theme 200 を推奨する理由:** HTML 側も `prefers-color-scheme: dark` 対応で設計しているため、
SVG とのコントラスト破綻が起きにくい。ライトテーマで読まれる場合も 200 は背景が `slate-900` で、
HTML 本文背景 (light: `#fff` / dark: `#0f172a`) とのコントラストが両方で確保される。

## レイアウト方向 — aspect 比が UX を決める

| direction | aspect | 結果 | 評価 |
|---|---|---|---|
| `right` (横長) | 2:1+ | 横スクロール必須 → 認知負荷高 | ✗ 避ける |
| `down` (縦長) | 0.5–1.5:1 | ページ縦スクロールに自然に乗る | **✓ 推奨** |
| `down` + 内部 `right` | 内部グループだけ横並び | 縦フロー + 横グルーピング | **✓ 最適** |

aspect > 2:1 になりそうなら **行を増やす (`grid-rows` / 縦区切り)** で縦長化。

## 凡例は HTML 側に書く

D2 の `legend.near: top-right` は viewBox が無駄に拡大 + inner/outer viewBox 不整合を起こす。
凡例は **HTML figcaption 内に flex layout で配置**。フォント一貫性も上がる。

```html
<figcaption class="footnote">
  <div style="display: flex; flex-wrap: wrap; gap: 12px; justify-content: center;
              margin: 8px 0 10px; font-size: 0.85rem;">
    <span style="display: inline-flex; align-items: center; gap: 6px;">
      <span style="display: inline-block; width: 14px; height: 14px;
                   border: 2px solid #22d3a0; border-radius: 3px;"></span>
      新規 (path A)
    </span>
    <span style="display: inline-flex; align-items: center; gap: 6px;">
      <span style="display: inline-block; width: 14px; height: 14px;
                   border: 2px solid #94a3b8; border-radius: 3px;"></span>
      既存
    </span>
  </div>
  ソース: <code>docs/assets/foo.d2</code>
  (再生成 = <code>d2 --layout=tala -t 200 foo.d2 foo.svg</code>)
</figcaption>
```

凡例の色は D2 側の `classes:` で定義した stroke 色と一致させること。

## HTML 埋込パターン

```html
<figure style="margin: 0;">
  <div class="diagram-scroll">
    <a href="assets/YYYY-MM-DD_topic.svg"
       target="_blank" rel="noopener"
       title="クリックで原寸を新タブで開く">
      <img src="assets/YYYY-MM-DD_topic.svg"
           alt="ダイアグラムの説明..."
           loading="lazy">
    </a>
  </div>
  <figcaption class="footnote">
    <!-- 色凡例 (HTML 側 flex layout) -->
    <!-- 説明 + ソース表記 + 再生成コマンド -->
  </figcaption>
</figure>
```

- `<a>` で囲むと「クリック → 新タブで原寸表示」が動く。スマホ等で詳細を確認したいケースに必須。
- `loading="lazy"` でスクロール前は読み込まない。
- `alt` は必ず書く。アクセシビリティ + リンク切れ時のフォールバック。

## ボイラープレート

`scripts/diagram-template.d2` をコピーして使う。`scripts/template.html` から相対参照で動く。

定義済みの classes:

| class | 色 | 用途 |
|---|---|---|
| `new` | 緑 (`#22d3a0`) | 新規追加ノード |
| `base` | グレー (`#94a3b8`) | 既存ノード |
| `attn` | オレンジ (`#fb923c`) | 注目したい接続 / 重要 module |
| `inject` | 緑破線 | gated / 条件付き注入 |

色運用を一貫させたい場合はこの 4 つから出ない範囲で書く。
追加が必要なら `classes:` ブロックに追記し、HTML figcaption の凡例もそろえる。

## アンチパターン

- **手書き SVG をインラインで埋める** — ノード重なり / 矢印交差で破綻、保守不能 → D2 を使う
- **D2 凡例を D2 内部で書く** — viewBox が無駄に拡大 → HTML figcaption に分離
- **direction: right のまま 8 ノード並べる** — 横スクロール必須で読まれない → 縦長化
- **SVG を base64 で HTML にインライン** — 1 ファイル原則に思想は合うが、HTML が肥大化 + 編集不能化。`assets/` 別ファイル運用が現実解
