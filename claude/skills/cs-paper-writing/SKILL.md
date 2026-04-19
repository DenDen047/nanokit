---
name: cs-paper-writing
description: Drafts, reviews, and rewrites computer-science research papers (CVPR/NeurIPS/ICML/ACL/SIGGRAPH style). Use when writing or critiquing CS papers, abstracts, introductions, related work, or paragraphs; when asked to structure a contribution around a "nugget" / Problem-Solution / Goal-Problem-Solution pattern; when filling a Nature summary-paragraph or Michael Black Mad Libs abstract; when removing LLM-tell (delve, showcase, allows to, ...) or zombie nouns. Triggers include "論文 執筆", "論文 査読", "論文 添削", "abstract template", "paper skeleton", "introduction review", "related work grouping".
user-invocable: true
---

# CS Paper Writing: 情報科学論文の執筆方針

## TL;DR

> 読者の頭を変えるために、Nugget（核 insight）を1文で言語化し、
> Figure 1 と Abstract を最初に固め、
> Goal → Problem → Solution を入れ子で繰り返し、
> 削れるものはすべて削る。

## 参照ファイル（progressive disclosure）

本 SKILL.md は全体方針のナビゲーション。詳細は必要時に下記を読む。
各ファイルは **いつ参照するか** をタグで示している:

- [references.md](references.md) — **出典を辿る時**。一次出典（Black, Freeman, Keogh, Peyton Jones, 松尾ぐみ, Neubig）と古典の完全書誌
- [abstract.md](abstract.md) — **Abstract を書く / 直す時**（§8 Step 3）。Nature paragraph / Black Mad Libs の 2 テンプレと worked example
- [phrase-bans.md](phrase-bans.md) — **最終稿の grep 書き直し時**（§8 Step 7–8）。LLM-tell / zombie nouns / 禁則句の完全リストと grep コマンド
- [sections.md](sections.md) — **Related Work / Method / Experiments / Discussion / Conclusion を詰める時**。節ごとの具体的な書き方
- [production.md](production.md) — **Title / Acronym / Figures / Sup. mat. / Video を整える時**。パッケージング要素一式
- [black-practical.md](black-practical.md) — **(a) 着手前の pre-write questionnaire**、**(b) 共著者作業の分担を決める時**、**(c) deadline 72 時間前の triage**、**(d) 最終 proofreading 段階**（§8 Step 9–11）。Michael Black の実践則のうち他ファイルで扱わない節目の判断と endgame の規律

---

## 1. 立脚点（Why）

論文の目的は **読者の頭を変えること**。
自分の思考整理でも、研究内容の網羅的記録でもない。
読者にとっての価値がなければ、内容が正しくても載らないし読まれない（McEnerney）。

執筆中に常に問うべきは「これは正しいか？」ではなく
**「これは読者の問題を動かすか？」**（McEnerney）、
**"So what?"**（Keogh）である。

> **Conferences do not accept results. They accept papers.**（Black）

結果が良いだけでは通らない。論文として読者の頭を動かせて初めて通る。

---

## 2. 構造原理（GPS = Goal → Problem → Solution）

すべての階層を同じパターン **`Goal → Problem → Solution → Repeat`**（以下 GPS）で組む。
これは Hoey の S-P-R-E（Situation-Problem-Response-Evaluation）の CS 向け呼称（Black）。

| 階層 | G | P | S / E |
|---|---|---|---|
| 論文全体 | Intro 前半 | Intro 後半 | Method + Results → Discussion |
| 各節 | 節冒頭の目的 | 節が解く sub-problem | 節の提案 + 支持 |
| 各段落 | 冒頭文（= message） | message を支える論証 | 具体例・数式・図で evaluation |
| Abstract | Context | However, ... | Here we ... |

「上位の S が下位の G として再帰呼び出しされる」**フラクタル構造**。
読者はどの階層から入っても同じ形に出会うので迷わない。

GPS は物語構造（恋愛譚・英雄譚・冒険譚）と同型で、読者の認知パターンと共鳴する（Black）。
`problem → solution → problem → solution` のリズムで階層的に insight を渡していく。

---

## 3. 方針の 4 本柱

### A. Nugget first（insight の言語化）

**Nugget = 「世界の見方を変える 1 つの insight」** であり、
**technical contribution とは別物**（Black）。

- technical contribution: 「何を作ったか／何が速くなったか」
- Nugget: 「解けなかった問題を解ける問題に reformulate した視点」

典型パターン（Reese's Peanut Butter Cup）:
「X も Y も難しいが、X と Y を組み合わせると実は簡単になる」。

**Nugget 1 文テンプレート**:
> Previous work treats X as {old framing}. We observe that X is actually {new framing}, which makes {unsolvable problem} {tractable}.

執筆前に自分に問う（Black's pre-write questionnaire）:

- この研究の goal は何で、なぜ読者が care するか？
- hypothesis は何か？ testable か？
- **Nugget（見方の転換）は何か？** 1 文で書けるか？
- Elevator pitch（3 文以内）は？
- Teaser（1 枚絵）は何を見せる？
- 既存手法の「何が」間違っているか？
- 実験で何を定量化するか？
- デモ（存在証明）は何か？

