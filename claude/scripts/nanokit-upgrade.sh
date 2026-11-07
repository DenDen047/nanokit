#!/usr/bin/env bash
# nanokit が外から取り込んだものを確かめて、新しい版があれば取り込む (冪等)。
#
# 対象はリポジトリの中身から見つけるので、別の一覧は持たない。
#   skills       claude/skills/*/SKILL.md のうち gh skill の出どころ (metadata.github-repo) があるもの
#   use-spark    Spark Desktop 同梱の skill (spark-skill-sync.sh で作り直す)
#   pixi-locks   tools/*/pixi.toml と claude/mcp-servers/*/pixi.toml の pixi.lock
#   npx-pins     claude/scripts/* と tools/*/* にある `npx -y "pkg@X.Y.Z"` の版
#   npm-clis     npm で入れた Codex CLI と Gemini CLI (入っているときだけ)
#   gh-ext       gh の拡張機能
#   pixi-global  pixi global の道具一式
#
# 公開から 7 日経っていない版は取らない (README の Supply Chain Security と同じ方針)。
# pixi は各 pixi.toml の exclude-newer、npm は ~/.npmrc の min-release-age と、ここでの版選びで守る。
# skill だけは上流の更新に早く追いつくのが目的なので待たない。その代わり、コードに通信や動的実行の
# 行が足されたときと、SKILL.md の frontmatter の allowed-tools などが変わったときは取り込まずに
# 保留する。中身を確かめたら `nanokit upgrade --accept-held` で取り込む。
#
# git に入っているもの (skills・use-spark・pixi.lock・npx の版) が変わったら、その道だけを commit する。
# 走る前に未 push の commit がなく、origin より遅れてもいなければ push する。
#
# 成功は静か。失敗は ~/.local/state/nanokit-upgrade/failed.txt に残り、Claude Code の SessionStart で
# 動く `--report` が知らせる。次に全部成功すると消える。
#
#   usage: nanokit upgrade [--dry-run] [--accept-held]
#          nanokit upgrade --schedule | --unschedule   (macOS の launchd に毎日 04:30 で登録 / 解除)
#          nanokit-upgrade.sh --report                  (SessionStart フック用)

# shellcheck disable=SC2218  # 0.11 の誤検知。関数はすべて main より前で定義している
set -uo pipefail

src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do src="$(readlink "$src")"; done
NANOKIT_ROOT="$(cd "$(dirname "$src")/../.." >/dev/null 2>&1 && pwd)"

STATE_DIR="$HOME/.local/state/nanokit-upgrade"
LOG="$STATE_DIR/upgrade.log"
FAILED="$STATE_DIR/failed.txt"
LAST_RUN="$STATE_DIR/last-run"
LOCK_DIR="$STATE_DIR/lock"
LABEL="local.nanokit-upgrade"
PLIST_SRC="$NANOKIT_ROOT/claude/scripts/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
COOLDOWN_DAYS=7

DRY_RUN=false
ACCEPT_HELD=false
FAILS=()
CHANGED=()
SUMMARY=()

