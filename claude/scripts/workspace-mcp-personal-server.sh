#!/bin/bash
# workspace-mcp HTTP server lifecycle management (personal Google account)
# Usage: workspace-mcp-personal-server.sh [start|stop|status]
#
# Serves Google Workspace tools for sh.mn.nat@gmail.com as a single shared
# streamable-http endpoint so that parallel Claude Code sessions do not race
# on the OAuth refresh_token (Issue workspace-mcp #506/#667).
#
# Credentials (GOOGLE_OAUTH_CLIENT_ID / _SECRET) come from the OS secret
# store via lib/secret.sh (same source as templates/base/.envrc.defaults).

# Graceful exit for environments without uvx (SessionStart hook runs everywhere).
command -v uvx >/dev/null 2>&1 || exit 0

PORT="${WORKSPACE_MCP_PERSONAL_PORT:-8322}"
HOST="localhost"
PID_FILE="$HOME/.claude/workspace-mcp-personal.pid"
LOG_FILE="$HOME/.claude/debug/workspace-mcp-personal.log"

USER_GOOGLE_EMAIL_VALUE="${USER_GOOGLE_EMAIL:-sh.mn.nat@gmail.com}"
CREDENTIALS_DIR_VALUE="${WORKSPACE_MCP_CREDENTIALS_DIR:-$HOME/.config/google-workspace-mcp/personal}"

# Resolve claude-settings repo root from either invocation path:
#   ~/nanokit/claude/scripts/...        (direct)
#   ~/.claude/scripts/...               (dotter symlink)
# We need it to source lib/secret.sh for Keychain access.
_resolve_link() {
  local p="$1"
  while [[ -L "$p" ]]; do
    local l; l="$(readlink "$p")"
    [[ "$l" = /* ]] && p="$l" || p="$(dirname "$p")/$l"
  done
  echo "$p"
}

_find_claude_settings_dir() {
  if [[ -n "${CLAUDE_SETTINGS_DIR:-}" && -f "$CLAUDE_SETTINGS_DIR/lib/secret.sh" ]]; then
    echo "$CLAUDE_SETTINGS_DIR"
    return
  fi
  for d in "$HOME/Projects/claude-settings" "$HOME/Documents/Projects/claude-settings"; do
    if [[ -f "$d/lib/secret.sh" ]]; then
      echo "$d"
      return
    fi
  done
}

CLAUDE_SETTINGS_DIR_RESOLVED="$(_find_claude_settings_dir)"
if [[ -n "$CLAUDE_SETTINGS_DIR_RESOLVED" ]]; then
  . "$CLAUDE_SETTINGS_DIR_RESOLVED/lib/secret.sh"
fi

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
      echo "workspace-mcp-personal already running (PID $existing_pid)" >&2
      exit 0
    fi
    # Port occupied but unhealthy → kill and restart
    kill "$existing_pid" 2>/dev/null
    sleep 1
  fi

  rm -f "$PID_FILE"
  mkdir -p "$(dirname "$LOG_FILE")"
  mkdir -p "$CREDENTIALS_DIR_VALUE"

  if ! type get_secret >/dev/null 2>&1; then
    echo "ERROR: lib/secret.sh not found (searched CLAUDE_SETTINGS_DIR, ~/Projects/claude-settings, ~/Documents/Projects/claude-settings)" >&2
    exit 1
  fi

  local client_id client_secret
  client_id=$(get_secret "claude-google-oauth" "client-id")
  client_secret=$(get_secret "claude-google-oauth" "client-secret")

  if [[ -z "$client_id" || -z "$client_secret" ]]; then
    echo "ERROR: Google OAuth credentials not registered (claude-google-oauth/client-id,client-secret)." >&2
    echo "Register via setup-secrets.sh or security add-generic-password." >&2
    exit 1
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] workspace-mcp-personal starting port=$PORT email=$USER_GOOGLE_EMAIL_VALUE creds=$CREDENTIALS_DIR_VALUE" >> "$LOG_FILE"

  env GOOGLE_OAUTH_CLIENT_ID="$client_id" \
      GOOGLE_OAUTH_CLIENT_SECRET="$client_secret" \
      USER_GOOGLE_EMAIL="$USER_GOOGLE_EMAIL_VALUE" \
      WORKSPACE_MCP_CREDENTIALS_DIR="$CREDENTIALS_DIR_VALUE" \
      OAUTHLIB_INSECURE_TRANSPORT="1" \
      WORKSPACE_MCP_PORT="$PORT" \
    nohup uvx workspace-mcp \
      --transport streamable-http \
      --single-user \
      >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"

  # Wait for ready (max 30s). uvx install + FastMCP init can take time on cold start.
  for i in $(seq 1 60); do
    if [ -n "$(get_pid_on_port)" ] && health_check; then
      echo "workspace-mcp-personal started (PID $(cat "$PID_FILE"), port $PORT)" >&2
      exit 0
    fi
    sleep 0.5
  done

  echo "workspace-mcp-personal failed to start (check $LOG_FILE)" >&2
  exit 1
}

cmd_stop() {
  local pid
  pid=$(get_pid_on_port)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
  rm -f "$PID_FILE"
  echo "workspace-mcp-personal stopped" >&2
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
