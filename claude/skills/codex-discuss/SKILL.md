---
name: codex-discuss
description: >
  設計・アーキテクチャの壁打ちを Codex (GPT) と行う。
  実装前の方針検討、トレードオフ分析、API 設計の相談に使う。
  "codex discuss", "GPTと相談", "壁打ち", "設計を議論" などで呼び出す。
---

# Codex Discuss: 設計の壁打ち

実装に入る前に、別の AI (GPT) と設計方針を議論する。
Claude の提案をぶつけて批判をもらう、または白紙から選択肢を洗い出す。

## Context: $ARGUMENTS

## モデル設定

モデルと reasoning effort は **`~/.codex/config.toml` の値を継承する**。
`codex exec` に `-m` や `-c model=...` / `-c model_reasoning_effort=...` を **付けない** こと。
Codex の最高モデルを切り替えたいときは config.toml の 1 箇所だけを更新すればよい (単一ソース)。

## 前提

- `codex` CLI がログイン済み (`./nanokit codex-install` → `codex login`)
- `jq` が使える

## Codex の呼び方

Bash から `codex exec` を呼ぶ。プロンプトは Write で一時ファイル (scratchpad などの `<dir>/prompt.md`) に書き、標準入力で渡す。コードやバッククォートを含んでもシェルの引用で崩れない。

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
- 回答に数分かかることがある。Bash の `timeout` は `600000` にする
- 失敗すると、回答の代わりに Codex のエラー (JSON の `error` / `turn.failed`、または起動時のエラー文) が出る

## ワークフロー

### Step 1: 議論の種を整理する

引数とプロジェクトの状況から、議論のコンテキストを組み立てる:

- **引数あり**: 引数をそのまま議題として使う
- **引数なし**: 直近の会話から議題を推測する。推測できなければユーザーに確認する

補足コンテキストとして、必要に応じて以下を読む:
- プロジェクトの CLAUDE.md / README.md
- 議題に関連するソースコード
- 既存のアーキテクチャ (ディレクトリ構成、主要なインターフェース)

### Step 2: Codex に議論を投げる

次の内容を `<dir>/prompt.md` に書き、新しい会話として送る。返ってきた thread_id は Step 3 で使う。

```markdown
あなたはシニアソフトウェアエンジニアです。
以下の設計課題について議論してください。

## プロジェクト概要
[プロジェクトの目的と技術スタック]

## 現在の状況
[関連する既存コードやアーキテクチャの要約]

## 議題
[ユーザーの質問や検討事項]

## Claude の提案 (あれば)
[Claude が既に考えた方針案]

以下の形式で回答してください:
1. 提案の評価 (良い点・懸念点)
2. 代替案があれば提示 (最大 3 つ)
3. 各案のトレードオフ比較表
4. 推奨案とその理由

率直に意見してください。遠慮は不要です。
```

### Step 3: 議論を続ける

Codex の応答を受けて、Claude が以下のいずれかを行う:

1. **同意**: Codex の指摘を踏まえて方針を確定し、ユーザーに提示
2. **反論**: Claude の観点で反論し、`codex exec resume` で同じ会話に送って再議論
3. **深掘り**: 特定のポイントについて追加質問

反論する場合は次の内容を `<dir>/prompt.md` に書き、Step 2 の thread_id で続きとして送る:

```markdown
[指摘 N] について反論があります。

[Claude の反論: 根拠を添えて]

この反論を踏まえて、評価を更新してください。
それでも元の指摘が妥当なら、その理由を説明してください。
```

最大 3 ラウンドまで。収束しない場合は両論併記してユーザーに判断を委ねる。

### Step 4: 結論をまとめる

議論の結果を以下の形式でユーザーに提示する:

```markdown
## 議論の結論

### 合意事項
- [Claude と Codex が一致した点]

### 論点 (判断が必要)
- [意見が分かれた点と、それぞれの根拠]

### 推奨方針
[最終的な推奨案]
```

## 使い方の例

```
/codex-discuss REST API のページネーション方式を cursor vs offset で迷っている
/codex-discuss このモジュールの責務分割について壁打ちしたい
/codex-discuss 認証を JWT にするか session にするか
/codex-discuss              ← 引数なし: 直近の文脈から推測
```

## ルール

- Codex の意見を鵜呑みにせず、Claude も自分の判断を持つ。議論であり、丸投げではない
- コンテキストは簡潔に。ソースコード全体を送らない (関連部分のみ)
- 議論は最大 3 ラウンド。それ以上は収束しない可能性が高い
- thread_id を保持し、ユーザーが追加で質問できるようにする
- 結論は必ずユーザーに提示する。裏で勝手に方針を決めない