say() {
  printf '%s\n' "$*"
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"
}
fail() {
  FAILS+=("$1")
  say "FAIL $1"
}
git_nk() { git -C "$NANOKIT_ROOT" "$@"; }
release_lock() { [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK_DIR"; }
# 未 commit の変更 (追跡外のファイルも、status.showUntrackedFiles の設定によらず) があるか。
# status 自体が失敗したら、安全側に倒して変更ありとみなす。
dirty() {
  local s
  s="$(git_nk status --porcelain --untracked-files=all -- "$@")" || return 0
  [ -n "$s" ]
}
revert() {
  git_nk checkout -q -- "$@" 2>/dev/null
  git_nk clean -fdq -- "$@" 2>/dev/null
}
# 試し実行では手順の出力をそのまま見せ、本番ではログにだけ残す。
run_quiet() {
  if $DRY_RUN; then "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; fi
  "$@" >>"$LOG" 2>&1
}

# npm の版のうち、公開から COOLDOWN_DAYS 日以上経ち、latest を超えない最新を選ぶ。
# 「今の版と同じメジャー版の中の最新」と「メジャー版を問わない最新」を | で区切って出す。
# 今の版より新しいものが無ければ、その欄は空になる。
npm_pick() {
  npm view "$1" time dist-tags --json 2>/dev/null | python3 -c '
import datetime, json, sys
cur, days = sys.argv[1], int(sys.argv[2])
data = json.load(sys.stdin)
def key(v):
    try:
        return tuple(int(x) for x in v.split("."))
    except ValueError:
        return None
latest, now = key(data["dist-tags"]["latest"]), key(cur)
cut = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
ok = []
for v, t in data["time"].items():
    k = key(v)
    if k is None or k > latest or (now is not None and k <= now):
        continue
    if datetime.datetime.fromisoformat(t.replace("Z", "+00:00")) <= cut:
        ok.append((k, v))
same = [x for x in ok if now is not None and x[0][0] == now[0]]
print((max(same)[1] if same else "") + "|" + (max(ok)[1] if ok else ""))
' "$2" "$COOLDOWN_DAYS"
}

# 常駐の MCP サーバーを立ち上げ直し、応答するようになったかまで確かめる。
# 止まりきる前に start すると「起動済み」と誤って判断されるので、先に止まるのを待つ。
restart_server() {
  local s="$1"
  bash "$s" stop >>"$LOG" 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    bash "$s" status >/dev/null 2>&1 || break
    sleep 1
  done
  bash "$s" start >>"$LOG" 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    bash "$s" status >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

skill_label() {
  local f="$1/SKILL.md" ref sha
  ref="$(sed -n 's/^ *github-ref: *//p' "$f" | head -n 1)"
  sha="$(sed -n 's/^ *github-tree-sha: *//p' "$f" | head -n 1)"
  case "$ref" in
    refs/tags/*) echo "${ref#refs/tags/}" ;;
    *) echo "${ref#refs/heads/}@${sha:0:7}" ;;
  esac
}

# skill の更新を保留するかの判定に使う 2 つの見方。
# 1. コードに新しく足された行 (変わったファイルの差分と、新しく増えたファイルの全体) に、
#    通信や動的実行の書き方があるか。もともと同じ語があっても、足された行にあれば止める。
# 2. SKILL.md の frontmatter のうち、説明・名前・ライセンス・出どころの記録以外
#    (allowed-tools や hooks など、権限や動きに効く項目) が足されたり消えたり変わったりしたか。
RISKY_RE='(import|from)[[:space:]]+(urllib|http|httpx|requests|aiohttp|socket|ssl|ftplib|smtplib|telnetlib|websocket|paramiko)|curl[[:space:]]|wget[[:space:]]|Invoke-WebRequest|fetch\(|XMLHttpRequest|b64decode|base64[[:space:]]+-d|__import__|eval\(|exec\('
risky_added() {
  local d="$1" specs=() g f
  # git の pathspec の * は / もまたぐので、下のフォルダのファイルも拾う。
  for g in '*.py' '*.sh' '*.js' '*.mjs' '*.ts' '*.ps1'; do specs+=("$d/$g"); done
  {
    git_nk diff -U0 --no-color -- "${specs[@]}" | grep '^+' | grep -v '^+++'
    git_nk ls-files --others --exclude-standard -z -- "${specs[@]}" \
      | while IFS= read -r -d '' f; do cat "$NANOKIT_ROOT/$f"; done
  } | grep -oE "$RISKY_RE" | sort -u
}
guarded_frontmatter() {
  awk 'NR == 1 && /^---$/ { fm = 1; next }
       fm && /^---$/ { exit }
       fm {
         if ($0 ~ /^[^ \t]/) { key = $0; sub(/:.*/, "", key) }
         if (key != "description" && key != "metadata" && key != "license" && key != "name" && key != "version") print
       }' "$1/SKILL.md"
}

