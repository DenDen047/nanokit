---
name: codex-review
description: >
  git diff ベースのコードレビューを Codex (GPT) に依頼する。
  コード変更後にセカンドオピニオンが欲しいとき、"codex review", "GPTにレビューして",
  "セカンドオピニオン" などで呼び出す。実体は公式プラグイン codex@openai-codex に
  移行済みで、本 skill は自然文トリガーの受け皿 (誘導シム)。
user-invocable: true
argument-hint: "[--background | --base <ref>]"
allowed-tools: Bash(node:*), Bash(git:*), Bash(ls:*), Read
---

# Codex Review: 公式プラグインへの誘導シム

コードレビュー機能は公式プラグイン **codex@openai-codex** に統合された
(経緯: `<nanokit>/docs/2026-07-13_codex-plugin-integration.html`)。
本 skill は「GPT にレビューして」等の自然文トリガーの受け皿として残してある。

## 使い分け

| やりたいこと | 手段 |
|---|---|
| 普通のレビュー (uncommitted / ブランチ diff) | `/codex:review` (`--background` 推奨、ブランチは `--base <ref>`) |
| 観点を指定して攻めるレビュー | `/codex:adversarial-review <focus テキスト>` |
| バックグラウンドジョブの確認 / 結果 / 中止 | `/codex:status` `/codex:result` `/codex:cancel` |
| lgtm-loop の継続レビュー (threadId) | 本 skill ではなく `mcp__codex__codex` 直叩き (lgtm-loop に内蔵) |

## 自然文で頼まれたときの動き

プラグインのコマンドは `disable-model-invocation: true` のため Claude からは起動できない。

1. ユーザーがスラッシュコマンドを打てる文脈なら、上の表から適切なコマンドを 1 行で案内する
2. 「この場でやって」と言われたら、プラグインコマンドと同じ実体である companion script を直接実行する:

```bash
# インストール済みバージョンを動的に解決 (バージョン更新でパスが変わるため)
SCRIPT=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1)
node "$SCRIPT" review ""             # working tree レビュー
node "$SCRIPT" review "--base main"  # ブランチレビュー
```

大きい diff (目安: 3 ファイル超) は Bash の `run_in_background: true` で流す。
結果は要約せずそのまま提示し、指摘への対応判断はユーザーに委ねる。

## モデル設定

プラグイン / MCP の両経路とも `~/.codex/config.toml` を継承する
(現状 `model = gpt-5.6-sol` / `model_reasoning_effort = xhigh`)。
呼び出し側で model / effort を上書きしない (単一ソース)。
