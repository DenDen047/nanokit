---
name: committing-changes
description: Generates focused git commits with well-structured messages. Analyzes the diff, splits unrelated changes via `git add -p`, and writes Problem → Solution → Implications messages (type + subject + body). Use when the user says "commit", "コミット", "コミットして", "git commit", "PR を作って", asks to split a diff, write a commit message, fix up history, or when work is ready to commit. MUST be invoked before any `git commit` bash invocation — the Bash system-prompt "Committing changes with git" section is a fallback, not a substitute.
user-invocable: true
---

# Committing Changes — Workflow と原則

> 出典: [MIT Missing Semester 2026 - Beyond the Code](https://missing.csail.mit.edu/2026/beyond-code/)

## このスキルの使い方 (Claude 向け)

ユーザーが commit / コミット関連のリクエストを出したら、**git コマンドを実行する前に本 SKILL.md を読み**、下記 Workflow を上から順に実行する。trivial な typo 修正 (1 行・1 ファイル・自明) は Workflow を圧縮しても良いが、`<type>: <subject>` 構造は守る。

## Workflow

### Step 1: 変更の把握

```bash
git status                  # 全体像
git diff --staged           # ステージ済の確認
git diff                    # unstaged
```

`git status` の `-uall` フラグは使わない (大きい repo でメモリ問題)。

### Step 2: 粒度判定

stagedな変更が **1 つの論理的変更** に収まるか確認:
- 機能追加 / バグ修正 / リファクタリング / フォーマット変更 が**混ざっていないか**
- 1 つの問題 / チケットを解決しているか
- レビュアーが独立してレビューできるか

混ざっていれば **Step 2.5 (分割)** へ。単一なら **Step 3** へ。

### Step 2.5 (任意): 複数論理変更の分割

```bash
git reset HEAD              # ステージを解除
git add -p                  # ハンク単位で選択的にステージング
```

`-p` で 1 論理変更分だけステージング → commit → 次の論理変更を `add -p` → commit、を繰り返す。

ハンク選択が複雑な場合、sub-agent (Explore 等) に diff を渡し「意味的に独立した変更グループに分けて」と依頼する。

### Step 3: メッセージ draft

```
<type>: <subject>

<body>
```

- **type**: feat / fix / refactor / chore / docs / style / test / perf / ci のいずれか
- **subject**: 命令形・50 char 以内・末尾 period なし
- **body**: 必要時のみ。72 char 折り返し。**Problem → Solution → Implications** 構造で書く

body に書くべき 4 つの問い:
1. **何がこの変更を強制したか** — 問題・要件・制約
2. **どんな代替案を検討したか** — なぜこの方法を選んだか
3. **トレードオフや影響は** — 例: ランタイム速いがビルド遅い
4. **驚くべき点は** — 非自明な副作用・注意事項

### Step 4: commit 実行

HEREDOC で渡す (改行が正しく入る):

```bash
git commit -m "$(cat <<'EOF'
feat(scope): subject line

Problem: ...
Solution: ...
Implications: ...
EOF
)"
```

注意:
- `git add -A` / `git add .` は使わない (`.env` 等を含み得る)
- `--no-verify` / `--no-gpg-sign` は user が明示要求しない限り使わない
- `--amend` は user が明示要求しない限り使わない (新 commit を作る)
- attribution trailer (`Co-Authored-By:`) は **追加しない** (`~/.claude/CLAUDE.md` / `rules/common/git-workflow.md` で attribution disabled)

### Step 5: 検証

```bash
git status                  # commit 成立確認
git log --oneline -3        # HEAD に新 commit があるか
```

pre-commit hook が失敗した場合は **新 commit を作って fix** (amend ではなく)。

## Reference: 粒度の原則

### 1 commit = 1 論理変更

なぜ重要か:
- **デバッグ効率**: `git bisect` で犯人 commit を特定したとき、変更が小さければ原因箇所も絞れる
- **レビュー効率**: 焦点が絞られた diff は通る、無関係な変更が混ざると却下される
- **歴史の可読性**: `git log` / `git blame` で「なぜこの行が変わったか」が追跡できる
- **部分採用**: OSS では一部だけマージし他は保留にできる

### スケーリング

| 変更規模 | 推奨 |
|---|---|
| 1 行 typo | subject だけで OK、body 不要 |
| 単機能追加 / 単 bug fix | subject + 短い body (Problem) |
| 複雑な変更 (>50 lines / 複数ファイル) | subject + Problem/Solution/Implications |
| リファクタ + 機能追加 | **必ず分割** (Step 2.5) |

## Reference: メッセージのアンチパターン

- `fix bug` / `update` / `misc changes` / `wip` — 中身がない
- `Add function foo to bar.py` — diff を text で繰り返しただけ (何 → diff、なぜ → 不明)
- リファクタ + 機能追加を 1 commit に混ぜる — `git bisect` 不能
- 「色々直した」「諸々修正」— 履歴の死蔵
- `Co-Authored-By: Claude` 等の trailer (本リポジトリは attribution disabled)

## Reference: 議論ログ / 改訂レビュー型タスクとの連携

複雑な検討タスクで版を重ねる場合 (例: `html-report-writing` skill の `patterns/review-log.md`)、各 commit message に **どの議論ラウンドで何が変わったか** を残す。

```
refactor(skill): adopt review-log structure per round-2 feedback

Problem: iterative-template と SKILL.md で用語 (反復) が混乱
Solution: review-log に統一、外部レビュー取り込みを明示
Implications: 旧 iterative-* 参照を更新、cto-briefing 表現は触らず
```

## Claude が「このスキルを呼び忘れない」ための補強

Bash system-prompt の "Committing changes with git" 節と競合するため、以下も併用すると確実:

1. **PreToolUse hook**: Bash command が `git commit` を含むときに「本 skill を invoke せよ」の system-reminder を注入する (`karpathy-reminder.sh` 同型)。
2. **memory feedback**: 「commit を作る前に必ず本 skill を Skill() で invoke する」を `~/.claude/projects/.../memory/feedback_*.md` に書く (既に保存済)。

これらが揃って初めて 100% activation が保証される。description の改善は確率の引き上げに留まる。
