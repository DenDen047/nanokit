---
name: codex-review
description: >
  git diff ベースのコードレビューを Codex MCP (GPT) 経由で取得する。
  コード変更後にセカンドオピニオンが欲しいとき、"codex review", "GPTにレビューして",
  "セカンドオピニオン" などで呼び出す。
user-invocable: true
argument-hint: "[scope: staged | HEAD~N | branch-diff | file paths]"
allowed-tools: Bash(*), Read, Grep, Glob, mcp__codex__codex, mcp__codex__codex-reply
---

# Codex Review: コード変更のセカンドオピニオン

Claude が書いた・修正したコードを、別の AI (GPT) にレビューさせる。
単一モデルの盲点を補い、エッジケースや設計の穴を検出する。

## Context: $ARGUMENTS

## 定数

- MODEL = `gpt-5.4`
- REASONING_EFFORT = `xhigh`

すべての `mcp__codex__codex` / `mcp__codex__codex-reply` 呼び出しに以下を付与する:

```
config: {"model": "gpt-5.4", "model_reasoning_effort": "xhigh"}
```

## 前提

- Codex MCP Server が登録済み (`./nanokit codex-install` で自動登録)
- `mcp__codex__codex` / `mcp__codex__codex-reply` が利用可能

## ワークフロー

### Step 1: diff を収集する

引数に応じて適切な diff を取得する:

| 引数 | 動作 |
|------|------|
| なし / `staged` | `git diff --cached` (ステージ済み変更) |
| `HEAD~N` | `git diff HEAD~N` (直近 N コミット) |
| ブランチ名 | `git diff main...HEAD` (ブランチ全体) |
| ファイルパス | 指定ファイルの diff |

diff が空の場合、`git diff HEAD~1` にフォールバックする。
それでも空なら、ユーザーにスコープを確認する。

### Step 2: コンテキストを補強する

diff だけでは文脈が不足する場合、以下を読む:

- 変更ファイルの周辺コード (関数全体、クラス定義)
- README.md やプロジェクトの CLAUDE.md (設計方針)
- 関連するテストファイル

ただしコンテキストは**必要最小限**に絞る。大量のコードを送ると要点がぼける。

### Step 3: Codex にレビューを依頼する

```
mcp__codex__codex:
  config: {"model": "gpt-5.4", "model_reasoning_effort": "xhigh"}
  prompt: |
    以下のコード変更をレビューしてください。

    ## プロジェクト概要
    [1-2 文でプロジェクトの目的を説明]

    ## 変更の意図
    [この変更が何を達成しようとしているか]

    ## Diff
    ```diff
    [git diff の出力]
    ```

    ## レビュー観点
    以下の観点で問題を指摘してください:
    1. バグ・ロジックエラー (境界条件、off-by-one、null/undefined)
    2. エッジケースの見落とし
    3. セキュリティ上の問題 (入力検証、インジェクション、認証)
    4. パフォーマンス上の懸念
    5. エラーハンドリングの不足
    6. API 設計・インターフェースの問題

    各指摘について:
    - 重要度: CRITICAL / HIGH / MEDIUM / LOW
    - 該当箇所: ファイル名と行番号
    - 問題の説明
    - 修正案 (コード付き)

    問題がない場合は「LGTM」と明記してください。
```

### Step 4: 結果を整理して提示する

Codex の応答から指摘を抽出し、重要度順にまとめて提示する。

```
## Codex Review 結果

CRITICAL: 0 件 | HIGH: 1 件 | MEDIUM: 2 件 | LOW: 1 件

### HIGH: [指摘タイトル]
- ファイル: path/to/file.py:42
- 問題: ...
- 修正案: ...
```

### Step 5: フォローアップ (任意)

ユーザーが特定の指摘について深掘りしたい場合、`mcp__codex__codex-reply` で
threadId を使って会話を継続する。

## ルール

- diff が 500 行を超える場合、ファイルごとに分割してレビューを依頼する
- Claude 自身のレビューと Codex のレビューは**混ぜない** — Codex の指摘をそのまま提示する
- 指摘への対応は Claude が行うが、Codex の指摘を勝手に却下しない。ユーザーに判断を委ねる
- threadId を保持し、同一セッション内での追加質問に対応する
