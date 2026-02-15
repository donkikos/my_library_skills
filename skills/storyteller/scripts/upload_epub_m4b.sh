#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
. "$SCRIPT_DIR/_common.sh"

API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
COLLECTION_UUID=""
BOOK_UUID=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") <epub_path> <m4b_path> [--book-uuid UUID] [--collection UUID] [--api URL] [--token-file PATH]

Upload one EPUB and one M4B into Storyteller as the same book via TUS.
USAGE
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

EPUB_PATH="$1"
M4B_PATH="$2"
shift 2

while [ $# -gt 0 ]; do
  case "$1" in
    --book-uuid)
      BOOK_UUID="$2"
      shift 2
      ;;
    --collection)
      COLLECTION_UUID="$2"
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
require_cmd file
require_cmd uuidgen

if [ ! -f "$EPUB_PATH" ]; then
  echo "EPUB not found: $EPUB_PATH" >&2
  exit 1
fi
if [ ! -f "$M4B_PATH" ]; then
  echo "M4B not found: $M4B_PATH" >&2
  exit 1
fi

if [ -z "$BOOK_UUID" ]; then
  BOOK_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
fi

TOKEN="$(resolve_token "$TOKEN_FILE")"

upload_one() {
  local file_path="$1"
  local relative_path="$2"
  local filename filetype size metadata headers_file location_url upload_url patch_code

  filename="$(basename "$file_path")"
  filetype="$(file -b --mime-type "$file_path")"
  size="$(wc -c < "$file_path" | tr -d ' ')"

  metadata="bookUuid $(b64_no_newline "$BOOK_UUID"),filename $(b64_no_newline "$filename"),filetype $(b64_no_newline "$filetype"),relativePath $(b64_no_newline "$relative_path")"
  if [ -n "$COLLECTION_UUID" ]; then
    metadata="$metadata,collection $(b64_no_newline "$COLLECTION_UUID")"
  fi

  headers_file="$(mktemp)"
  curl -sS -D "$headers_file" -o /dev/null -X POST "$API_BASE/api/v2/books/upload" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Tus-Resumable: 1.0.0' \
    -H "Upload-Length: $size" \
    -H "Upload-Metadata: $metadata"

  location_url="$(parse_location_header "$headers_file")"
  rm -f "$headers_file"

  if [ -z "$location_url" ]; then
    echo "Upload creation failed for $file_path" >&2
    exit 1
  fi

  case "$location_url" in
    http://*|https://*) upload_url="$location_url" ;;
    *) upload_url="$API_BASE$location_url" ;;
  esac

  patch_code="$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH "$upload_url" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Tus-Resumable: 1.0.0' \
    -H 'Upload-Offset: 0' \
    -H 'Content-Type: application/offset+octet-stream' \
    --data-binary @"$file_path")"

  if [ "$patch_code" != "204" ]; then
    echo "Upload PATCH failed for $file_path (HTTP $patch_code)" >&2
    exit 1
  fi

  echo "Uploaded: $filename"
}

upload_one "$EPUB_PATH" "$(basename "$EPUB_PATH")"
upload_one "$M4B_PATH" "$(basename "$M4B_PATH")"

echo "BOOK_UUID=$BOOK_UUID"

BOOK_JSON="$(curl -sS "$API_BASE/api/v2/books/$BOOK_UUID" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json' || true)"
if [ -n "$BOOK_JSON" ] && command -v jq >/dev/null 2>&1; then
  printf '%s' "$BOOK_JSON" | jq -r 'if .uuid then "FOUND: " + .title + " | uuid=" + .uuid + " | readaloud_status=" + (.readaloud.status // "-") else . end'
else
  printf '%s\n' "$BOOK_JSON"
fi
