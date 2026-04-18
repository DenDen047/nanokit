#!/bin/bash
# lib/secret.sh — OS-agnostic secret retrieval
#
# Usage:
#   . "$NANOKIT_ROOT/lib/secret.sh"
#
# API:
#   get_secret <service> <account>
#     Returns the secret value to stdout.
#     Returns empty string (and exits 0) if not found.
#
#   store_secret <service> <account> <value>
#     Stores a secret in the OS credential store.
#
#   has_secret <service> <account>
#     Returns 0 if the secret exists, 1 otherwise.
#
# Backends (auto-detected):
#   macOS   → security find-generic-password (Keychain)
#   Linux   → secret-tool lookup (GNOME Keyring / libsecret)
#   fallback → $HOME/.config/nanokit/secrets.env

_NANOKIT_SECRET_BACKEND=""

_detect_secret_backend() {
  if [[ -n "$_NANOKIT_SECRET_BACKEND" ]]; then
    return
  fi

  case "$(uname -s)" in
    Darwin)
      _NANOKIT_SECRET_BACKEND="keychain"
      ;;
    Linux)
      if command -v secret-tool &>/dev/null; then
        _NANOKIT_SECRET_BACKEND="secret-tool"
      else
        _NANOKIT_SECRET_BACKEND="env-file"
      fi
      ;;
    *)
      _NANOKIT_SECRET_BACKEND="env-file"
      ;;
  esac
}

# get_secret <service> <account>
#   Retrieve a secret from the OS credential store.
#   Key format in env-file backend: SERVICE__ACCOUNT (dots/hyphens → underscores, uppercased)
get_secret() {
  local service="$1"
  local account="$2"

  _detect_secret_backend

  case "$_NANOKIT_SECRET_BACKEND" in
    keychain)
      security find-generic-password -s "$service" -a "$account" -w 2>/dev/null || echo ""
      ;;
    secret-tool)
      secret-tool lookup service "$service" account "$account" 2>/dev/null || echo ""
      ;;
    env-file)
      _get_secret_from_file "$service" "$account"
      ;;
  esac
}

# store_secret <service> <account> <value>
#   Store a secret in the OS credential store.
store_secret() {
  local service="$1"
  local account="$2"
  local value="$3"

  _detect_secret_backend

  case "$_NANOKIT_SECRET_BACKEND" in
    keychain)
      security delete-generic-password -s "$service" -a "$account" >/dev/null 2>&1 || true
      security add-generic-password -s "$service" -a "$account" -w "$value"
      ;;
    secret-tool)
      echo -n "$value" | secret-tool store --label="$service ($account)" service "$service" account "$account"
      ;;
    env-file)
      _store_secret_to_file "$service" "$account" "$value"
      ;;
  esac
}

# has_secret <service> <account>
#   Returns 0 if the secret exists, 1 otherwise.
has_secret() {
  local result
  result="$(get_secret "$1" "$2")"
  [[ -n "$result" ]]
}

# delete_secret <service> <account>
#   Remove a secret from the OS credential store.
delete_secret() {
  local service="$1"
  local account="$2"

  _detect_secret_backend

  case "$_NANOKIT_SECRET_BACKEND" in
    keychain)
      security delete-generic-password -s "$service" -a "$account" >/dev/null 2>&1 || true
      ;;
    secret-tool)
      secret-tool clear service "$service" account "$account" 2>/dev/null || true
      ;;
    env-file)
      _delete_secret_from_file "$service" "$account"
      ;;
  esac
}

# --- env-file backend helpers ---

_SECRETS_FILE="${HOME}/.config/nanokit/secrets.env"

_secret_env_key() {
  local service="$1"
  local account="$2"
  local key="${service}__${account}"
  key="${key//-/_}"
  key="${key//./_}"
  echo "${key^^}"
}

_get_secret_from_file() {
  local key
  key="$(_secret_env_key "$1" "$2")"

  if [[ ! -f "$_SECRETS_FILE" ]]; then
    echo ""
    return
  fi

  local line
  line=$(grep "^${key}=" "$_SECRETS_FILE" 2>/dev/null | head -1) || true
  if [[ -n "$line" ]]; then
    local val="${line#*=}"
    val="${val#\"}"
    val="${val%\"}"
    val="${val#\'}"
    val="${val%\'}"
    echo "$val"
  else
    echo ""
  fi
}

_store_secret_to_file() {
  local key
  key="$(_secret_env_key "$1" "$2")"
  local value="$3"

  mkdir -p "$(dirname "$_SECRETS_FILE")"

  if [[ -f "$_SECRETS_FILE" ]]; then
    grep -v "^${key}=" "$_SECRETS_FILE" > "${_SECRETS_FILE}.tmp" 2>/dev/null || true
    mv "${_SECRETS_FILE}.tmp" "$_SECRETS_FILE"
  fi

  echo "${key}=\"${value}\"" >> "$_SECRETS_FILE"
  chmod 600 "$_SECRETS_FILE"
}

_delete_secret_from_file() {
  local key
  key="$(_secret_env_key "$1" "$2")"

  [[ -f "$_SECRETS_FILE" ]] || return 0
  grep -v "^${key}=" "$_SECRETS_FILE" > "${_SECRETS_FILE}.tmp" 2>/dev/null || true
  mv "${_SECRETS_FILE}.tmp" "$_SECRETS_FILE"
}
