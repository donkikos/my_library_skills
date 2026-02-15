#!/usr/bin/env bash

set -euo pipefail

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
USERNAME_OR_EMAIL=""
CLEAR_CLIPBOARD=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") --username-or-email USER [--api URL] [--token-file PATH] [--clear-clipboard]

Read a Storyteller password from macOS clipboard (pbpaste), request a token,
and store it securely as a token file.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --username-or-email)
      USERNAME_OR_EMAIL="$2"
      shift 2
      ;;
    --api)
      API_BASE="$2"
      shift 2
      ;;
    --token-file)
      TOKEN_FILE="$2"
      shift 2
      ;;
    --clear-clipboard)
      CLEAR_CLIPBOARD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$USERNAME_OR_EMAIL" ]; then
  echo "Missing required --username-or-email" >&2
  usage
  exit 1
fi

for cmd in curl jq pbpaste; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

PASSWORD="$(pbpaste | perl -0777 -pe 's/\r?\n\z//')"
if [ -z "$PASSWORD" ]; then
  echo "Clipboard is empty. Copy the Storyteller password first." >&2
  exit 1
fi

RESP="$(printf '%s' "$PASSWORD" | curl -sS -w '\n%{http_code}' -X POST "$API_BASE/api/v2/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "usernameOrEmail=$USERNAME_OR_EMAIL" \
  --data-urlencode 'password@-')"

HTTP_CODE="$(printf '%s\n' "$RESP" | tail -n 1)"
BODY="$(printf '%s\n' "$RESP" | sed '$d')"

if [ "$HTTP_CODE" != "200" ]; then
  echo "Token request failed (HTTP $HTTP_CODE)" >&2
  printf '%s\n' "$BODY" >&2
  exit 1
fi

TOKEN="$(printf '%s' "$BODY" | jq -er '.access_token')"
if [ -z "$TOKEN" ]; then
  echo "Token response did not include access_token" >&2
  printf '%s\n' "$BODY" >&2
  exit 1
fi

TOKEN_DIR="$(dirname "$TOKEN_FILE")"
mkdir -p "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"
printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

if [ "$CLEAR_CLIPBOARD" -eq 1 ] && command -v pbcopy >/dev/null 2>&1; then
  printf '' | pbcopy
fi

echo "Saved token to: $TOKEN_FILE"