step_skills() {
  local dirs=() d
  for d in "$NANOKIT_ROOT"/claude/skills/*/; do
    d="${d%/}"
    grep -q '^ *github-repo:' "$d/SKILL.md" 2>/dev/null && dirs+=("$d")
  done
  [ "${#dirs[@]}" -gt 0 ] || return 0
  command -v gh >/dev/null || { fail "skills: gh が見つからない"; return; }
  local tmp out rc
  if $DRY_RUN; then
    out="$(gh skill update --dry-run --all --dir "$NANOKIT_ROOT/claude/skills" 2>&1)"
    rc=$?
    printf '%s\n' "$out" | grep -v 'has no GitHub metadata' | tee -a "$LOG"
    [ "$rc" -eq 0 ] || fail "skills: gh skill update --dry-run が失敗した (exit $rc)"
    return
  fi
  if dirty "${dirs[@]}"; then
    fail "skills: 追跡中の skill に未 commit の変更があるので飛ばした"
    return
  fi

  tmp="$(mktemp -d)"
  for d in "${dirs[@]}"; do
    guarded_frontmatter "$d" >"$tmp/$(basename "$d").fm"
    skill_label "$d" >"$tmp/$(basename "$d").label"
  done

  out="$(gh skill update --all --dir "$NANOKIT_ROOT/claude/skills" 2>&1)"
  rc=$?
  printf '%s\n' "$out" | grep -v 'has no GitHub metadata' >>"$LOG"
  if [ "$rc" -ne 0 ]; then
    fail "skills: gh skill update が失敗した (exit $rc)"
    revert "${dirs[@]}"
    rm -rf "$tmp"
    return
  fi

  local name why
  for d in "${dirs[@]}"; do
    dirty "$d" || continue
    name="$(basename "$d")"
    why="$(risky_added "$d" | paste -sd, - | sed 's/,/, /g')"
    if ! guarded_frontmatter "$d" | cmp -s "$tmp/$name.fm" -; then
      why="${why:+$why, }frontmatter の allowed-tools などの変更"
    fi
    if [ -n "$why" ] && ! $ACCEPT_HELD; then
      revert "$d"
      fail "skills: $name の更新を保留した (理由: $why)。中身を確かめて問題なければ \`nanokit upgrade --accept-held\`"
      continue
    fi
    CHANGED+=("$d")
    SUMMARY+=("$name $(cat "$tmp/$name.label") → $(skill_label "$d")")
  done
  rm -rf "$tmp"
}

step_spark() {
  local f="$NANOKIT_ROOT/claude/skills/use-spark/SKILL.md"
  command -v spark >/dev/null || return 0
  if $DRY_RUN; then
    bash "$NANOKIT_ROOT/claude/scripts/spark-skill-sync.sh" --diff 2>&1 | tee -a "$LOG" \
      || fail "use-spark: spark-skill-sync.sh --diff が失敗した"
    return
  fi
  if dirty "$f"; then
    fail "use-spark: 未 commit の変更があるので飛ばした"
    return
  fi
  if ! bash "$NANOKIT_ROOT/claude/scripts/spark-skill-sync.sh" >>"$LOG" 2>&1; then
    revert "$f"
    fail "use-spark: spark-skill-sync.sh が失敗した"
    return
  fi
  if dirty "$f"; then
    CHANGED+=("$f")
    SUMMARY+=("use-spark (Spark Desktop の同梱版)")
  fi
}

step_pixi_locks() {
  command -v pixi >/dev/null || { fail "pixi-locks: pixi が見つからない"; return; }
  local m dir lock name server s broken
  for m in "$NANOKIT_ROOT"/tools/*/pixi.toml "$NANOKIT_ROOT"/claude/mcp-servers/*/pixi.toml; do
    [ -f "$m" ] || continue
    dir="$(dirname "$m")"
    lock="$dir/pixi.lock"
    name="$(basename "$dir")"
    if $DRY_RUN; then
      say "-- $name"
      pixi update --dry-run --manifest-path "$m" 2>&1 | tee -a "$LOG" \
        || fail "$name: pixi update --dry-run が失敗した"
      continue
    fi
    if dirty "$m" "$lock"; then
      fail "$name: pixi.toml か pixi.lock に未 commit の変更があるので飛ばした"
      continue
    fi
    if ! pixi update --manifest-path "$m" >>"$LOG" 2>&1; then
      revert "$lock"
      fail "$name: pixi update が失敗した"
      continue
    fi
    dirty "$lock" || continue
    # 更新した環境で動くかを確かめる。version タスクがあればそれを走らせ、常駐の MCP サーバーなら
    # 立ち上げ直して応答を待つ。どちらかが駄目なら元の lock と環境に戻す。
    server=""
    for s in "$HOME/.claude/scripts/$name-server.sh" "$HOME/.claude/scripts/$name-mcp-server.sh"; do
      [ -f "$s" ] && server="$s"
    done
    broken=""
    # 版が上がったあとに要る手順 (ブラウザ本体の取り直しなど) は、各 pixi.toml の post-update タスクに書く。
    if grep -qE '^post-update *=' "$m" && ! pixi run --manifest-path "$m" post-update >>"$LOG" 2>&1; then
      broken="post-update タスクが失敗した"
    elif grep -qE '^version *=' "$m" && ! pixi run --manifest-path "$m" version >>"$LOG" 2>&1; then
      broken="version タスクが動かない"
    elif [ -n "$server" ] && ! restart_server "$server"; then
      broken="MCP サーバーが応答しない"
    fi
    if [ -n "$broken" ]; then
      revert "$lock"
      pixi install --manifest-path "$m" >>"$LOG" 2>&1
      [ -n "$server" ] && { restart_server "$server" || fail "$name: 元の環境に戻しても MCP サーバーが応答しない ($server)"; }
      fail "$name: 更新後に$broken ので元の pixi.lock に戻した (詳しくはログ)"
      continue
    fi
    CHANGED+=("$lock")
    SUMMARY+=("$name (pixi.lock)")
  done
}

step_npx_pins() {
  local f spec pkg cur res pick newest tmp
  for f in "$NANOKIT_ROOT"/claude/scripts/* "$NANOKIT_ROOT"/tools/*/*; do
    [ -f "$f" ] || continue
    spec="$(grep -oE 'npx -y "@?[^"@]+@[0-9][^"]*"' "$f" | head -n 1)"
    [ -n "$spec" ] || continue
    command -v npm >/dev/null || { fail "npx-pins: npm が見つからない"; return; }
    spec="${spec#npx -y \"}"
    spec="${spec%\"}"
    pkg="${spec%@*}"
    cur="${spec##*@}"
    if ! res="$(npm_pick "$pkg" "$cur")"; then
      fail "$pkg: npm で版を調べられなかった"
      continue
    fi
    IFS='|' read -r pick newest <<<"$res"
    # メジャー版が上がると使い方が変わりうるので、自動では上げずにログに出すだけにする。
    if [ -n "$newest" ] && [ "$newest" != "$pick" ]; then
      say "$pkg: メジャー版 $newest が出ている (自動では上げない。${f#"$NANOKIT_ROOT"/} の版を手で上げる)"
    fi
    [ -n "$pick" ] || continue
    if $DRY_RUN; then
      say "$pkg: $cur → $pick"
      continue
    fi
    if dirty "$f"; then
      fail "$pkg: ${f#"$NANOKIT_ROOT"/} に未 commit の変更があるので飛ばした"
      continue
    fi
    tmp="$(mktemp)"
    sed "s|\"$pkg@$cur\"|\"$pkg@$pick\"|" "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
    if ! "$f" --version >>"$LOG" 2>&1; then
      revert "$f"
      fail "$pkg: $pick が --version で動かないので $cur に戻した"
      continue
    fi
    CHANGED+=("$f")
    SUMMARY+=("$pkg $cur → $pick")
  done
}

