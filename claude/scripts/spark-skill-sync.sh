#!/usr/bin/env bash
# Spark Desktop 同梱の use-spark skill を nanokit へ取り込む (冪等)。
#
# `spark` は Spark Desktop.app 同梱バイナリへの /usr/local/bin/spark symlink で、
# conda-forge に無いため pixi global の管理外。CLI と skill はバージョンを共有し、
# 新しい Spark Desktop は新しい skill を同梱するので、Spark を更新したらこれを再実行する。
#
# ベンダ出力そのままではなく、この環境固有の注意 (Codex のサンドボックス制約・送信系の
# 承認ゲート・更新手順) を frontmatter 直後へ挿し込む。再実行すれば必ず付け直されるので、
# Spark 側の更新でローカルの注意が消えることはない。
#
# 生成先 claude/skills/use-spark/SKILL.md は agent-config-sync が
# ~/.claude/skills/use-spark と ~/.agents/skills/use-spark の両方へ symlink する。
#
#   usage: spark-skill-sync.sh [--diff]

set -euo pipefail

src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do src="$(readlink "$src")"; done
NANOKIT_ROOT="$(cd "$(dirname "$src")/../.." >/dev/null 2>&1 && pwd)"
DEST="$NANOKIT_ROOT/claude/skills/use-spark/SKILL.md"

if ! command -v spark >/dev/null 2>&1; then
  echo "spark-skill-sync: spark が PATH にありません (Spark Desktop.app を入れて CLI を有効化してください)" >&2
  exit 127
fi

raw="$(mktemp)"
block="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "$raw" "$block" "$out"' EXIT

spark skill >"$raw"

# ベンダ出力が壊れていたら既存ファイルを潰さない。
if [ ! -s "$raw" ] || ! head -n 1 "$raw" | grep -qx -- '---'; then
  echo "spark-skill-sync: 'spark skill' の出力が SKILL.md 形式ではありません。中断します" >&2
  exit 1
fi

fm_end="$(awk 'NR>1 && /^---$/ {print NR; exit}' "$raw")"
if [ -z "$fm_end" ]; then
  echo "spark-skill-sync: frontmatter の終端が見つかりません。中断します" >&2
  exit 1
fi

cat >"$block" <<'LOCAL'

## この環境での注意 (nanokit 管理)

- **このファイルは生成物。** 更新は `~/.claude/scripts/spark-skill-sync.sh` を実行する。下の "Keeping this skill up to date" が言う `spark skill > SKILL.md` を直接やるとこの節が消える。実体は `~/nanokit/claude/skills/use-spark/SKILL.md` で、`~/.claude/skills` と `~/.agents/skills` の両方へ symlink されている。
- **exit 134 は接続失敗のサイン。** `spark` は Spark Desktop に繋がらないとき、エラーメッセージを出さず SIGABRT (exit 134) で落ちることがある。出力が空で 134 なら、まず Spark Desktop が起動していて Settings の AI Agents で CLI アクセスが有効かを確認する。読み取り系は Codex の既定サンドボックス内でもそのまま通る (2026-09-11 に read-only と workspace-write の両方で確認済み) ので、サンドボックスを真っ先に疑わない。それでも 134 が続くなら `with_escalated_permissions: true` を付けて再実行する。
- **`spark` は pixi global の管理外。** 実体は Spark Desktop.app 同梱バイナリへの `/usr/local/bin/spark` symlink なので、`pixi global install spark` を試みない。
- **この環境の Spark は読み取り専用。書き込み系は使わない。** Spark に課金していないため全アカウントが read-only 固定で、`draft` / `action` / `contact-action` / `comment` / `event` はアプリ側で必ず弾かれる。試すだけ無駄なので Claude Code では `deny` で実際に塞がれている (確認済み)。Codex 側にも `forbidden` を宣言しているが、non-interactive の `codex exec` では素通りするのを確認しているため、エージェント自身が呼ばないこと。下の各コマンドの説明が triage / send 権限の話をしていても、この環境には当てはまらない。
- **書き込みが要るときは Gmail を直接操作する。** メールの送信・下書き・整理は `mcp__workspace-personal__*` (sh.mn.nat@gmail.com)、HDT 宛は `mcp__workspace-hdt__*` を使う。カレンダー更新も同じ Google 側で行う。Spark は「全アカウントを横断して読む」ためだけに使い、Google 以外のアカウントには書き込み経路そのものが無い。
LOCAL

{
  head -n "$fm_end" "$raw"
  cat "$block"
  tail -n "+$((fm_end + 1))" "$raw"
} >"$out"

version="$(sed -n 's/^  version: *//p' "$raw" | head -n 1)"

if [ "${1-}" = "--diff" ]; then
  if [ -f "$DEST" ]; then
    diff -u "$DEST" "$out" && echo "spark-skill-sync: 変更なし (v${version:-unknown})"
  else
    echo "spark-skill-sync: 新規作成予定 $DEST (v${version:-unknown})"
  fi
  exit 0
fi

if [ -f "$DEST" ] && cmp -s "$DEST" "$out"; then
  echo "spark-skill-sync: 変更なし (v${version:-unknown})"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
cp "$out" "$DEST"
echo "spark-skill-sync: 更新しました $DEST (v${version:-unknown})"
