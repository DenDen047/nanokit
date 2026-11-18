---
name: lgtm-loop
description: >
  実装・レビュー (Codex / GPT)・修正の反復ループ。
  ユーザーの意図する機能が動くこと (= 機能ゲート pass) と Codex の LGTM を AND で満たすまで回す。
  タスク説明 / plan ファイル / 既存 diff のいずれを起点にしてもよい。
  実装フェーズは Karpathy 4 原則 (think before / simplicity / surgical / goal-driven) に従う。
  "lgtm loop", "LGTMまで回す", "実装してレビューして直して", "実装と修正をループで" などで呼び出す。
---

# LGTM Loop: 実装・レビュー・修正の反復

ユーザーが意図する機能を実装し、Codex (GPT) によるレビュー → 修正 → 再レビューを LGTM 達成まで反復する。
最終ゴールは **ユーザーの意図する機能が動くこと**。LGTM はそれを補強するコード品質の安全網であり、ゴール自体ではない。

レビューの指摘は仮説として扱い、採否は動かして確かめた結果で決める。差分だけを見た指摘は命名や将来への備えに偏りやすく、全部直すと往復が収束しない。トークンはレビューの往復より検証に使う。

## Context: $ARGUMENTS

## 定数

- MAX_ITERATIONS = `3`

モデルと reasoning effort は **`~/.codex/config.toml` の値を継承する**。
`codex exec` に `-m` や `-c model=...` / `-c model_reasoning_effort=...` を **付けない** こと。
Codex の最高モデルを切り替えたいときは config.toml の 1 箇所だけを更新すればよい (単一ソース)。

## 前提

- `codex` CLI がログイン済み (`./nanokit codex-install` → `codex login`)
- `jq` が使える
- `karpathy-guidelines` skill が同居していると望ましい (Step 1b で auto-invoke 想定)。なければ本文 4 原則を inline 参照

> 継続レビューは同じ会話に続けて送る必要があるため、**`codex exec` / `codex exec resume <thread_id>` を Bash から呼ぶ**。
> 公式プラグイン (`/codex:review`) は会話を指定して続けられないので、1 ショットレビューにのみ使い、本ループでは使わない。

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
   新しい test は **実装前 (バグ修正なら修正前) に実行して落ちることを確かめ、その出力を残す**。最初から通る test は修正の根拠にならない

実装の進め方:
- task-driven: 引数のタスクを 5–15 個の小さな Edit に分けて実装
- plan-driven: plan の phase ごとに実装し、各 phase 後に Step 2 を回す
- 「前置き 1 文 + 実装 + 軽い確認」のリズムを保つ

## Step 2: GATE — 機能ゲート + 品質ゲート

ゲートは 2 段階。**両方 pass** しなければ Step 3 (REVIEW) に進まない。Codex を呼ぶのは GATE green が前提。

### 2a. 機能ゲート

Step 1a で立てた受け入れ基準を満たしているか:
- 新規 test を実行し pass を確認 (Step 1b で落ちることを確かめた test に限る)
- 受け入れシナリオを手動 / 自動でなぞる。CLI なら実際に実行し、UI ならブラウザで操作して、出力や画面を見る
- test が本当にバグを捕まえるか怪しいときは、修正の要の行を一時的に戻して test が落ちることを確かめ、元に戻す
- fail → Step 1b に戻って実装を直す (Karpathy "Surgical Changes" 厳守)

### 2b. 品質ゲート

リポジトリ標準のチェックを順に試行:
1. `pixi run check` が定義されていれば最優先
2. なければ `pixi run lint` + `pixi run typecheck` + `pixi run test-unit` を順に
3. pixi 不在なら `make test` / `npm test` / `pytest` をフォールバック
4. プロジェクトのチェックコマンドが特定できなければ、ユーザーに 1 度確認

fail → 修正してから再実行。

## Step 3: REVIEW — Codex によるレビュー

### Codex の呼び方

リポジトリのルートで、Bash から `codex exec` を呼ぶ。プロンプトは Write で一時ファイル (scratchpad などの `<dir>/prompt.md`) に書き、標準入力で渡す。diff やバッククォートを含んでもシェルの引用で崩れない。

新しい会話を始める (1 行目に thread_id、続けて Codex の回答が出る):

```bash
rm -f <dir>/reply.md
codex exec --json -s read-only --skip-git-repo-check -o <dir>/reply.md - < <dir>/prompt.md > <dir>/events.jsonl \
  && jq -r 'select(.type=="thread.started").thread_id' <dir>/events.jsonl && cat <dir>/reply.md \
  || { jq -c 'select(.type=="error" or .type=="turn.failed")' <dir>/events.jsonl; false; }
```

同じ会話に続きを送る:

```bash
rm -f <dir>/reply.md
codex exec resume <thread_id> --json -c 'sandbox_mode="read-only"' --skip-git-repo-check \
  -o <dir>/reply.md - < <dir>/prompt.md > <dir>/events.jsonl \
  && cat <dir>/reply.md || { jq -c 'select(.type=="error" or .type=="turn.failed")' <dir>/events.jsonl; false; }
```

- `-s read-only` は Codex にリポジトリを読ませるが書き換えさせない設定。`resume` には `-s` が無いので `-c` で同じ指定をする
- `--skip-git-repo-check` は git 管理外のディレクトリでも動かすため
- レビューは数分以上かかることがある。Bash の `run_in_background: true` で流し、完了通知が来てから出力を読む
- 失敗すると、回答の代わりに Codex のエラー (JSON の `error` / `turn.failed`、または起動時のエラー文) が出る