commit_and_push() {
  [ "${#CHANGED[@]}" -gt 0 ] || return 0
  # push してよいのは、追跡先があり、origin より遅れておらず、走る前に未 push の commit が無いときだけ。
  # 遅れているのと fetch できないのは手で直すことなので失敗として知らせ、未 push の commit は本人の作業なので触らない。
  local can_push=false why="" branch remote merge counts behind="" ahead="" names body sha
  branch="$(git_nk symbolic-ref -q --short HEAD)"
  remote="$(git_nk config "branch.$branch.remote" 2>/dev/null)"
  merge="$(git_nk config "branch.$branch.merge" 2>/dev/null)"
  if [ -z "$branch" ] || [ -z "$remote" ] || [ -z "$merge" ]; then
    why="追跡先のブランチが無い"
  elif ! git_nk fetch -q "$remote" >>"$LOG" 2>&1; then
    fail "git fetch が失敗したので push しない"
  elif ! counts="$(git_nk rev-list --left-right --count '@{u}...HEAD' 2>>"$LOG")"; then
    fail "origin との差を数えられなかったので push しない"
  else
    read -r behind ahead <<<"$counts"
    case "$behind:$ahead" in
      *[!0-9:]* | :* | *:) fail "origin との差を読めなかったので push しない ($counts)" ;;
      0:0) can_push=true ;;
      0:*) why="走る前から未 push の commit が $ahead 個あった" ;;
      *) fail "nanokit が origin より $behind commit 遅れているので push しない (pull してから push する)" ;;
    esac
  fi

  names="$(printf '%s\n' "${SUMMARY[@]}" | sed 's/ .*//' | paste -sd, - | sed 's/,/, /g')"
  body="$(printf -- '- %s\n' "${SUMMARY[@]}")"
  git_nk add -A -- "${CHANGED[@]}"
  if ! git_nk commit -q -m "chore(upgrade): update $names" \
      -m "nanokit upgrade が取り込んだ上流の更新。" -m "$body" -- "${CHANGED[@]}" >>"$LOG" 2>&1; then
    fail "git commit が失敗した (変更は作業ツリーに残っている)"
    return
  fi
  sha="$(git_nk rev-parse HEAD)"
  say "commit: $(git_nk log -1 --format='%h %s')"

  if $can_push; then
    # push.default などの設定によらず、この commit だけを追跡先へ送る。
    git_nk push -q "$remote" "$sha:$merge" >>"$LOG" 2>&1 || fail "git push が失敗した (commit は手元にある)"
  elif [ -n "$why" ]; then
    say "push しなかった ($why)"
  fi
}

