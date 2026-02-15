#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
. "$SCRIPT_DIR/_common.sh"

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
LOG_LINES="${STORYTELLER_LOG_LINES:-400}"
SERVICE_NAME="${STORYTELLER_DOCKER_SERVICE:-web}"
COMPOSE_DIR="${STORYTELLER_COMPOSE_DIR:-}"
CONTAINER_NAME="${STORYTELLER_CONTAINER_NAME:-}"
NO_LOGS=0
BOOK_UUID=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") <book_uuid> [--api URL] [--token-file PATH] [--logs-lines N] [--service NAME] [--compose-dir PATH] [--container NAME] [--no-logs]

Diagnose Storyteller alignment issues by combining API status with recent logs.
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
    --logs-lines)
      LOG_LINES="$2"
      shift 2
      ;;
    --service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    --compose-dir)
      COMPOSE_DIR="$2"
      shift 2
      ;;
    --container)
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --no-logs)
      NO_LOGS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
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

if ! [[ "$LOG_LINES" =~ ^[0-9]+$ ]] || [ "$LOG_LINES" -lt 1 ]; then
  echo "--logs-lines must be a positive integer" >&2
  exit 1
fi

require_cmd curl
require_cmd jq
TOKEN="$(resolve_token "$TOKEN_FILE")"

BOOK_JSON="$(curl -fsS "$API_BASE/api/v2/books/$BOOK_UUID" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')"

TITLE="$(printf '%s' "$BOOK_JSON" | jq -r '.title // ""')"
BOOK_PATH="$(printf '%s' "$BOOK_JSON" | jq -r '.path // ""')"
READALOUD_STATUS="$(printf '%s' "$BOOK_JSON" | jq -r '.readaloud.status // "-"')"
CURRENT_STAGE="$(printf '%s' "$BOOK_JSON" | jq -r '.readaloud.currentStage // "-"')"
QUEUE_POSITION="$(printf '%s' "$BOOK_JSON" | jq -r '.readaloud.queuePosition // "-"')"
RESTART_PENDING="$(printf '%s' "$BOOK_JSON" | jq -r '.readaloud.restartPending // "-"')"
API_ERROR="$(printf '%s' "$BOOK_JSON" | jq -r '[.readaloud.error, .readaloud.lastError, .readaloud.message, .error, .lastError, .message] | map(select(type == "string" and length > 0)) | .[0] // ""')"

printf 'book_uuid=%s\n' "$BOOK_UUID"
printf 'title=%s\n' "$TITLE"
printf 'path=%s\n' "$BOOK_PATH"
printf 'readaloud_status=%s\n' "$READALOUD_STATUS"
printf 'current_stage=%s\n' "$CURRENT_STAGE"
printf 'queue_position=%s\n' "$QUEUE_POSITION"
printf 'restart_pending=%s\n' "$RESTART_PENDING"
if [ -n "$API_ERROR" ]; then
  printf 'api_error=%s\n' "$API_ERROR"
fi

discover_container() {
  docker ps --format '{{.Names}}' | awk '/storyteller/ && /web/ {print; exit}'
}

collect_logs() {
  local logs_output=""

  require_cmd docker

  if [ -n "$CONTAINER_NAME" ]; then
    docker logs --tail "$LOG_LINES" "$CONTAINER_NAME" 2>&1
    return 0
  fi

  if [ -n "$COMPOSE_DIR" ]; then
    if logs_output="$(cd "$COMPOSE_DIR" && docker compose logs -n "$LOG_LINES" "$SERVICE_NAME" 2>&1)"; then
      printf '%s' "$logs_output"
      return 0
    fi
  fi

  if logs_output="$(docker compose logs -n "$LOG_LINES" "$SERVICE_NAME" 2>&1)"; then
    printf '%s' "$logs_output"
    return 0
  fi

  CONTAINER_NAME="$(discover_container || true)"
  if [ -n "$CONTAINER_NAME" ]; then
    docker logs --tail "$LOG_LINES" "$CONTAINER_NAME" 2>&1
    return 0
  fi

  return 1
}

