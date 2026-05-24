#!/bin/bash
# scrapling-mcp HTTP server lifecycle management
# Usage: scrapling-mcp-server.sh [start|stop|status]
#
# Serves Scrapling's web-scraping tools as a single shared streamable-http
# endpoint (http://localhost:8323/mcp) so that Claude Code AND Codex (and any
# other MCP client) connect to ONE long-lived process via the same URL, rather
# than each client spawning its own stdio process + Playwright/Chromium.
#
# Mirrors the lifecycle pattern of zotero-mcp-server.sh / workspace-mcp-personal-server.sh.
# Scrapling needs no credentials, so there is no secret-store wiring here.

# Graceful exit for environments without pixi (SessionStart hook runs everywhere).
command -v pixi >/dev/null 2>&1 || exit 0

PORT="${SCRAPLING_MCP_PORT:-8323}"
HOST="127.0.0.1"
PID_FILE="$HOME/.claude/scrapling-mcp.pid"
LOG_FILE="$HOME/.claude/debug/scrapling-mcp.log"

# Resolve this script's real location (it is dotter-symlinked into ~/.claude/scripts)
# so we can locate the pixi manifest at <nanokit>/claude/mcp-servers/scrapling/pixi.toml.
# BSD readlink on older macOS has no -f, so follow links manually.
_resolve_link() {
  local p="$1"
  while [[ -L "$p" ]]; do
    local l; l="$(readlink "$p")"
    [[ "$l" = /* ]] && p="$l" || p="$(dirname "$p")/$l"
  done
  echo "$p"
}

SCRIPT_REAL="$(_resolve_link "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_REAL")" && pwd)"
MANIFEST="${SCRAPLING_MCP_MANIFEST:-$SCRIPT_DIR/../mcp-servers/scrapling/pixi.toml}"

health_check() {
  local exit_code
  curl -sf -m 3 -o /dev/null "http://${HOST}:${PORT}/mcp" 2>/dev/null
  exit_code=$?
  # streamable-http returns 4xx for a bare GET → curl exit 22 (HTTP error) = healthy
  # connection refused → curl exit 7 = unhealthy
  [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 22 ]
}

get_pid_on_port() {
  lsof -i ":${PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1
}

cmd_start() {
  local existing_pid
  existing_pid=$(get_pid_on_port)

  if [ -n "$existing_pid" ]; then
    if health_check; then
      echo "scrapling-mcp already running (PID $existing_pid)" >&2
      exit 0
    fi
    # Port occupied but unhealthy → kill and restart
    kill "$existing_pid" 2>/dev/null
    sleep 1
  fi

  if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: scrapling pixi manifest not found at $MANIFEST" >&2
    exit 1
  fi

  rm -f "$PID_FILE"
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] scrapling-mcp starting port=$PORT manifest=$MANIFEST" >> "$LOG_FILE"

  nohup pixi run --manifest-path "$MANIFEST" mcp --http --host "$HOST" --port "$PORT" \
    >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  # Wait for ready (max 30s). Cold start (pixi activation + FastMCP init) can take time.
  for i in $(seq 1 60); do
    if [ -n "$(get_pid_on_port)" ] && health_check; then
      echo "scrapling-mcp started (PID $(cat "$PID_FILE"), port $PORT)" >&2
      exit 0
    fi
    sleep 0.5
  done

  echo "scrapling-mcp failed to start (check $LOG_FILE)" >&2
  exit 1
}

cmd_stop() {
  local pid
  pid=$(get_pid_on_port)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$PID_FILE"
  echo "scrapling-mcp stopped" >&2
}

cmd_status() {
  local pid
  pid=$(get_pid_on_port)
  if [ -n "$pid" ] && health_check; then
    echo "running (PID $pid, port $PORT)" >&2
  else
    echo "stopped" >&2
    exit 1
  fi
}

case "${1:-start}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  *)      echo "Usage: $0 [start|stop|status]" >&2; exit 1 ;;
esac
