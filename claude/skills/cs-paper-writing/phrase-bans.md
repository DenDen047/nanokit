# Phrase Bans: LLM-tell / Zombie Nouns / 禁則句

LLM が書いた文はしばしば「文法は正しいが insight が薄い」（Black）。
このファイルに列挙された語を最終稿で grep し、すべて書き直す。

## Contents

- 1. LLM-tell（AI 特有の美辞麗句）
- 2. 意味の薄い動詞（allows to / provides / enables）
- 3. 弱い hedge（we can / aim to / may）
- 4. 支持のない比較級・絶対化
- 5. we の濫用
- 6. Zombie nouns（名詞化）
- 7. Style 小道具（感嘆符・contractions・tense）
- 8. 一括 grep コマンド

---

## 1. LLM-tell（AI 特有の美辞麗句）

| 避ける | なぜ悪いか | 置換 |
|---|---|---|
| `delve into` | LLM の癖。「調べる」は動詞 `study / examine / analyze` |
| `showcase` | 論文は販促資料ではない | `show / demonstrate / present` |
| `unveil` | 隠されていたわけではない | `introduce / describe` |
| `pivotal` | 美辞麗句 | `central / necessary / load-bearing` |
| `leverage` (動詞として) | LLM 語彙で頻出 | `use / exploit / apply` |
| `realm` | 美辞麗句 | `field / area` |
| `navigate the challenges of` | 中身が空 | `address the problems that` |
| `seamlessly integrate` | 検証不可 | `integrate` のみ。接続の自動性を主張するなら根拠と共に |
| `paradigm shift` | overclaim | 削除、または具体的な変化を書く |
| `holistic approach` | 意味不明 | 何と何を統合したかを書く |
| `intricate` | 美辞麗句 | `complex` もし必要なら |
| `meticulous` | 自画自賛 | 削除 |
| `in today's {landscape / world / era}` | 意味なし | 削除して具体的年代・制約を書く |

---

## 2. 意味の薄い動詞

| 避ける | なぜ悪いか | 置換 |
|---|---|---|
| `allows to V` | "allows WHO to V" の who が抜けている | `V` そのもの、または `allows {the method} to V` |
| `provides X` (機構不明) | 誰がどう provide するか書けていない | メカニズムを動詞で書く |
| `enables X` (機構不明) | 同上 | 同上 |
| `facilitates X` | 同上 | 同上 |
| `addresses the issue of X` | 解決したのか触れただけか曖昧 | `solves X` / `reduces X by Y%` など |
| `handles X` | 機構不明 | 具体動詞 |

**原則**: 「どう X するのか」を書けないなら、その動詞は使わない。

---

## 3. 弱い hedge

| 避ける | なぜ悪いか | 置換 |
|---|---|---|
| `we can V` | したのか、できるだけなのか曖昧 | `V`（したなら言い切る） |
| `aim to V` | 意図表明で結果がない | `V`（した結果を書く） |
| `try to V` | 同上 | `V` |
| `attempt to V` | 同上 | `V` |
| `may be useful` | noncommittal | 検証可能な条件付き言明に |
| `could potentially` | 冗長 | `could` または削除 |

---

## 4. 支持のない比較級・絶対化

| 避ける | なぜ悪いか | 置換 |
|---|---|---|
| `more accurate / robust / efficient` (対象なし) | more than what? | `more accurate than {specific baseline}` |
| `better` (対象なし) | better than what? | `outperforms X by Y on Z` |
| `significantly` (統計ではない場合) | 意味が薄い / misleading | 具体的な差分・比率 |
| `paramount` | 絶対化で反論の余地を失う | `central / necessary` など測れる語 |
| `unique` | 証明困難 | `new / novel` に置換、または具体的に何が unique か書く |
| `first to V` | 検証困難、fail すると反証される | 本当に最初と確認できるまで使わない |
| `a vast amount of` | 定量化されていない | `{N} examples` など |
| `extensively evaluate` | 自画自賛 | 削除して実験の具体性で示す |

---

## 5. we の濫用

| 避ける | なぜ悪いか | 置換 |
|---|---|---|
| `First we do X, then we do Y` (の連発) | we が過剰。方法が主語のはず | `The method first does X, then Y` |
| `In this section we describe` | section 自身が記述する | `This section describes` |
| `We are interested in X` | 読者は author の興味に関心がない | `X is important because ...` |

**原則**: 「人間が手作業でやったこと」だけ we。「method が実行すること」は method を主語に。

---

## 6. Zombie nouns（名詞化）

`-tion` / `-ity` / `-ment` / `-ance` / `-ance` の名詞化は動詞に戻す。

| 避ける（zombie） | 戻す（動詞） |
|---|---|
| `performed an analysis of` | `analyzed` |
| `made an observation that` | `observed that` |
| `gave a demonstration of` | `demonstrated` |
| `the maximization of X` | `maximize X` |
| `the implementation of X was done` | `X was implemented` → さらに能動化 |
| `utilization of` | `use` |
| `assessment of` | `assess` |

**原則**: 名詞化で「誰が何をした」が消えるとき、それは zombie。動詞に戻して主語を復活させる。

---

## 7. Style 小道具

| 避ける | 理由 | 置換 |
|---|---|---|
| `!` 感嘆符 | 科学論文では使わない | 削除 |
| `don't` / `it's` / `won't` | formal でない | `do not` / `it is` / `will not` |
| tense の混在 | 読者の負荷 | 本文は present tense、dataset 作成は past tense |
| `To that end` | end が曖昧なことが多い | 何の end か具体的に書く、または削除 |
| `Author et al. <space><space>[10]` | 余計な空白 | `Author et al.~\cite{Author}` |
| `[10] was the first to V` | 引用番号で文を始めない | `Author et al.~\cite{Author} were the first to V` |
| `state of the art` (初出で略) | 初出は spell out | `state of the art (SOTA)` 初出後 `SOTA` |

---

## 8. 一括 grep コマンド

Overleaf で作業している場合は main.tex にまとめて適用。LaTeX プロジェクトルートで:

```bash
# LLM-tell
grep -n -i -E "delve|showcase|unveil|pivotal|leverage|realm|seamlessly|paradigm shift|holistic|intricate|meticulous" *.tex

# 弱い hedge
grep -n -i -E "allows to|we can |aim to |try to |attempt to |may be useful|could potentially" *.tex

# 支持のない比較級
grep -n -i -E "more (accurate|robust|efficient|effective)[^a-z]|significantly[^-]|paramount|unique|first to" *.tex

# Zombie nouns (上位ヒット)
grep -n -E "utilization|implementation of|analysis of|assessment of|observation that|maximization of" *.tex

# Style
grep -n -E "!|don't|it's|won't|can't" *.tex

# we 濫用（1 パラグラフに 3 回以上の we は要注意）
grep -c -w -i "we" *.tex
```

grep で見つかった箇所を 1 つずつ、上表の置換パターンで書き直す。
機械置換は不可（文脈によって残して良いケースもある）。必ず人間が判断する。
