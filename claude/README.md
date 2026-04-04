# claude/

Claude Code のグローバル設定を管理するディレクトリ。
dotter により `~/.claude/` へシンボリックリンクされる。

## Skills / Commands / Sub-agents の違い

> 公式ドキュメント: https://code.claude.com/docs/en/skills, https://code.claude.com/docs/en/sub-agents

> [!WARNING]
> **Commands は Skills に統合済み。** 既存の `.claude/commands/` ファイルはそのまま動くが、新規作成は Skills 推奨。

| | Skills | Commands (レガシー) | Sub-agents |
|---|---|---|---|
| **配置場所** | `skills/<name>/SKILL.md` | `commands/<name>.md` | `agents/<name>.md` |
| **形式** | ディレクトリ（補助ファイル同梱可） | 単一ファイル | 単一ファイル |
| **スコープ** | グローバル (`~/.claude/`) / プロジェクト (`.claude/`) | 同左 | 同左 |
| **ユーザーが `/` で呼べる** | Yes | Yes | No |
| **Claude が自動で使う** | Yes（description で判断） | No | Yes（description で判断して委譲） |
| **独立コンテキスト** | No（会話に注入）※ `context: fork` で可 | No | **Yes（常に独立）** |
| **カスタムシステムプロンプト** | No | No | **Yes**（本文がプロンプトになる） |
| **ツール制限** | `allowed-tools` | `allowed-tools` | `tools` / `disallowedTools` |
| **モデル指定** | `model` | `model` | `model` |
| **永続メモリ** | No | No | Yes (`memory` フィールド) |
| **MCP サーバースコーピング** | No | No | Yes (`mcpServers` フィールド) |
| **権限モード指定** | No | No | Yes (`permissionMode` フィールド) |

### 使い分け

| やりたいこと | 使うもの |
|---|---|
| コーディング規約・コミット規約を自動適用 | **Skill** (`user-invocable: false`) |
| `/deploy` のようなユーザー起動タスク | **Skill** (`user-invocable: true`) |
| コードレビューを独立コンテキストで並列実行 | **Sub-agent** |
| 専門分野ごとにモデルやツールを変えたい | **Sub-agent** |
| 既存の commands/ がそのまま動いている | そのまま放置で OK |

### Skills の例

```
claude/skills/git-conventions/
├── SKILL.md          # 必須エントリポイント
├── templates/        # 任意の補助ファイル
└── examples/
```

```yaml
# SKILL.md
---
name: git-conventions
description: Git コミットメッセージ規約。コミット時に自動適用。
user-invocable: false
---

ここにスキルの内容を記述...
```

### Sub-agents の例

```yaml
# agents/security-reviewer.md
---
name: security-reviewer
description: セキュリティ脆弱性の検出。認証やユーザー入力を扱うコード変更時に使う。
tools: ["Read", "Grep", "Glob", "Bash"]
model: opus
---

あなたはセキュリティ専門家です。OWASP Top 10 を中心にレビューしてください。
```
