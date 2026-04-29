---
name: lgtm-loop
description: >
  実装・レビュー (Codex MCP / GPT)・修正の反復ループ。
  ユーザーの意図する機能が動くこと (= 機能ゲート pass) と Codex の LGTM を AND で満たすまで回す。
  タスク説明 / plan ファイル / 既存 diff のいずれを起点にしてもよい。
  実装フェーズは Karpathy 4 原則 (think before / simplicity / surgical / goal-driven) に従う。
  "lgtm loop", "LGTMまで回す", "実装してレビューして直して", "実装と修正をループで" などで呼び出す。
user-invocable: true
argument-hint: "[task description | plans/foo.md | empty for review-only]"
allowed-tools: Bash(*), Read, Edit, Write, Grep, Glob, Skill, mcp__codex__codex, mcp__codex__codex-reply
---

# LGTM Loop: 実装・レビュー・修正の反復

ユーザーが意図する機能を実装し、Codex (GPT) によるレビュー → 修正 → 再レビューを LGTM 達成まで反復する。
最終ゴールは **ユーザーの意図する機能が動くこと**。LGTM はそれを補強するコード品質の安全網であり、ゴール自体ではない。

## Context: $ARGUMENTS

## 定数

- MODEL = `gpt-5.5`
- REASONING_EFFORT = `xhigh`
- MAX_ITERATIONS = `10`

`mcp__codex__codex-reply` を直接呼ぶときは以下を付与:

```
config: {"model": "gpt-5.5", "model_reasoning_effort": "xhigh"}
```

## 前提

- Codex MCP Server が登録済み (`./nanokit codex-install` で自動登録)
- `mcp__codex__codex` / `mcp__codex__codex-reply` が利用可能
- `/codex-review` skill が同じ nanokit 配下に存在 (Step 3 の 1 ラウンド目で skill 経由で呼ぶ)
- `karpathy-guidelines` skill が同居していると望ましい (Step 1b で auto-invoke 想定)。なければ本文 4 原則を inline 参照

## Step 0: 起点モード判定

`$ARGUMENTS` から 3 モードを分岐:

| 引数の形 | モード | 開始ステップ |
|---|---|---|
| 空 | review-only | Step 2 から (既存 diff を REVIEW へ) |
| `plans/*.md` のパス | plan-driven | Step 1a から (plan を読んで CRITERIA + IMPLEMENT) |
| それ以外のテキスト | task-driven | Step 1a から (引数を要件に CRITERIA + IMPLEMENT) |

review-only モードでは Step 1a / 1b を skip。既存の uncommitted/branch diff にループ (GATE → REVIEW → FIX) をかける。

## Step 1a: CRITERIA — 受け入れ基準を確定

ループの最終ゴールは「ユーザーの意図する機能が動くこと」。タスクから具体的に何が動けば成功かを最初に書き出す。

抽出すべき内容:
- 機能の入出力例 / 受け入れシナリオ (例: 「ログインフォームに不正な email で 422 が返る」)
- 検証手段 (新規 test / 既存 test / 手動確認手順)
- 失敗条件 (どうなったら未完了とみなすか)

曖昧なときは Karpathy 「Think Before Coding」に従い、ユーザーに 1 度確認する。仮定したまま実装に入らない。

## Step 1b: IMPLEMENT — 実装

review-only モードでは skip。`karpathy-guidelines` skill (4 原則) を必ず適用:

1. **Think Before Coding** — 仮定を明示し、不明点はユーザに確認してから書き始める
2. **Simplicity First** — 要求された分だけ書く (speculative な抽象化禁止)
3. **Surgical Changes** — 触れる必要のある行だけ変更、既存スタイル踏襲
4. **Goal-Driven Execution** — Step 1a の受け入れ基準を成功条件として実装。
   「test を先に書いてから実装を通す」を基本動作とする
   (例: "Add validation" → 不正入力に対する test を書く → make them pass)

実装の進め方:
- task-driven: 引数のタスクを 5–15 個の小さな Edit に分けて実装
- plan-driven: plan の phase ごとに実装し、各 phase 後に Step 2 を回す
- 「前置き 1 文 + 実装 + 軽い確認」のリズムを保つ

## Step 2: GATE — 機能ゲート + 品質ゲート

ゲートは 2 段階。**両方 pass** しなければ Step 3 (REVIEW) に進まない。Codex を呼ぶのは GATE green が前提。

### 2a. 機能ゲート

Step 1a で立てた受け入れ基準を満たしているか:
- 新規 test を実行し pass を確認
- 受け入れシナリオを手動 / 自動でなぞる
- fail → Step 1b に戻って実装を直す (Karpathy "Surgical Changes" 厳守)

### 2b. 品質ゲート

リポジトリ標準のチェックを順に試行:
1. `pixi run check` が定義されていれば最優先
2. なければ `pixi run lint` + `pixi run typecheck` + `pixi run test-unit` を順に
3. pixi 不在なら `make test` / `npm test` / `pytest` をフォールバック
4. プロジェクトのチェックコマンドが特定できなければ、ユーザーに 1 度確認

fail → 修正してから再実行。

## Step 3: REVIEW — Codex によるレビュー

### 1 ラウンド目: `/codex-review` skill 経由

