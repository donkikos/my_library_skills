#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
. "$SCRIPT_DIR/_common.sh"

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
FORCE_IF_PROCESSING=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") <book_uuid> <title> <series_uuid> <series_name> <series_position> [--api URL] [--token-file PATH] [--force-if-processing]

Update Storyteller title and series metadata for one book.
USAGE
}

if [ $# -lt 5 ]; then
  usage
  exit 1
fi

BOOK_UUID="$1"
TITLE="$2"
SERIES_UUID="$3"
SERIES_NAME="$4"
SERIES_POSITION="$5"
shift 5

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
    --force-if-processing)
      FORCE_IF_PROCESSING=1
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

if ! [[ "$SERIES_POSITION" =~ ^[0-9]+$ ]]; then
  echo "series_position must be an integer" >&2
  exit 1
fi

require_cmd curl
require_cmd jq
TOKEN="$(resolve_token "$TOKEN_FILE")"

BOOK_JSON="$(curl -fsS "$API_BASE/api/v2/books/$BOOK_UUID" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')"
READALOUD_STATUS="$(printf '%s' "$BOOK_JSON" | jq -r '.readaloud.status // ""')"

if [ "$FORCE_IF_PROCESSING" -ne 1 ] && { [ "$READALOUD_STATUS" = "PROCESSING" ] || [ "$READALOUD_STATUS" = "QUEUED" ]; }; then
  echo "Refusing metadata update while readaloud_status=$READALOUD_STATUS for $BOOK_UUID" >&2
  echo "Cancel processing first or rerun with --force-if-processing." >&2
  exit 1
fi

TITLE_JSON="$(jq -cn --arg t "$TITLE" '$t')"
SERIES_JSON="$(jq -cn --arg uuid "$SERIES_UUID" --arg name "$SERIES_NAME" --argjson position "$SERIES_POSITION" '{uuid:$uuid,name:$name,featured:1,position:$position}')"

curl -fsS -X PUT "$API_BASE/api/v2/books/$BOOK_UUID" \
  -H "Authorization: Bearer $TOKEN" \
  -F 'fields=title' \
  -F 'fields=series' \
  --form-string "title=$TITLE_JSON" \
  --form-string "series=$SERIES_JSON" \
| jq -r '{uuid,title,series,readaloud}'