step_npm_clis() {
  command -v npm >/dev/null || return 0
  local pair pkg sub cur res pick
  for pair in "@openai/codex:codex-update" "@google/gemini-cli:gemini-update"; do
    pkg="${pair%%:*}"
    sub="${pair##*:}"
    cur="$(npm ls -g --depth=0 "$pkg" 2>/dev/null | grep -oE "$pkg@[0-9][^ ]*" | head -n 1)"
    [ -n "$cur" ] || continue
    cur="${cur##*@}"
    if ! res="$(npm_pick "$pkg" "$cur")"; then
      fail "$pkg: npm で版を調べられなかった"
      continue
    fi
    IFS='|' read -r _ pick <<<"$res"
    [ -n "$pick" ] || continue
    if $DRY_RUN; then
      say "$pkg: $cur → $pick"
      continue
    fi
    if "$NANOKIT_ROOT/nanokit" "$sub" >>"$LOG" 2>&1; then
      SUMMARY+=("$pkg $cur → $pick")
    else
      fail "$pkg: nanokit $sub が失敗した"
    fi
  done
}

step_gh_ext() {
  command -v gh >/dev/null || return 0
  [ -n "$(gh extension list 2>/dev/null)" ] || return 0
  if $DRY_RUN; then
    run_quiet gh extension upgrade --all --dry-run || fail "gh-ext: gh extension upgrade --dry-run が失敗した"
    return
  fi
  run_quiet gh extension upgrade --all || fail "gh-ext: gh extension upgrade が失敗した"
}

step_pixi_global() {
  command -v pixi >/dev/null || return 0
  if $DRY_RUN; then
    say "pixi global: 試し実行の手段がないので飛ばした"
    return
  fi
  # 壊れたときに前の版へ戻す手がかりとして、更新前の一覧を残す。
  pixi global list >"$STATE_DIR/pixi-global-before.txt" 2>&1
  # pixi global update は、新しい版が出すコマンドを pixi-global.toml の exposed に書き足すことがある。
  # 走る前に手を入れていなかったときだけ、その書き換えを commit に含める。
  local manifest="$NANOKIT_ROOT/pixi-global.toml" was_dirty=false out rc
  dirty "$manifest" && was_dirty=true
  out="$(pixi global update 2>&1)"
  rc=$?
  printf '%s\n' "$out" >>"$LOG"
  [ "$rc" -eq 0 ] || fail "pixi-global: pixi global update が失敗した (exit $rc)"
  printf '%s\n' "$out" | grep -E '^\(updated\)' | while read -r line; do say "pixi global $line"; done
  if ! $was_dirty && dirty "$manifest"; then
    CHANGED+=("$manifest")
    SUMMARY+=("pixi-global.toml (pixi global update が書き足した exposed)")
  fi
}

