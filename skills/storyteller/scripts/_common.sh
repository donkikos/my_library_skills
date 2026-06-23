#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

credentials_available() {
  [ -n "${STORYTELLER_USERNAME_OR_EMAIL:-}" ] &&
    [ -n "${STORYTELLER_PASSWORD:-}" ]
}

require_complete_credentials() {
  if credentials_available; then
    return 0
  fi

  echo "Set both STORYTELLER_USERNAME_OR_EMAIL and STORYTELLER_PASSWORD to create or refresh a token." >&2
  return 1
}

save_token() {
  local token_file="$1"
  local token="$2"
  local token_dir temp_file

  token_dir="$(dirname "$token_file")"
  mkdir -p "$token_dir"
  chmod 700 "$token_dir"
  temp_file="$(mktemp "$token_dir/.storyteller_token.tmp.XXXXXX")"
  chmod 600 "$temp_file"
  printf '%s' "$token" > "$temp_file"
  mv -f "$temp_file" "$token_file"
  chmod 600 "$token_file"
}

refresh_token() {
  local token_file="$1"
  local api_base="$2"
  local response token

  require_complete_credentials || return 1
  require_cmd curl
  require_cmd jq

  if ! response="$(
    printf '%s' "$STORYTELLER_PASSWORD" |
      curl -fsS -X POST "$api_base/api/v2/token" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "usernameOrEmail=$STORYTELLER_USERNAME_OR_EMAIL" \
        --data-urlencode 'password@-'
  )"; then
    echo "Token refresh request failed." >&2
    return 1
  fi
  token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
  if [ -z "$token" ]; then
    echo "Token response did not include access_token." >&2
    return 1
  fi

  save_token "$token_file" "$token"
  printf '%s' "$token"
}

resolve_token() {
  local token_file="$1"
  local api_base="$2"
  local token="" http_code

  if [ -n "${STORYTELLER_TOKEN:-}" ]; then
    token="$STORYTELLER_TOKEN"
  elif [ -f "$token_file" ]; then
    token="$(tr -d '\n' < "$token_file")"
  fi

  if [ -z "$token" ]; then
    if credentials_available; then
      refresh_token "$token_file" "$api_base"
      return
    fi
    if [ -n "${STORYTELLER_USERNAME_OR_EMAIL:-}" ] ||
      [ -n "${STORYTELLER_PASSWORD:-}" ]; then
      require_complete_credentials
      return 1
    fi

    echo "Token file not found: $token_file" >&2
    echo "Set STORYTELLER_TOKEN, create the token file, or set both STORYTELLER_USERNAME_OR_EMAIL and STORYTELLER_PASSWORD." >&2
    return 1
  fi

  require_cmd curl
  if ! http_code="$(
    curl -sS -o /dev/null -w '%{http_code}' \
      "$api_base/api/v2/books" \
      -H "Authorization: Bearer $token" \
      -H 'Accept: application/json'
  )"; then
    echo "Could not reach Storyteller to validate the token." >&2
    return 1
  fi

  case "$http_code" in
    2??)
      printf '%s' "$token"
      ;;
    401)
      refresh_token "$token_file" "$api_base"
      ;;
    *)
      echo "Token validation failed (HTTP $http_code)." >&2
      return 1
      ;;
  esac
}

parse_location_header() {
  local header_file="$1"
  awk -F': ' 'tolower($1)=="location"{print $2}' "$header_file" | tr -d '\r' | tail -n 1
}

b64_no_newline() {
  printf '%s' "$1" | base64 | tr -d '\n'
}
