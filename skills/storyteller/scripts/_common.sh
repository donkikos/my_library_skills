#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

resolve_token() {
  local token_file="$1"

  if [ -n "${STORYTELLER_TOKEN:-}" ]; then
    printf '%s' "$STORYTELLER_TOKEN"
    return 0
  fi

  if [ ! -f "$token_file" ]; then
    echo "Token file not found: $token_file" >&2
    echo "Set STORYTELLER_TOKEN or create the token file first." >&2
    return 1
  fi

  tr -d '\n' < "$token_file"
}

parse_location_header() {
  local header_file="$1"
  awk -F': ' 'tolower($1)=="location"{print $2}' "$header_file" | tr -d '\r' | tail -n 1
}

b64_no_newline() {
  printf '%s' "$1" | base64 | tr -d '\n'
}
