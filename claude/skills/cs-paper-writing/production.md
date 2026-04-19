# Production: Title / Acronym / Teaser / Figures / Supplemental / Video

論文の中身が固まった後に整える「パッケージング」要素。
Reviewer の第一印象を決めるので、手抜きすると減点される。

## Contents

- 1. Title
- 2. Acronym
- 3. Teaser Figure
- 4. Figures 全般
- 5. Supplemental material
- 6. Video
- 7. LaTeX 小道具

---

## 1. Title

- **12 語以内**で contribution を「詩の 1 行」に凝縮する（Black）
- 可能なら **Acronym を含める**（code と紐づけられる）
- 準備段階の研究なら `Towards {Goal}`
- 基礎を与える研究なら `On {Topic}`
- 可愛さを狙いすぎない（酔って入れた tattoo と同じで後悔する — Black）

良い例:
- `SMPL: A Skinned Multi-Person Linear Model`（SMPL）
- `Attention Is All You Need`（Transformer）
- `NeRF: Representing Scenes as Neural Radiance Fields for View Synthesis`

悪い例:
- `A Novel Approach to ...` （novel を自称）
- `Towards an Efficient and Effective Framework ...` （空虚な hedge の重ね掛け）

---

## 2. Acronym

良い acronym は code / talk / 引用時に readers がすぐ想起できる。

### 条件

- **invertible**（元の語が復元できる）
- **pronounceable** — 音声で呼べる
- **short** — 3–5 文字が理想
- **distinctive / searchable** — `NASA` や `NeRF` のように既存語と衝突するものは避ける
- 英語以外の語も候補（ラテン・ギリシャ・スペイン語等 — Black）

### 作り方

1. Paper の主要語を書き出す（名詞・動詞）
2. 頭文字を取り、Scrabble 感覚で並び替える
3. 短くて意味のある語に収束させる
4. 候補をいくつか共著者に見せて discuss する

例（Black より）:
- `SMPL` = Skinned Multi-Person Linear — "simple" から。short / searchable
- `MANO` = hand Model with Articulated and Non-rigid defOrmations — スペイン語で "hand"
- `CAPE` = Clothed Auto Person Encoding — 服飾語 (cape) と重なる

### アンチパターン

- 意味不明な文字列（無理に頭文字を継ぎ足しただけ）
- 既存語と完全衝突（`NASA`, `HAND`）
- acronym を title に無理やり詰めて title が不自然になる

---

## 3. Teaser Figure

Abstract の視覚版。1 枚で nugget を伝える。First page に置く。

### 3 類型

1. **Result summary** — 結果が美しい場合、成果を前面に
2. **Problem illustration** — 既存手法がどう失敗するか + 本手法の差
3. **System overview** — ごく cartoonish なときのみ first page に置ける

System overview は通常 Fig 1 として Method 節の冒頭に置く方が自然。
first page に置くなら全体を 1 秒で理解できる抽象度まで引き上げる必要がある。

### 原則

- **self-contained caption** — 本文を読まなくても図だけで理解できる
- **矢印や丸** で読者の視線を誘導する（重要領域を明示）
- **text は zoom なしで読めるサイズ** に
- **Sintel dataset** のように「綺麗で見たくなる」要素は武器になる（Black）

---

## 4. Figures 全般

- 早期に placeholder を入れる（ホワイトボード写真など）。図なしの原稿は story が見えない
- 図は必ず本文から参照する（`Figure 6 shows ...`）。参照されない図は削る
- 図参照の書き方: `In Figure 6, we show ...` より `Figure 6 shows ...` が簡潔
- caption は self-contained。色の意味・矢印の意味・重要領域をすべて書く
- 軸にラベルと単位。単位は caption で言い直さない（軸で完結させる）
- 色は意味を伝える手段として使う（飾りではない）
- figure は page / column の **top** に置く（`\begin{figure}[t]`）。`[h]` は無駄な vspace を生む
- `\begin{center}...\end{center}` は vspace を足すので、`\centering` を使う

---

## 5. Supplemental material

### 原則

1. 本文で `sup. mat. 参照` と約束したものは **必ず** 入れる
2. 本文と同等の polish。手抜きは即座に見抜かれる
3. **新規実験を忍ばせない**（会議によってはルール違反）
4. reviewer が短時間しか読まないことを前提にする

### 中身

- cherry-pick でない追加結果
- **failure cases**（正直さは印象を改善する）
- 追加 ablation
- 実装詳細（hyperparam 表、random seed、hardware）
- video（後述）

---

## 6. Video

**Reviewer は video を最初に見る可能性が高い**（Black）。第一印象を作る媒体。

### 作り方

- **4 分以内**（超えると観られない）
- **narrated** — 音声付き。生声または良質な AI 音声（ElevenLabs 等）
- **scripted** — 各文を別録音して後でミックスできるようにする
- **論文の再現ではなく、別媒体として story を語り直す**
  - 論文の静止図をそのまま貼る = ✗
  - time axis を活用する = ✓
    - before/after overlay
    - parameter を動かして動作を見せる
    - positional encoding のような抽象概念の動的説明
- **複数の再生環境でテスト**（特に macOS での再生）
- 最後に「論文を読む動機」を作って終える

### 模範例

[Jon Barron の Mip-NeRF video](https://jonbarron.info/mipnerf/) を Black は「masterful」と評価:

- 論文構造を video 構造に写さず、video 独自の教え方
- 時間軸を使って概念を段階的に開示
- chart を一度に出さず、suspense を作る

### video checklist

```
- [ ] 4 分以内
- [ ] narrated
- [ ] 各 sentence が別 take で撮れている
- [ ] before/after overlay や parameter 変化など time axis を活用
- [ ] failure case も含む
- [ ] macOS / Windows / Linux で再生確認
- [ ] 本文中に sup. mat. / video への参照がある
```

---

## 7. LaTeX 小道具

よく遭遇する LaTeX の「小さな困り」への定石:

### Bibliography

```latex
\usepackage[numbers,sort,compress]{natbib}
```

これで `\cite{a,b,c}` が `[1, 2, 5]` に自動 sort + compress される。

### 引用の空白

- `Author \cite{Author}` — OK（自動で `~` なし 1 スペース）
- `Author et al.~\cite{Author}` — OK（non-breaking space で line break 防止）
- `Author~\cite{Author}` — 通常不要（redundant）

### 文頭引用

`[10] was the first to V` は不可。`Author et al.~\cite{Author} were the first to V` に書き換える。
長いなら `Prior work on robust estimation~\cite{Author}` のように名詞句を置く。

### Capitalization in titles

BibTeX エントリで `title = {{SMPL}: Skinned Multi-Person Linear Model}` のように braces で保護しないと、
lower case に勝手に変換される。3D / 2D / SMPL などは常に braces で括る。

### Page management

- 9 ページを 8 ページに圧縮するとき: 段落末尾が 1–2 語で終わっている箇所を rework する
- `\vspace{-Xmm}` の乱用は禁物。図の周辺だけに限定
- section title が page 末尾に来るなら、前ページを圧縮して section を前ページに押し上げる
- figure は `[t]` に統一して vspace を節約
