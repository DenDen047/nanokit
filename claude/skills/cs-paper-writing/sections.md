# Section-by-section guidance

Introduction と Abstract 以外の節を書くときに読む。
Introduction は SKILL.md §6 を、Abstract は abstract.md を参照。

## Contents

- 1. Related Work — teach the history
- 2. Method — Fig 1 / notation / text-eq-fig
- 3. Experiments — baseline / ablation / story
- 4. Discussion — Limitations と future work の結びつけ
- 5. Conclusion — GPS の再演

---

## 1. Related Work — "teach the history"

laundry list（「Foo et al. did X. Bar et al. did Y.」）にしない（Black, Freeman）。
良い Related Work は分野の **history を教える**。

### 書き方

- **テーマで grouping**。各テーマで「何が正しかったか / 何が足りなかったか」を書く
- **祖先を辿る**。2020 年以降しか引かない paper の "best of our knowledge" は浅い
- **present tense**（`Smith et al. propose ...`）。work は今も live している
- 先行研究を disparage しない。「良かった点 → さらにどう進めたか」の論理
- 配置は **冒頭 or 末尾**。末尾は Peyton Jones 式で、Intro で nugget を優先できる

### 構造テンプレート

```
## Related Work

### {Theme 1}（例: Global descriptor methods）
{Theme 1 を1 文で定義}. Work in this line {describes the genealogy}.
{Earliest approach} {contribution} [cite]. Later, {next approach} {extends} [cite].
{Recent work} {further improves} [cite]. While these methods excel at X,
they share a common assumption — {the assumption} — which fails when {condition}.
Our work relaxes this assumption by {approach}.

### {Theme 2}（例: Local descriptor methods）
...

### {Theme 3}（例: Joint optimization approaches — closest to ours）
...
```

最後のテーマは **自分の研究に最も近いもの** を置き、違いを最も精緻に説明する。

### アンチパターン

- **テーマではなく年代順に並べる**: 2018, 2019, 2020, ... と並べるだけで grouping がない
- **各引用が 1 文で完結**: 「A did X. B did Y. C did Z.」 = laundry list
- **自分の研究との関係を書かない**: 読者は自分で差分を計算することになる
- **先行研究を disparage**: 「彼らは fail する」。正: 「この条件では不十分だが、別の条件では有効」

---

## 2. Method — Fig 1 / notation / text-eq-fig

### Fig 1 = system overview

- 1 枚で全体像。本文を読まなくても caption だけで意味が取れる（self-contained）
- 最初にホワイトボード写真を placeholder として本文に貼って書き始める（Black）
- reviewer が caption しか読まないことを前提に、caption で要点を伝える

### Text + Equation + Figure の 3 方式（Black）

重要概念は **text + equation + figure の 3 方式** で提示する。冗長ではなく補完:

| 方式 | 役割 |
|---|---|
| **Text** | 直感と gist（not-so-technical に） |
| **Equation** | text を precise に |
| **Figure** | 直観を与える（"A picture is worth a thousand words"） |

3 方式を揃えると、読者が自分の得意な入口から入れる。

### 数式のお作法

- 数式は初出で散文の意味も併記（Knuth）:
  `We minimize L(θ) = ... (the loss measures how far predictions fall from ground truth).`
- **notation 表** を Appendix に置き、書き始めた瞬間から更新する
  - 慣例: `\mathbf{A}` matrix, `\mathit{a}` scalar, `\mathbf{a}` vector, `\alpha` parameter
  - overload しない: `x` を pixel の意味で使ったら他で使わない
- 数式は文の一部として句読点を打つ（Knuth）。文末は `.`、以降に節が続くなら `,`
- `\hat{c}_i` は正しい、`\hat{c_i}` は hat が `c` と `i` の中間に来るので誤り
- equations **must match code**。合わないなら deadline 前にどちらかを直す（Black）
  - pseudocode は method と一致、method は実験に使った code と一致

### アルゴリズム

pseudocode + 散文説明をペアで提示。pseudocode 単体では insight が伝わらない。

---

## 3. Experiments — baseline / ablation / story

### 原則

1. **Simple baseline を最初に作って走らせる**（Black, Keogh）
   SOTA より simple の方がよく通ることが多い。baseline に倒される覚悟で実装し、
   その結果を含めて story を作る
2. **Change ONE thing at a time**（Black）
   method と data を同時に変えない。変えたら何が効いたか分からない
3. **1 本の強い対照 + ablation で成分を 1 つずつ消す**
   baseline の個数より、比較の明晰さが重要
4. **結果に story を添える**
   表で数値を並べるだけにせず、「何が driver だったか」を本文で言語化する
5. **Fair に比較**（Black）
   「ボコボコにする」ではなく「何を学べたか」を書く。reviewer は fair さを見ている

### 節構造

```
### Setup
- Datasets: {data, split, preprocessing}
- Metrics: {正式名 + 1 文の意味}
- Baselines: {1 つずつに 1–2 文の説明と引用}
- Implementation: {framework, hardware, runtime}
  ※ 細かいハイパラは Appendix に逃がす

### Main Results
- 表 + 1 段落の story
- Story は「何が effect の driver か」を説明する

### Ablation
- 成分を 1 つずつ off にして表に並べる
- 「この成分を off にすると Y 落ちる。なぜか: ...」の 1 文を添える

### Qualitative Results（必要なら）
- 図で「こう改善された」を視覚化
- Failure case も入れる（reviewer 印象が改善する）
```

### 再現性

Appendix に **reproducibility checklist** を必ず置く:
dataset / split / hyperparam / random seed / hardware / runtime / code URL / model checkpoint URL。
本文中には埋め込まない（主張のリズムを崩す）。

NeurIPS reproducibility checklist、ML Reproducibility Challenge のフォーマットが参考になる。

---

## 4. Discussion — Limitations と future work

### Limitations は必ず書く

主要 ML 会議では Limitations 節が実質必須。書かないと reviewer から「自己批判の欠如」で減点される。
書き方の原則（Black）:

- 「今は限界だが、解決へのパスは見えている」と提示する
- future work と結びつけて「この方向に進める」の形にする
- 「grabbing too much of the field」にならないよう、future work は欲張らない

### テンプレート

```
## Limitations and Future Work

Our method assumes {assumption}. When {assumption fails}, {what happens}.
We view this as a limitation rather than a fundamental barrier:
{why solvable} suggests that {concrete path forward}.

A second limitation is {second limitation}. This is orthogonal to the {main nugget}
and could be addressed by {specific next step}.
```

---

## 5. Conclusion — GPS の再演

Conclusion は abstract の拡張版ではなく、**結果を見た後の再演**。
1 段落で GPS を繰り返し、「どう理解が変わったか」を present tense で書く。

構造:

```
{Goal を再提示}. {Problem を再提示（既存手法がなぜ失敗していたか）}.
{Solution（nugget）を再提示}. {Results を 1 文で要約}.
{The broader implication — この知見が次に何を可能にするか}.
```

avoid:
- abstract の逐語コピー
- 「we presented / we proposed」連発
- future work の長大リスト（1–2 項目に絞る）
