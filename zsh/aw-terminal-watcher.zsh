#!/usr/bin/env zsh
# aw-terminal-watcher.zsh
# ActivityWatch 用の軽量ターミナル・ウォッチャー。
#
# 目的: 「クライアント案件 = リポジトリ/ワークスペース」の対応付けを passive に記録する。
#   標準の aw-watcher-window はアプリ名とタイトルしか取れず、ターミナル作業は
#   "✳ Claude Code" のように案件が判別できない。ここでは precmd/cd のたびに
#   「今いる git リポジトリ(なければ作業ディレクトリ名)」をローカル aw-server の
#   カスタムバケットへ heartbeat し、後段でクライアント別に集計できるようにする。
#   ローカルシェルだけでなく SSH 先のシェルにも同じファイルを置けば、リモート作業の
#   cwd も拾える(その場合は下の AW_TERM_SERVER をトンネル等で到達可能なURLにする)。
#
# 設計メモ:
#   - fire-and-forget (バックグラウンド + 短いタイムアウト)。プロンプトを遅くしない。
#   - aw-server が落ちていても無害 (curl が失敗して終わるだけ)。
#   - 長時間フォアグラウンド・コマンド(claude / vim / 訓練ジョブ / ssh など)の実行中は
#     シェルがブロックされ precmd が発火しない。そこで preexec(コマンド開始直前)でも
#     heartbeat を打って「起動時のリポジトリ」を記録し、pulsetime を十分大きく(既定8h)
#     取ることで「開始〜終了」の長い空白を1つの同一リポジトリ滞在イベントに連結する。
#     真のアイドル/離席は afk ウォッチャーの not-afk 区間と後段で intersection して
#     除外する前提なので、pulsetime を大きくしても離席は二重に除ける。
#     (pulsetime を超える単発セッションは分割されるが、その長さの連続作業は稀。)
#   - イベントの data は {project, repo, host} のみ。git リポジトリ内ではサブディレクトリを
#     移動しても project/repo が不変なので、リポジトリ滞在が途切れず1イベントに連結される。

# ---- 設定 (ここだけ触ればよい) ----
: ${AW_TERM_SERVER:=http://localhost:5600}   # ローカル aw-server の baseURL
: ${AW_TERM_PULSETIME:=28800}                # イベント連結を許すギャップ上限(秒). 既定8h.
                                             # 長時間 claude 実行(開始〜終了)を1イベントに繋ぐため
# -----------------------------------

# 対話シェル以外(スクリプト実行など)では何もしない
[[ -o interactive ]] || return 0

autoload -Uz add-zsh-hook

_AW_TERM_HOST="${HOST:-$(hostname)}"
_AW_TERM_BUCKET="aw-watcher-terminal_${_AW_TERM_HOST}"
_AW_TERM_URL="${AW_TERM_SERVER}/api/0/buckets/${_AW_TERM_BUCKET}/heartbeat?pulsetime=${AW_TERM_PULSETIME}"

# バケットを一度だけ作成 (既存なら 304 で無害)。バックグラウンドで投げる。
{ curl -s -m 2 -XPOST "${AW_TERM_SERVER}/api/0/buckets/${_AW_TERM_BUCKET}" \
    -H 'Content-Type: application/json' \
    -d "{\"client\":\"aw-watcher-terminal\",\"type\":\"currentcwd\",\"hostname\":\"${_AW_TERM_HOST}\"}" \
    >/dev/null 2>&1 ; } &!

# JSON 文字列エスケープ (jq 非依存にして heartbeat ごとの fork を避ける)
_aw_term_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  print -r -- "$s"
}

_aw_term_heartbeat() {
  emulate -L zsh
  local cwd="$PWD" repo reponame project ts data
  repo="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$repo" ]]; then
    project="${repo:t}"          # git リポジトリ名 = 案件キー
  else
    project="${cwd:t}"           # 非gitなら作業ディレクトリ名
  fi
  project="$(_aw_term_esc "$project")"
  repo="$(_aw_term_esc "$repo")"
  ts="$(date -u +%Y-%m-%dT%H:%M:%S.000000+00:00)"
  data="{\"timestamp\":\"${ts}\",\"duration\":0,\"data\":{\"project\":\"${project}\",\"repo\":\"${repo}\",\"host\":\"${_AW_TERM_HOST}\"}}"
  { curl -s -m 1 -XPOST "$_AW_TERM_URL" -H 'Content-Type: application/json' -d "$data" >/dev/null 2>&1 ; } &!
}

add-zsh-hook preexec _aw_term_heartbeat   # コマンド開始時(=claude 起動時)にリポジトリを記録
add-zsh-hook precmd  _aw_term_heartbeat   # プロンプト復帰時(=コマンド終了時)に記録
add-zsh-hook chpwd   _aw_term_heartbeat   # cd 時に記録