### 1 ラウンド目: 新しい会話でレビュー

次の内容を `<dir>/prompt.md` に書き、新しい会話として送る:

````markdown
以下のコード変更をレビューしてください。

## プロジェクト概要
[1-2 文でプロジェクトの目的を説明]

## 変更の意図
[Step 1a の受け入れ基準の要約]

## Diff
```diff
[git diff の出力]
```

## 確認してほしい観点
1. [この変更で壊れやすい点を具体的に。例: 月末 23 時台の日付が翌月に集計されないか]
2. [例: 0 件・上限値・不正入力のときの振る舞い]
3. [例: 認証を通らずに他人のデータが読めないか]

## 指摘の条件
- 各指摘に、問題が起きる具体的な入力や手順と、そのとき期待と違ってどうなるかを書いてください。書けないものは指摘しないでください
- 命名・書き方の好み・将来への備え (今の要件に無い抽象化や拡張性) は指摘しないでください
- 重要度 (CRITICAL / HIGH / MEDIUM / LOW)・該当箇所 (ファイル名:行)・修正案を付けてください
- 読むだけにして、スクリプトやコマンドは実行しないでください
- 問題がなければ、無理に指摘を探さず「LGTM」と書いてください
````

観点は受け入れ基準と diff から 3〜4 個に絞って具体的に書く。「厳しく」「徹底的に疑え」と強調するより、観点を具体化したほうが見つかるバグが多い。

出力の 1 行目に出る **thread_id を覚えておき**、2 ラウンド目以降の `codex exec resume` で使う。

### 2 ラウンド目以降: 同じ会話で継続レビュー

次の内容を `<dir>/prompt.md` に書き、1 ラウンド目の thread_id で続きとして送る:

````markdown
前ラウンドの指摘について以下のとおり修正しました。

## 修正サマリ
- [HIGH N]: <対応内容>
- [MEDIUM M]: <対応内容>
...

## 最新 diff
```diff
<git diff の出力>
```

前ラウンドの各指摘について「解消 / 未解消」と根拠 (ファイル名:行) を答えてください。
新しい指摘は、CRITICAL / HIGH で、具体的な入力や手順を書けるものだけにしてください。
すべて解消されていれば「LGTM」と明記してください。
````

plan-driven モードのときは prompt に 1 行追加: 「plans/foo.md からの逸脱があれば併せて指摘してください」。

## Step 4: FIX — 指摘の整理と修正

- Codex 応答から `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` を抽出し、`TaskCreate` で 1 件 1 タスクに分解
- **バグの指摘は、直す前に再現する。** 指摘の入力や手順を test にし、いまのコードで落ちることを確かめてから直す。再現できなければ直さず、試した内容を添えて次のラウンドで Codex に返す
- **CRITICAL** がある場合は、再現できたら自動修正前にユーザーに確認 (重大変更は人間が判断)
- **HIGH / MEDIUM** は再現できたものだけ AUTO で修正 (Karpathy "Surgical Changes" 厳守、無関係な refactor 禁止)
- **LOW** は直さず、終了時の出力に一覧で載せてユーザーの判断に任せる
- Edit / Write で修正を適用
- 修正後は必ず Step 2 (GATE) に戻って機能ゲート + 品質ゲートを再実行

## Step 5: ループ判定

成功終了条件は **AND** (3 点すべて満たす):

1. 機能ゲート (Step 2a) pass — 受け入れ基準を満たしている
2. 品質ゲート (Step 2b) pass — リポジトリ標準チェックが green
3. Codex 応答に "LGTM" を含む、または残る指摘がどれも再現できなかったか LOW だけ

どれか 1 つでも未達なら Step 2 → 3 → 4 をもう 1 周。
反復回数 `>= MAX_ITERATIONS (=3)` に達したら現状を整理してユーザーに判断委ね。3 往復で収束しない指摘は、往復を重ねても収束しないことが多い。

**注意:**
- Codex が LGTM を返しても機能ゲート fail なら未完了 (機能未実装の可能性)。実装に戻る。
- 機能が動いていても、再現できた CRITICAL/HIGH が残っていれば未完了。修正に戻る。

## ルール

- 再現できない指摘は却下してよい。黙って捨てず、試した内容を同じ thread_id の会話で Codex に返す
- Claude のレビューと Codex のレビューは混ぜない — Codex の指摘をそのまま提示し対応する
- thread_id は session 内で保持。別セッションへ持ち越さない
- diff が 500 行を超える場合はファイル単位で分割レビュー
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
- 総修正件数: M 件 (CRITICAL 0 / HIGH a / MEDIUM b)
- 証拠: 修正前に落ち、修正後に通った test 名と実行結果。受け入れシナリオを実際になぞった出力 (UI ならスクリーンショット)
- 再現できず却下した指摘: K 件 (要約)
- 直していない LOW: L 件 (一覧)
```

中断時 (MAX_ITERATIONS 到達 or ユーザー判断要):
```
## LGTM Loop 中断

- 反復回数: N ラウンド (上限 3)
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
- `/codex:review` (公式プラグイン) : 1 ショットレビュー (loop 不要時)。`--background` でターンを塞がない
- `git-commits`         : LGTM 後のコミット粒度整理

## 補足: レビュー経路の使い分け

レビュー観点プロンプトは本 skill の Step 3 に内蔵している (旧 codex-review skill から移設)。
公式プラグイン `/codex:review` は会話を指定して続けられず継続レビューができないため、本ループでは `codex exec` を直接呼ぶ。
