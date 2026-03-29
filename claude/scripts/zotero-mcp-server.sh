#!/bin/bash
# zotero-mcp HTTP server lifecycle management
# Usage: zotero-mcp-server.sh [start|stop|status]

PORT="${ZOTERO_MCP_PORT:-8321}"
HOST="localhost"
PID_FILE="$HOME/.claude/zotero-mcp.pid"
LOG_FILE="$HOME/.claude/debug/zotero-mcp.log"
BINARY="${ZOTERO_MCP_BINARY:-$HOME/.local/bin/zotero-mcp}"

health_check() {
  local exit_code
  curl -sf -m 3 -o /dev/null "http://${HOST}:${PORT}/mcp" 2>/dev/null
  exit_code=$?
  # FastMCP returns 405 for GET → curl exit 22 (HTTP error) = healthy
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
      echo "zotero-mcp already running (PID $existing_pid)" >&2
      exit 0
    fi
    # Port occupied but unhealthy → kill and restart
    kill "$existing_pid" 2>/dev/null
    sleep 1
  fi

  # Clean stale PID file
  rm -f "$PID_FILE"
  mkdir -p "$(dirname "$LOG_FILE")"

  # Start server
  ZOTERO_LOCAL=true nohup "$BINARY" serve \
    --transport streamable-http \
    --host "$HOST" \
    --port "$PORT" \
    >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  # Wait for ready (max 15s)
  for i in $(seq 1 30); do
    if [ -n "$(get_pid_on_port)" ] && health_check; then
      echo "zotero-mcp started (PID $(cat "$PID_FILE"))" >&2
      exit 0
    fi
    sleep 0.5
  done

  echo "zotero-mcp failed to start (check $LOG_FILE)" >&2
  exit 1
}

cmd_stop() {
  local pid
  pid=$(get_pid_on_port)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$PID_FILE"
  echo "zotero-mcp stopped" >&2
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