Nugget が言語化できていない原稿は、どれだけ実装を磨いても読者に insight が届かない。

### B. Outline first

本文より先に **Figure 1 と各節の 1 文サマリー** を確定させる（Whitesides, Peyton Jones）。
CS では **Figure 1 = contribution の絵 / system overview** と Abstract の確定が、執筆全体のアンカー。
placeholder としてホワイトボードの写真を本文に貼ってから書き始めるのも有効（Black）。

Black の追加推奨: **論文より先に talk を書く**。
talk は text が最小で済むので、説明の自然な順序が強制される。talk の順 = 論文の順にする。

### C. Recursive Problem-Solution

新情報を出す前に、必ず読者の中に **「これは未解決の問題だ」** という認知を作る。
`However` / `Yet` / `Despite` で問題を顕在化してから、
`Here we` / `We propose` で解を渡す。
このリズムを論文・節・段落のすべてで反復する。

### D. Minimalism for clarity

削れる語・段落・節は削る。
装飾的な接続詞、名詞化（zombie nouns）、受動態、専門用語は読者の負荷を増やす。
**読者の認知コストを下げることが clarity であり、clarity が value の前提**
（McCarthy, Sword, Orwell, Pinker）。

LLM が書いた文はしばしば「文法は正しいが insight が薄い」（Black）。
`delve` / `showcase` / `allows to` などの LLM-tell を徹底除去する → [phrase-bans.md](phrase-bans.md)。

---

## 4. 論文タイプを先に決める

CS 論文は必ずしも「技術的貢献」型ではない。投稿前に自分の論文がどれかを決め、
その型の評価基準で自分を測る。

| タイプ | 貢献 | 成功の尺度 |
|---|---|---|
| **Technical** | 新手法・性能・単純化 | SOTA / ablation / 理論保証 |
| **Method** | 研究コミュニティ向けツール | 採用数・再現性・使いやすさ |
| **Data / Benchmark** | 新しいデータ・評価軸 | 規模・品質・影響範囲 |
| **Position / Survey** | 整理・問題提起 | フレーミングの斬新さ |

混ぜると contribution が曖昧になる。型を 1 つに絞り、型に合った baseline / 評価を選ぶ。

---

## 5. 全体骨格（CS 論文 = IMRaD + α）

```
Title          ← 12 語以内、検索キーワード + できれば acronym
Abstract       ← Nature paragraph / Mad Libs (150–250 words, GPS×2)  → abstract.md
Teaser Figure  ← 1 枚絵で nugget を伝える（Fig. 1 相当）              → production.md
1. Introduction      ← CARS (territory → niche → occupy) + GPS 反復
2. Related Work      ← 末尾可、テーマで grouping、teach the history   → sections.md
3. Problem Formulation / Preliminaries
4. Method            ← Fig 1 で全体像、節分けで GPS を反復             → sections.md
5. Experiments       ← Setup / Baselines / Results / Ablation          → sections.md
6. Discussion / Limitations
7. Conclusion        ← 1 段落で GPS を再演
References / Appendix (Reproducibility checklist)
Supplemental (video, 追加比較, 失敗例)                                 → production.md
```

各節の **内部も** GPS を繰り返す（= フラクタル）。

---

## 6. Introduction の GPS 反復（CARS 実装）

```
段落 1: Territory      この分野はなぜ重要か。応用例で示す。
                       "We are interested in X" ではなく
                       "X is important because ... and is unsolved because ..."
段落 2: Background     既存解の系譜（段落 2 自体が小 GPS）
段落 3: Niche/Problem  既存解の限界。"However" / "Yet" / "Despite" で開く。
段落 4: Occupy         我々の提案。**Nugget を 1 文で明示**。
                       Contribution リスト（箇条書き）。
段落 5 (任意): Roadmap "Section 2 ... Section 3 ..." の案内。
                       短い論文なら省いて良い（Black）。
```

第 1 文は個人ではなく問題から始める。「我々は X に興味がある」ではなく
「X は重要で、かつ未解決である」。

---

## 7. 段落・文レベル（毎段落チェックリスト）

| ルール | 出典 |
|---|---|
| 1 段落 = 1 メッセージ。冒頭文がそのメッセージ。 | McCarthy, Mensh-Kording |
| 文の主語 = 段落の主役。文末（stress position）に新情報。 | Gopen-Swan |
| Old → New の連鎖を保つ。前文の末 = 次文の頭。 | Gopen-Swan |
| 名詞化（`-tion`, `-ity`, `-ment`）は動詞に戻す。 | Sword |
| 専門用語は初出で必ず 1 文の砕いた言い換え。 | Pinker |
| 削れる語は削る、能動態優先。 | Orwell, McCarthy |
| tense は統一（原則 present）。勝手に過去・現在を混ぜない。 | Black |

禁則句と置換例の完全リストは [phrase-bans.md](phrase-bans.md) を参照。

---

