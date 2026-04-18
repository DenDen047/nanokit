#!/bin/bash
# zotero-mcp HTTP server lifecycle management
# Usage: zotero-mcp-server.sh [start|stop|status]
#
# Mode is auto-detected:
#   - local (Zotero.app running) → ZOTERO_LOCAL=true, uses Zotero's local API on :23119
#   - web  (Zotero.app absent)   → ZOTERO_LOCAL=false, uses api.zotero.org via Web API
#
# Web API mode requires credentials in the OS secret store (claude-zotero/api-key,
# claude-zotero/library-id). Register via: nanokit zotero-mcp-install

# Graceful exit for environments without pixi (SessionStart hook runs everywhere).
command -v pixi >/dev/null 2>&1 || exit 0

PORT="${ZOTERO_MCP_PORT:-8321}"
HOST="localhost"
PID_FILE="$HOME/.claude/zotero-mcp.pid"
LOG_FILE="$HOME/.claude/debug/zotero-mcp.log"

# Resolve the nanokit repo root even when invoked via the dotter symlink at
# ~/.claude/scripts/zotero-mcp-server.sh. Uses BASH_SOURCE (more reliable than $0)
# and a POSIX-portable link resolver (BSD readlink has no -f on older macOS).
_resolve_link() {
  local p="$1"
  while [[ -L "$p" ]]; do
    local l; l="$(readlink "$p")"
    [[ "$l" = /* ]] && p="$l" || p="$(dirname "$p")/$l"
  done
  echo "$p"
}
NANOKIT_ROOT="$(cd "$(dirname "$(_resolve_link "${BASH_SOURCE[0]}")")/../.." && pwd)"
[[ -f "$NANOKIT_ROOT/lib/secret.sh" ]] && . "$NANOKIT_ROOT/lib/secret.sh"

ZOTERO_MCP_MANIFEST="$NANOKIT_ROOT/claude/mcp-servers/zotero-mcp/pixi.toml"

# BINARY_CMD: allow ZOTERO_MCP_BINARY override for manual/debug runs and for
# rolling back to the old uv-tool install during migration. Default is pixi run.
if [[ -n "${ZOTERO_MCP_BINARY:-}" ]]; then
  BINARY_CMD=("$ZOTERO_MCP_BINARY")
else
  BINARY_CMD=(pixi run --manifest-path "$ZOTERO_MCP_MANIFEST" zotero-mcp)
fi

detect_zotero_mode() {
  if curl -sf -m 2 -o /dev/null "http://localhost:23119/connector/ping" 2>/dev/null; then
    echo "local"
  else
    echo "web"
  fi
}

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

  rm -f "$PID_FILE"
  mkdir -p "$(dirname "$LOG_FILE")"

  local mode
  mode=$(detect_zotero_mode)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] zotero-mcp starting mode=$mode" >> "$LOG_FILE"

  if [[ "$mode" == "local" ]]; then
    env ZOTERO_LOCAL=true nohup "${BINARY_CMD[@]}" serve \
      --transport streamable-http \
      --host "$HOST" \
      --port "$PORT" \
      >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
  else
    if ! type get_secret >/dev/null 2>&1; then
      echo "ERROR: lib/secret.sh not found at $NANOKIT_ROOT/lib/secret.sh" >&2
      exit 1
    fi

    local api_key library_id
    api_key=$(get_secret "claude-zotero" "api-key")
    library_id=$(get_secret "claude-zotero" "library-id")

    if [[ -z "$api_key" || -z "$library_id" ]]; then
      echo "ERROR: Zotero API credentials not registered." >&2
      echo "Run: nanokit zotero-mcp-install" >&2
      exit 1
    fi

    env ZOTERO_LOCAL=false \
        ZOTERO_API_KEY="$api_key" \
        ZOTERO_LIBRARY_ID="$library_id" \
        ZOTERO_LIBRARY_TYPE="user" \
      nohup "${BINARY_CMD[@]}" serve \
        --transport streamable-http \
        --host "$HOST" \
        --port "$PORT" \
        >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
  fi

  # Wait for ready (max 15s). Pixi activation can add a few seconds on first run.
  for i in $(seq 1 30); do
    if [ -n "$(get_pid_on_port)" ] && health_check; then
      echo "zotero-mcp started mode=$mode (PID $(cat "$PID_FILE"))" >&2
      exit 0
    fi
    sleep 0.5
  done

  echo "zotero-mcp failed to start mode=$mode (check $LOG_FILE)" >&2
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
