#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
. "$SCRIPT_DIR/_common.sh"

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
RAW_JSON=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--api URL] [--token-file PATH] [--json]

List books from Storyteller.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --api)
      API_BASE="$2"
      shift 2
      ;;
    --token-file)
      TOKEN_FILE="$2"
      shift 2
      ;;
    --json)
      RAW_JSON=1
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

require_cmd curl
TOKEN="$(resolve_token "$TOKEN_FILE")"
JSON="$(curl -fsS "$API_BASE/api/v2/books" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')"

if [ "$RAW_JSON" -eq 1 ] || ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$JSON"
  exit 0
fi

printf '%s' "$JSON" | jq -r 'to_entries[] | "\(.key + 1). \(.value.title) | uuid=\(.value.uuid) | readaloud_status=\(.value.readaloud.status // "-")"'