## 8. 執筆工程（コピペして progress を追える checklist）

新規ドラフト着手時は下記を本文横に貼り、完了したら `[x]` で消していく:

```
Paper writing progress:
- [ ] Step 0: Pre-write questionnaire に答える
          → black-practical.md §1
- [ ] Step 1: Nugget を 1 文で書く（§3A のテンプレートに埋める）
- [ ] Step 2: Figure 1 の placeholder を作る（ホワイトボード写真で可）
- [ ] Step 3: Abstract を Mad Libs または Nature paragraph で埋める
          → abstract.md
- [ ] Step 4: 各節 1 文サマリーを作り共著者に skeleton 承認を得る
          → black-practical.md §4（co-authors とのやり取り）
- [ ] Step 5: Abstract → Conclusion → Intro → Method → Experiments の順で本文
- [ ] Step 6: 各段落を 25% 削る（McCarthy）
- [ ] Step 7: Zombie 除去: `-tion` / `-ity` / 受動態を grep
          → phrase-bans.md
- [ ] Step 8: LLM-tell 除去: delve / showcase / allows to ... を grep
          → phrase-bans.md
- [ ] Step 9: Proofreading discipline — every word を読む
          → black-practical.md §7
- [ ] Step 10: Outsider test — 専門外 CS 研究者に Intro だけ読ませ、
          3 分で「何の問題を解いたか」を言わせる
- [ ] Step 11: 8 ページ目いっぱいに詰める（7.5 で止めない）
          → black-practical.md §7 (page management)
```

Deadline が迫っていて results が理想通りでない場合は
先に [black-practical.md §7 (Dance with who brung ya)](black-practical.md) で triage する。

原則:
- **Don't wait, write**（Peyton Jones, Black）: 研究最初の週に Abstract と Figure 1 のスケッチ。"shitty first draft" でよい。
- **Dance with who brung ya**（Black）: deadline 前は手元の nugget で最善の story を語る。野心を dropping して得られるものは多い。

---

## 9. 自己レビュー（迷ったら立ち戻る問い）

| 局面 | 問い |
|---|---|
| 段落を残すか削るか | この段落がないと読者は何を理解できなくなるか？ |
| 用語を残すか言い換えるか | この用語の初出時、読者は意味を推測できるか？ |
| 文を能動か受動か | 主語は段落の主役か？ |
| 結果を本文か Appendix か | これは contribution の主張に必須か？ |
| 関連研究をどこに置くか | これを読まないと我々の問題が理解できないか？ |
| 残りの時間で何をするか | 今ある nugget で最善の story を語る準備は整ったか？ |

すべての問いは **「読者の頭の中で何が起きるか」** に収束する。

---

## 使い方（このスキルの起動例）

- 新規ドラフト着手: 「この研究で論文を書きたい。`cs-paper-writing` の方針で
  まず black-practical.md §1 の pre-write questionnaire を埋めて、
  Nugget を 1 文化し、Figure 1 と Abstract (Mad Libs) のスケルトンを作って」
- 既存原稿レビュー: 「`cs-paper-writing` の GPS 観点で Introduction を査読して」
- 段落リライト: 「この段落を `cs-paper-writing` のチェックリストで直して」
- Abstract 整形: 「`cs-paper-writing` の abstract.md テンプレで Abstract を組み直して」
- LLM-tell 除去: 「phrase-bans.md の禁則句リストで本文を grep して書き直して」
- Related Work 整理: 「laundry list になっている Related Work を sections.md の方針で grouping し直して」
- Deadline 前 triage: 「残り 3 日で results が理想と違う。black-practical.md §7 で
  今ある nugget から triage して、語れる最善の story を決めて」
- 最終 proofreading: 「black-practical.md §7 の proofreading checklist で
  本文と bibliography を洗う」

---

## アンチパターン

- **Nugget なし**: technical contribution は書けているが、insight が言語化されていない。
- **記録としての論文**: 自分がやったことを時系列で全部書く。読者の問題と切り離されている。
- **Related Work 先出し**: Intro 冒頭で先行研究を並べ、自分の問題が遅れて出てくる。
- **Related Work = laundry list**: 系譜と批評になっておらず列挙だけ。
- **解決策の先出し**: 問題を顕在化する前に解を提示し、読者が「なぜこれが要るのか」を理解できない。
- **段落 = 複数メッセージ**: 1 段落に 2 つ以上の主張を詰め、冒頭文がメッセージになっていない。
- **Zombie 過多**: 名詞化と受動態が連続し、誰が何をしたか追えない。
- **LLM-tell 氾濫**: `delve`, `showcase`, `allows to` など LLM 語彙が残る。
- **Method と data を同時に変える ablation**: 何が効いたか分からない。
- **equation と code の不一致**: 実装を隠そうとして破綻する。
- **再現性情報の本文埋め込み**: ハイパラ表や seed が本文を膨らませ、主張のリズムを崩す。
- **ページが 7.5 で止まっている**: 足りない印象を与える。8 ページに詰める。
- **video が論文の静止図の貼り合わせ**: 時間軸を使えていない。