report() {
  local msg="" ref="$LAST_RUN"
  [ -s "$FAILED" ] && msg="$(cat "$FAILED")"
  # 登録してあるのに 3 日以上走っていなければ、それ自体を失敗として知らせる。
  if [ -f "$PLIST_DST" ]; then
    [ -f "$ref" ] || ref="$PLIST_DST"
    if [ -n "$(find "$ref" -mmin +4320 2>/dev/null)" ]; then
      msg="${msg:+$msg
}nanokit upgrade が 3 日以上走っていない (launchd の $LABEL を確かめる)"
    fi
  fi
  [ -n "$msg" ] || return 0
  MSG="$msg" LOG_PATH="$LOG" python3 -c '
import json, os
msg = "nanokit upgrade に失敗した項目がある。\n" + os.environ["MSG"] + "\n詳しくは " + os.environ["LOG_PATH"]
print(json.dumps({
    "systemMessage": "⚠️ " + msg,
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "[nanokit-upgrade] " + msg},
}, ensure_ascii=False))
'
}

schedule() {
  [ "$(uname)" = Darwin ] || { echo "launchd は macOS だけ。Linux では cron などから nanokit upgrade を呼ぶ" >&2; return 1; }
  mkdir -p "$STATE_DIR" "$(dirname "$PLIST_DST")"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  # symlink にせずコピーで置く。リンクの plist はログインのときに読まれないことがある。
  cp "$PLIST_SRC" "$PLIST_DST"
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" && echo "登録した: $LABEL (毎日 04:30)"
}

unschedule() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST_DST"
  echo "解除した: $LABEL"
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      --accept-held) ACCEPT_HELD=true ;;
      --report) report; return 0 ;;
      --schedule) schedule; return ;;
      --unschedule) unschedule; return ;;
      *) echo "usage: nanokit upgrade [--dry-run] [--accept-held] [--schedule|--unschedule]" >&2; return 2 ;;
    esac
  done

  mkdir -p "$STATE_DIR"
  # 同時に 2 本走らせない。ロックの持ち主 (pid) がもう居ないか、再起動のあとで同じ番号を
  # 別のプロセスが使っているだけなら、前の回が落ちた跡として外す。
  local pid
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if { [ -n "$pid" ] && ps -p "$pid" -o command= 2>/dev/null | grep -q 'nanokit-upgrade'; } \
        || { [ -z "$pid" ] && [ -z "$(find "$LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }; then
      echo "nanokit upgrade はほかで実行中" >&2
      return 0
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "ロックを取れない: $LOCK_DIR" >&2; return 1; }
  fi
  echo "$$" >"$LOCK_DIR/pid"
  trap release_lock EXIT
  [ -f "$LOG" ] && tail -n 5000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"

  say "== nanokit upgrade$($DRY_RUN && echo ' (dry-run)')"
  step_skills
  step_spark
  step_pixi_locks
  step_npx_pins
  step_pixi_global
  $DRY_RUN || commit_and_push
  step_npm_clis
  step_gh_ext

  if $DRY_RUN; then
    say "試し実行なので何も書き換えていない"
    [ "${#FAILS[@]}" -eq 0 ]
    return
  fi
  touch "$LAST_RUN"
  if [ "${#SUMMARY[@]}" -gt 0 ]; then
    say "取り込んだもの: $(printf '%s; ' "${SUMMARY[@]}")"
  fi
  if [ "${#FAILS[@]}" -gt 0 ]; then
    printf -- '- %s\n' "${FAILS[@]}" >"$FAILED"
    return 1
  fi
  rm -f "$FAILED"
  say "すべて最新"
  return 0
}

main "$@"
