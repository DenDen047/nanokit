# Black Practical: Michael Black の実践則

[Michael Black, Writing a good scientific paper](https://medium.com/@black_51980/writing-a-good-scientific-paper-c0f8af480c91) の
実践ノウハウのうち、他ファイルで扱わない「節目の判断」と「endgame の規律」をまとめる。
Black の原記事セクション順に並べ、既存ファイルで詳述済みの項目はクロスリファレンスに留める。

## 参照タイミング

- **着手前**: §1 pre-write questionnaire で research の輪郭を固める
- **共著者作業の前**: §4 co-authors でやり取りの作法を確認
- **手が止まった時**: §2 biggest mistake で「書かない」罠を自覚する
- **手本を探す時**: §3 で award-winning paper から構造を学ぶ
- **reviewer 視点で見直す時**: §6 strategy でレビュアーの job に empathize
- **deadline 72 時間前**: §7 end game で triage と proofreading を実行
- **投稿直後**: §8 final thought

## Contents

- 1. Before you start: pre-write questionnaire
- 2. The biggest mistake: not writing
- 3. Learn by reading great papers
- 4. Working with co-authors
- 5. Basics of writing: rhythm and polish
- 6. Strategy: reviewer empathy & over/underclaim
- 7. The End Game: final 72 hours
- 8. Final thought: have fun

---

## 1. Before you start: pre-write questionnaire

研究の最初の週に、下記すべてに回答を書く。どれか 1 つでも埋まらないなら、
その研究は論文の体をなす前に設計の穴がある。

```
Pre-write questionnaire:
- [ ] Goal: What is the goal and why do people care?
- [ ] Audience: Who will use or build on this?
- [ ] Hypothesis: "My hypothesis is ..." — is it testable?
         How will I know whether it is true?
- [ ] Impediment: What problem means this has not been done yet?
- [ ] Nugget: What key insight makes it doable? (→ SKILL.md §3A)
         1 文で書き出す。technical contribution と混同しない。
- [ ] Elevator pitch: 3 sentences or fewer to a senior scientist.
- [ ] Teaser: What single image explains the core idea? (→ production.md §3)
- [ ] Key prior works: What do they get right? What do they get wrong?
         Limitations in prior work point the way forward.
- [ ] Quantitative evaluation: What will I measure and compare against?
- [ ] Demo: How do I show the idea works?
- [ ] Key risks: What could invalidate the project?
- [ ] Data: Do I already have everything I need?
```

Hypothesis を明示することで、「数字を少し良くするだけ」の incremental engineering trap を避けられる。

---

## 2. The biggest mistake: not writing

> **Conferences do not accept results. They accept papers.**

- どれだけ結果が良くても、論文になっていなければ通らない
- 論文執筆は実験より時間がかかる。「提出日に書けばいい」で失敗する
- 1 本の論文は税金換算でおよそ 100K EUR のコスト。雑に扱わない
- **Shitty first draft** を研究 1 週目に書く。grammar は無視して論理構造だけ通す
- Intro は結果が無くても書き始められる。早く書くことで自分の思考が整理される

---

## 3. Learn by reading great papers

- 賞を取った論文（best paper / test-of-time）を 1 本選び、構造を分析する
- 問い:
  - 著者は何をしたか？
  - なぜ自分はこの論文を好きになったか？
  - 導入の順序はどう組まれているか？
  - Figure 1 は何を見せているか？
- 好きな論文の骨格を模倣することから始める（ゼロから設計するより速くて上手い）

---

## 4. Working with co-authors

First author は heavy lift をする覚悟を持つ。

### 共著者（特に senior）を正しく使う

- **crap を渡して "ready for your pass" は最悪**。copy-edit で時間を浪費させる
- 磨いた版を渡し、**macro の論証を refine する** ことに集中してもらう
- senior co-author は他の締切も抱えている。respect their time
- 「誰が著者か／著者順」の議論は別。本ファイルでは扱わない

### 実務的な渡し方

1. Abstract + Figure 1 + section 1 行サマリーで skeleton 承認を得る（SKILL.md §8 Step 4）
2. Full draft を渡す前に、自分で §7 の proofreading を 1 周している
3. コメント返しは macro → micro の順に処理する

---

## 5. Basics of writing: rhythm and polish

Black の具体則のうち、既存ファイルで詳述済みのものと未収録のものを整理:

### 既存ファイルに詳細

- Text + Equation + Figure の 3 方式は補完関係 → [sections.md §2](sections.md)
- 禁則句（`allows to`, `we can`, `paramount`, `to that end`, contractions, 感嘆符） → [phrase-bans.md](phrase-bans.md)
- tense 統一（present 原則） → [phrase-bans.md §7](phrase-bans.md)
- Acronym / Title → [production.md §1-2](production.md)
- Figure の置き方 → [production.md §4](production.md)

### 本ファイル固有

- **All good papers start as bad papers**: 初稿は必ず悪い。書き直して良くなる前提で書き始める
- **Paper rhythm**: text → equation → figure のブロック反復が単調を破り、読者の脳に休憩を与える。論文には rhythm があり、良い論文にはそれがある
- **Polish matters**: 貧弱な prose / ぞんざいな参考文献 / 醜い figure / 混乱した notation は、
  無意識に reviewer の印象を下げる。内容以前に「この著者は細部に気を配る人か」で判定される
- **Capitalization consistency**: section heading の大文字化は好みで良いが、**統一する**。
  一貫性の欠如は「他の細部も雑」という subtext を発信する

---

## 6. Strategy: reviewer empathy & over/underclaim

### Reviewer empathy

Reviewer は時間に追われた人間。彼らの job を楽にする:

- 投稿先の **reviewer guidelines を読む**
  （例: [CVPR Reviewer Guidelines](https://cvpr.thecvf.com/Conferences/2024/ReviewerGuidelines)）
- レビュー用紙の質問に対応する材料を本文に明示する:

| Reviewer form 質問 | 本文で先回りする置き方 |
|---|---|
| "Summary in 3–5 sentences" | `Our key ideas are ...` / `Our contributions are ...` の段落を Intro 末尾に |
| "Strengths: key ideas / experimental validation / significance" | これらの語を Intro と Conclusion で実際に使う |
| "Weaknesses: prior art / experiments" | Limitations 節で先回りし、future work として位置づける（[sections.md §4](sections.md)） |

### Overclaim / underclaim のバランス

- **Overclaim** で reviewer は引く:
  - `we are the first to ...`（検証困難）
  - `paramount importance`（絶対化）
  - `unique`（反証されやすい）
  → [phrase-bans.md §4](phrase-bans.md)
- **Underclaim** で novelty が埋もれる:
  - "contributions" 段落を必ず設けて、何が新しいかを明言する
  - `towards` / `on` は慎重に使う（準備的研究なら OK、本論で使うと novelty が薄まる）

---

## 7. The End Game: final 72 hours

### Triage — Dance with who brung ya

> Deadline まで 3 日。results は理想通りでなく、cluster も混雑。

- この段階で award-winning の夢を追わない
- 手元に残った nugget で語れる最善の story を語る
- smaller story の方がしばしば良い story になる（focus が明確になる）
- what you have にフォーカスする（what you don't have ではなく）

### Proofreading discipline

Black の proofreading rule は極めて厳しい:

```
Final proofreading checklist:
- [ ] Read EVERY word — title, caption, equation, bibliography
- [ ] 初見の reviewer のつもりで読む（acronym も math も文献も知らない前提）
- [ ] 複数人で読む（=事前に書き終えている必要がある）
- [ ] Bibliography を grep:
      grep -n "?" main.tex          # 参照切れ
      grep -n "\[\?\]" main.tex     # 未解決引用
- [ ] 参考文献の番号順 sort: \usepackage[numbers,sort,compress]{natbib}
      （[3, 9, 23] であって [23, 9, 3] ではない）
- [ ] 参考文献の最新版に更新（CVPR 採録後は arXiv 版ではなく CVPR 版を引く）
- [ ] 参考文献に最低 1 つの誤りはあると想定して探す（経験則）
```

### Page management（9 → 8 ページ圧縮）

- 段落末尾が 1–2 語で終わっている箇所を rework する。ほぼ必ず短く・明確にできる
- 数式 `E(x,y,z) = ...` の `E(x,y,z) =` を前段の文末に持ち上げて 1 行稼ぐ
- `\vspace{-Xmm}` の乱用は禁物。圧縮した結果として section title が前 page に上がる方が自然
- LaTeX の spacing は非線形。微修正で大きく page 数が動く
- `\begin{figure}[t]` 統一で vspace を節約（[production.md §4](production.md)）

### Fill the 8 pages

- 7.5 ページで止めない。「足りない」「finished でない」と reviewer に印象づける
- 埋めるために水増ししない。削った分、未収録だった insight や ablation を補う

---

## 8. Final thought: have fun

> Paper writing during a deadline can be stressful but it can also be an exhilarating,
> shared experience. — Black

Deadline 前の論文執筆は共同作業の最も濃密な瞬間のひとつ。
quality を追いながらも、共著者と一緒にこの時間を楽しむ姿勢そのものが
次の良い論文を書ける素地を作る。
