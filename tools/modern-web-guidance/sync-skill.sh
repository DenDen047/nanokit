#!/usr/bin/env bash
# ラッパーに固定した版の npm パッケージから SKILL.md を取り出し、npx で直接呼ぶ箇所を
# ラッパー (送信を止める) に置き換えて claude/skills/modern-web-guidance/SKILL.md に書く。
#
# 上流の SKILL.md は --skill-version の値が CLI の版と揃っている前提なので、手で直さずに
# 版を上げたらこれを流し直す。nanokit upgrade は版を上げたときに自動で流す。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out_dir="$root/claude/skills/modern-web-guidance"

spec="$(grep -oE 'npx -y "modern-web-guidance@[0-9][^"]*"' "$here/modern-web-guidance" | head -n 1)"
spec="${spec#npx -y \"}"
spec="${spec%\"}"
[ -n "$spec" ] || { echo "sync-skill: ラッパーから版を読めなかった" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(cd "$tmp" && npm pack "$spec" --silent >/dev/null && tar xzf ./*.tgz package/skills/modern-web-guidance/SKILL.md)
src="$tmp/package/skills/modern-web-guidance/SKILL.md"

# 1. コマンドの呼び方をラッパーに置き換える。
# 2. npx / pnpx の使い分けの節は丸ごと nanokit の節に差し替える (pnpx を勧める行が残ると送信を止められない)。
# 3. frontmatter の直後に、生成物であることを書いておく。
awk -v spec="$spec" '
  BEGIN { fm = 0; skip = 0 }
  NR == 1 && /^---$/ { fm = 1; print; next }
  fm == 1 && /^---$/ {
    fm = 2; print
    print ""
    print "<!-- Generated from " spec " by nanokit tools/modern-web-guidance/sync-skill.sh. Do not edit; re-run the script. -->"
    next
  }
  /^## Using npx \/ pnpx/ {
    skip = 1
    print "## Running the CLI (nanokit)"
    print ""
    print "- Always run the `modern-web-guidance` command on PATH. It is a nanokit wrapper that pins the version and sets `DISABLE_TELEMETRY=1`, so search queries and guide IDs are not sent to Google. Never call it through `npx`, `pnpx`, `bunx` or `@latest`; that bypasses the opt-out."
    print "- Do not run `install`, `update` or `uninstall`, and do not ask the user to update the skill. nanokit distributes and updates it (`nanokit upgrade`); the wrapper refuses those commands."
    print "- The first run downloads the pinned package from npm, so it needs network access. In a sandbox, request network approval before the first run."
    print ""
    next
  }
  skip && /^## / { skip = 0 }
  skip { next }
  {
    gsub(/(pnpx|npx)( -y)? modern-web-guidance@[A-Za-z0-9.-]+/, "modern-web-guidance")
    gsub(/directly with `npx`/, "(the nanokit wrapper on PATH)")
    print
  }
' "$src" >"$tmp/SKILL.md"

# shellcheck disable=SC2016  # バッククォートは Markdown の文字そのもの
if grep -nE '(npx|pnpx|bunx)( -y)? modern-web-guidance|modern-web-guidance@|with `npx`' "$tmp/SKILL.md" | grep -v ':<!-- Generated' >&2; then
  echo "sync-skill: 上の行に npx での呼び出しが残った。上流の書き方が変わったので、この script を直す" >&2
  exit 1
fi
grep -q 'modern-web-guidance search' "$tmp/SKILL.md" \
  || { echo "sync-skill: search の呼び出しが見つからない。上流の書き方が変わった" >&2; exit 1; }

mkdir -p "$out_dir"
cp "$tmp/SKILL.md" "$out_dir/SKILL.md"