LOG_OUTPUT=""
if [ "$NO_LOGS" -eq 0 ]; then
  if LOG_OUTPUT="$(collect_logs || true)"; then
    :
  fi
fi

if [ "$NO_LOGS" -eq 0 ]; then
  echo
  echo "--- Recent log lines (filtered) ---"

  BOOK_LINES="$(printf '%s\n' "$LOG_OUTPUT" | grep -F "$BOOK_UUID" || true)"
  if [ -z "$BOOK_LINES" ] && [ -n "$TITLE" ]; then
    BOOK_LINES="$(printf '%s\n' "$LOG_OUTPUT" | grep -F "$TITLE" || true)"
  fi
  if [ -z "$BOOK_LINES" ] && [ -n "$BOOK_PATH" ]; then
    PATH_TOKEN="$(basename "$BOOK_PATH")"
    BOOK_LINES="$(printf '%s\n' "$LOG_OUTPUT" | grep -F "$PATH_TOKEN" || true)"
  fi

  ERROR_LINES="$(printf '%s\n' "$LOG_OUTPUT" | grep -Ei 'ENOENT|ERROR|Exception|Unhandled|failed|FATAL' || true)"

  if [ -n "$BOOK_LINES" ]; then
    printf '%s\n' "$BOOK_LINES" | tail -n 60
  fi

  if [ -n "$ERROR_LINES" ]; then
    if [ -n "$BOOK_LINES" ]; then
      echo
    fi
    printf '%s\n' "$ERROR_LINES" | tail -n 40
  fi

  if [ -z "$BOOK_LINES" ] && [ -z "$ERROR_LINES" ]; then
    echo "No matching lines in recent logs. Increase --logs-lines or pass --compose-dir/--container."
  fi
fi

HAYSTACK="$API_ERROR"
if [ -n "$LOG_OUTPUT" ]; then
  HAYSTACK="$HAYSTACK
$LOG_OUTPUT"
fi

DIAGNOSIS=""
RECOVERY=""

if printf '%s' "$HAYSTACK" | grep -qiE 'ENOENT[^\n]*transcriptions/[^\n]*\.json'; then
  DIAGNOSIS="Missing transcription chunk files. Most likely path drift caused by metadata/path changes during processing."
  RECOVERY=$'1. Cancel processing.\n2. Keep title/series stable while processing.\n3. Requeue with restart.'
elif [ "$READALOUD_STATUS" = "PROCESSING" ] && [ "$CURRENT_STAGE" = "TRANSCRIBE_CHAPTERS" ] && printf '%s' "$LOG_OUTPUT" | grep -q 'Transcribing audio file'; then
  DIAGNOSIS="No fatal pattern detected. Job appears healthy and actively transcribing chunks."
  RECOVERY=$'1. Continue monitoring logs and stage.\n2. Avoid metadata/path edits until completion.'
elif [ "$READALOUD_STATUS" = "QUEUED" ]; then
  DIAGNOSIS="Job is queued and waiting for worker capacity."
  RECOVERY=$'1. Wait for queue position to advance.\n2. Check other jobs with scripts/list_books.sh.'
elif [ "$READALOUD_STATUS" = "ERROR" ] && [ -n "$API_ERROR" ]; then
  DIAGNOSIS="API reports an alignment error."
  RECOVERY=$'1. Inspect matching log lines above.\n2. Fix root cause.\n3. Requeue with --restart.'
else
  DIAGNOSIS="No known failure signature matched."
  RECOVERY=$'1. Pull more logs with a larger --logs-lines value.\n2. Re-run with --compose-dir or --container for precise log source.'
fi

echo
echo "--- Diagnosis ---"
printf '%s\n' "$DIAGNOSIS"

echo
echo "--- Suggested recovery ---"
printf '%s\n' "$RECOVERY"

if [ "$READALOUD_STATUS" = "ERROR" ]; then
  echo
  echo "Helpful commands:"
  echo "  scripts/queue_alignment.sh $BOOK_UUID --cancel"
  echo "  scripts/queue_alignment.sh $BOOK_UUID --restart"
fi