```
Skill ツール:
  skill: codex-review
  args: <空 (staged diff) or "HEAD~1" or 特定ファイルパス>
```

`/codex-review` の応答末尾には `threadId: <id>` 行が含まれる (codex-review SKILL.md ルールで明文化済み)。
**この threadId をローカル変数に保持** し、2 ラウンド目以降の `mcp__codex__codex-reply` で再利用する。

### 2 ラウンド目以降: `mcp__codex__codex-reply` 直叩き

`/codex-review` skill は毎回新 thread を立てる仕様なので、継続レビューには MCP を直接呼ぶ。

```
mcp__codex__codex-reply:
  threadId: <Step 3 ラウンド 1 で得た threadId>
  config: {"model": "gpt-5.5", "model_reasoning_effort": "xhigh"}
  prompt: |
    前ラウンドの指摘について以下のとおり修正しました。

    ## 修正サマリ
    - [HIGH N]: <対応内容>
    - [MEDIUM M]: <対応内容>
    ...

    ## 最新 diff
    ```diff
    <git diff の出力>
    ```

    変更全体を再レビューし、残存する問題があれば指摘してください。
    すべて解消されていれば「LGTM」と明記してください。
```

plan-driven モードのときは prompt に 1 行追加: 「plans/foo.md からの逸脱があれば併せて指摘してください」。

## Step 4: FIX — 指摘の整理と修正

- Codex 応答から `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` を抽出し、`TaskCreate` で 1 件 1 タスクに分解
- **CRITICAL** がある場合は自動修正前にユーザーに確認 (重大変更は人間が判断)
- **HIGH / MEDIUM / LOW** は AUTO で順次修正 (ただし Karpathy "Surgical Changes" 厳守、無関係な refactor 禁止)
- Edit / Write で修正を適用
- 修正後は必ず Step 2 (GATE) に戻って機能ゲート + 品質ゲートを再実行

## Step 5: ループ判定

成功終了条件は **AND** (3 点すべて満たす):

1. 機能ゲート (Step 2a) pass — 受け入れ基準を満たしている
2. 品質ゲート (Step 2b) pass — リポジトリ標準チェックが green
3. Codex 応答に "LGTM" を含む — コード品質に重大な指摘なし

どれか 1 つでも未達なら Step 2 → 3 → 4 をもう 1 周。
反復回数 `>= MAX_ITERATIONS (=10)` に達したら現状を整理してユーザーに判断委ね。

**注意:**
- Codex が LGTM を返しても機能ゲート fail なら未完了 (機能未実装の可能性)。実装に戻る。
- 機能が動いていても Codex の CRITICAL/HIGH が残っていれば未完了。修正に戻る。

## ルール

- Codex の指摘を勝手に却下しない (反論はしてよいが threadId 経由で再議論する)
- Claude のレビューと Codex のレビューは混ぜない — Codex の指摘をそのまま提示し対応する
- threadId は session 内で保持。別セッションへ持ち越さない
- diff が 500 行を超える場合はファイル単位で分割レビュー (codex-review 同様)
- 各 FIX 後は GATE 通過を確認してから Codex を再度呼ぶ (失敗ゲートのまま re-review しない)
- IMPLEMENT 中は Karpathy 4 原則を最優先。speculative な機能追加・無関係 refactor は禁止
- Codex の提案でも Karpathy 原則違反 (新機能追加・余計な抽象化等) なら却下を検討し、ユーザーに判断仰ぐ

## 終了時の出力

成功時:
```
## LGTM Loop 完了

- 反復回数: N ラウンド
- 機能ゲート: pass (受け入れ基準すべて満たす)
- 品質ゲート: pass (lint + typecheck + test green)
- Codex: LGTM
- 総修正件数: M 件 (CRITICAL 0 / HIGH a / MEDIUM b / LOW c)
```

中断時 (MAX_ITERATIONS 到達 or ユーザー判断要):
```
## LGTM Loop 中断

- 反復回数: N ラウンド (上限 10)
- 機能ゲート: pass / fail
- 品質ゲート: pass / fail
- Codex: 残存指摘 K 件 (CRITICAL a / HIGH b / ...)
- 最終 Codex 応答: <要約>

ユーザーの判断を仰ぎます。
```

## 使い方の例

```
/lgtm-loop                                   # 既存 diff をループ (review-only)
/lgtm-loop add JWT auth to /login            # タスク説明から (task-driven)
/lgtm-loop refactor parse_url to use urllib  # task-driven
/lgtm-loop plans/auth-jwt.md                 # plan ファイル駆動 (plan-driven)
```

## 関連 skill

- `karpathy-guidelines` : IMPLEMENT 中の行動規範 (4 原則)
- `codex-review`        : 1 ショットレビュー (loop 不要時)。本 skill が round-1 で委譲する
- `codex-discuss`       : 実装前の設計議論
- `git-commits`         : LGTM 後のコミット粒度整理

## 補足: codex-review 仕様変更との連動

本 skill は `/codex-review` の出力フォーマット (CRITICAL/HIGH/MEDIUM/LOW + 末尾 threadId) を前提に書かれている。
`codex-review/SKILL.md` の出力形式が変わったら、本 skill の Step 3-4 のパース手順も併せて更新すること。
