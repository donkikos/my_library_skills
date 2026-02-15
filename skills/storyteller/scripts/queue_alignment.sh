#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
. "$SCRIPT_DIR/_common.sh"

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
RESTART=0
CANCEL=0
BOOK_UUID=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") <book_uuid> [--api URL] [--token-file PATH] [--restart] [--cancel]

Queue or cancel Storyteller alignment for one book.
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
    --restart)
      RESTART=1
      shift
      ;;
    --cancel)
      CANCEL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [ -z "$BOOK_UUID" ]; then
        BOOK_UUID="$1"
      else
        echo "Unexpected extra positional argument: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$BOOK_UUID" ]; then
  usage
  exit 1
fi

if [ "$RESTART" -eq 1 ] && [ "$CANCEL" -eq 1 ]; then
  echo "Use either --restart or --cancel, not both." >&2
  exit 1
fi

require_cmd curl
TOKEN="$(resolve_token "$TOKEN_FILE")"

METHOD="POST"
URL="$API_BASE/api/v2/books/$BOOK_UUID/process"
if [ "$RESTART" -eq 1 ]; then
  URL="$URL?restart=1"
fi
if [ "$CANCEL" -eq 1 ]; then
  METHOD="DELETE"
fi

HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' -X "$METHOD" "$URL" -H "Authorization: Bearer $TOKEN")"
echo "${METHOD}_HTTP=$HTTP_CODE"

BOOK_JSON="$(curl -fsS "$API_BASE/api/v2/books/$BOOK_UUID" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$BOOK_JSON" | jq -r '"title=" + .title + " | readaloud_status=" + (.readaloud.status // "-") + " | stage=" + (.readaloud.currentStage // "-") + " | queuePosition=" + ((.readaloud.queuePosition|tostring) // "-") + " | restartPending=" + ((.readaloud.restartPending|tostring) // "-")'
else
  printf '%s\n' "$BOOK_JSON"
fi
