# Abstract Templates

Abstract は論文で最も投資対効果が高い箇所。ここが通らないと reviewer は本文を好意的に読まない。
2 つのテンプレートを使い分け、埋まった Abstract から Conclusion と Introduction を展開する。

## Contents

- どちらを使うか（decision guide）
- Variant A: Nature summary paragraph
- Variant B: Black Mad Libs（CVPR 系）
- 共通チェックリスト
- Worked examples

---

## どちらを使うか

| 対象 | 推奨 | 理由 |
|---|---|---|
| Nature / Science / Cell | **A** | 編集部が求める構造そのもの |
| CVPR / NeurIPS / ICML / ACL / SIGGRAPH | **B** | Black が CVPR 系で 30 年使ってきた実証済テンプレ |
| 境界（IJCV, TPAMI 等ジャーナル） | どちらでも | 字数制約に合う方を選ぶ |
| Position / Survey paper | **A** | thesis を段階的に展開する A が向く |

迷ったら **B** から始める。A への移植は容易。

---

## Variant A: Nature summary paragraph

Nature 編集部が公開している構造。専門外の研究者にも通じる粒度で書く。

```
[1–2 文 Context]    分野の重要性。専門外 CS 研究者に通じる粒度。
[2–3 文 Background] 主流アプローチの紹介。既存解 Y を名指す。
[1 文 Problem]      "However, Y suffers from Z when ...".
[1 文 Response]     "In this paper, we propose W, which ...".
[1 文 Method 要旨]  W が Z を回避する仕組みを 1 文で。
[1–2 文 Results]    "On {n datasets / k tasks}, W outperforms {baseline}
                     by +X% in {metric}".
[1 文 Evaluation]   既存 Y がなぜ失敗していたかを初めて説明する／示す／可能にする。
[1 文 Resolution]   この知見が次に何を可能にするか。
```

---

## Variant B: Black Mad Libs（CVPR 系に適合）

太字の接続詞を残して穴埋めすると GPS×2 が自然に現れる:

```
____ is widely used in {field} and has applications in ____.
Recent work has addressed this problem by ____.
**Unfortunately**, all of these approaches ____.
**In contrast**, we ____ (← insert nugget here).
This fixes ____, **however**, it does not solve ____.
**Consequently**, we further develop a novel ____.
**While promising**, ____ is non-trivial.
**Therefore**, we ____.
We evaluate ____ qualitatively and quantitatively on ____ and
find that it is more accurate than {specific baseline}.
Code and data will be available for research purposes.
```

GPS の対応:

- **Goal** = 冒頭
- **Problem 1** = "Unfortunately"
- **Solution 1** = "In contrast, we"（← ここに Nugget を入れる）
- **Problem 2** = "While promising"
- **Solution 2** = "Therefore"

Abstract を書いたら Introduction と Conclusion はほぼ自動で書ける。

---

## 共通チェックリスト（コピペして確認）

```
Abstract review:
- [ ] 150–250 words に収まっている
- [ ] 1 文目で "field × application" が見える（we 主語ではない）
- [ ] However / Unfortunately で problem が明示されている
- [ ] Here we / In contrast / We propose で solution が明示されている
- [ ] Nugget（見方の転換）が 1 文で読める
- [ ] 数値結果が少なくとも 1 つ含まれる（+X% / ×k speedup / etc.）
- [ ] 比較対象（baseline 名）が明示されている
- [ ] 最後に "what does this enable next" の 1 文がある
- [ ] 禁則句（delve, showcase, allows to, paramount, ...）が含まれない
     → phrase-bans.md で grep
```

---

## Worked examples

### Example 1: Mad Libs で埋めた Abstract（架空の点群処理論文）

> 3D point cloud registration is widely used in robotics and has applications in autonomous
> driving and AR/VR. Recent work has addressed this problem by learning global descriptors
> with deep networks. **Unfortunately**, all of these approaches collapse under partial
> overlap because the descriptor aggregation assumes the two point sets share geometry
> everywhere. **In contrast**, we observe that overlap detection and correspondence can be
> cast as a single mutually reinforcing optimization rather than two sequential stages.
> This fixes the partial-overlap failure, **however**, it does not solve the scaling issue
> when one cloud is an order of magnitude larger. **Consequently**, we further develop a
> hierarchical variant that retains accuracy at 10× scale imbalance. **While promising**,
> training such a joint objective is non-trivial because the two losses compete during
> warm-up. **Therefore**, we introduce a curriculum that gates the overlap loss by
> correspondence confidence. We evaluate the method on 3DMatch, KITTI, and ScanNet and
> find that it is 4.1% more accurate than the state of the art under partial overlap and
> 2× faster at inference. Code and pretrained models will be available for research
> purposes.

Nugget = 「overlap 検出と対応付けを別々に解くのではなく、相互補強する一つの最適化として解く」

### Example 2: Nature paragraph で書いた同じ論文

> Robots must fuse sensor measurements across space to build maps; point cloud registration
> is the basic operation behind this fusion. Deep-learning approaches currently dominate
> the benchmark by learning global geometric descriptors. However, when the two point sets
> overlap only partially — the norm outside controlled laboratory settings — the
> descriptor aggregation step averages away the shared geometry it is meant to find.
> Here we show that overlap detection and correspondence estimation can be cast as a
> single joint optimization in which each task supplies the supervision that the other
> lacks. A hierarchical variant retains this property under 10× scale imbalance.
> On 3DMatch, KITTI, and ScanNet, the joint formulation improves registration recall
> by 4.1% under partial overlap and halves inference time. The result exposes why prior
> sequential pipelines were bottlenecked not by descriptor quality but by their inability
> to revisit the overlap estimate once correspondences are found. The approach opens a
> path to fully online mapping where overlap changes at every frame.

同じ contribution が、A は「科学的発見としての意義」を末尾で強調し、B は「問題 → 解 → 問題 → 解」
のリズムで攻めている。分野に合わせて選ぶ。

---

## よくある失敗

- **we 主語で始める**: "We study X" → NG。"X is important because ..." で始める。
- **Problem が "Unfortunately" まで出てこない**: Background が長すぎる。1 段落目を 2 文に削る。
- **Nugget と technical contribution を混同**: "We propose a novel transformer" は
  technical contribution であって Nugget ではない。「なぜ transformer がここで効くか」
  の insight を書く。
- **Resolution 文が欠落**: 最後が結果数値で終わっている。「この結果が何を可能にするか」を 1 文足す。
