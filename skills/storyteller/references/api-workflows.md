# Storyteller API Workflows

## Configuration and auth

```bash
STORYTELLER_API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
```

Token precedence: `STORYTELLER_TOKEN`, token file, then
`STORYTELLER_USERNAME_OR_EMAIL` plus `STORYTELLER_PASSWORD` if no token exists
or a protected request returns HTTP `401`. Refresh once, overwrite the token
file, and retry. Scripts set directory mode `700` and file mode `600`.

Clipboard bootstrap:

```bash
scripts/get_token_from_clipboard.sh --username-or-email <username-or-email> --clear-clipboard
```

Compact raw bootstrap:

```bash
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
umask 077
mkdir -p "$(dirname "$TOKEN_FILE")"
chmod 700 "$(dirname "$TOKEN_FILE")"
TOKEN="$(pbpaste | curl -fsS -X POST "${STORYTELLER_API_BASE:-http://localhost:8001}/api/v2/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'usernameOrEmail=<username-or-email>' \
  --data-urlencode 'password@-' | jq -r '.access_token // empty')"
[ -n "$TOKEN" ] || { echo "Token endpoint returned no access token" >&2; exit 1; }
TEMP_FILE="$(mktemp "$(dirname "$TOKEN_FILE")/.token.tmp.XXXXXX")"
chmod 600 "$TEMP_FILE"
printf '%s\n' "$TOKEN" > "$TEMP_FILE"
mv -f "$TEMP_FILE" "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
```

## Endpoint map

- Books: `GET /api/v2/books`
- TUS upload: `POST /api/v2/books/upload`, then `PATCH <Location>`
- Metadata: `PUT /api/v2/books/{bookId}` using multipart `fields=title`,
  `fields=series`, JSON-string title, and JSON-object series
- Process: `POST /api/v2/books/{bookId}/process`; restart with `?restart=1`;
  cancel with `DELETE /api/v2/books/{bookId}/process`
- Book status: `GET /api/v2/books/{bookId}`
- Events: `GET /api/v2/books/events` with `Accept: text/event-stream`

TUS `POST` headers: `Tus-Resumable: 1.0.0`, `Upload-Length`,
`Upload-Metadata`. Metadata keys: `bookUuid`, `filename`, `filetype`,
`relativePath`; optional `collection`. `PATCH` headers: `Tus-Resumable: 1.0.0`,
`Upload-Offset: 0`, `Content-Type: application/offset+octet-stream`.

## Diagnosis and recovery

```bash
scripts/diagnose_alignment_error.sh <book_uuid> \
  --compose-dir /path/to/storyteller
```

Options: `--logs-lines N`, `--compose-dir PATH`, `--container NAME`.

A live `401 Unauthorized` or `Not authenticated` proves the API is reachable
but auth is stale or invalid; connection errors and timeouts are network
failures. During `TRANSCRIBE_CHAPTERS`, advancing `Transcribing audio file ...`
logs indicate active work. `ENOENT` for `/transcriptions/*.json` usually means
path drift after metadata/path changes.

Do not edit a `PROCESSING` or `QUEUED` book. Recovery: cancel processing, edit
metadata, then restart with `POST /api/v2/books/{bookId}/process?restart=1`.
