# Storyteller API Workflows

## Auth

- `POST /api/v2/token`
- Content type: `application/x-www-form-urlencoded`
- Fields: `usernameOrEmail`, `password`
- Returns JSON: `access_token`, `expires_in`, `token_type`

### Clipboard-safe token bootstrap (macOS)

Copy password to clipboard, then run:

```bash
scripts/get_token_from_clipboard.sh --username-or-email agent_user --clear-clipboard
```

Equivalent raw form (without exposing password in CLI args):

```bash
pbpaste | curl -sS -X POST 'http://localhost:8001/api/v2/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'usernameOrEmail=agent_user' \
  --data-urlencode 'password@-' \
| jq -r '.access_token' > "$HOME/.config/storyteller-skill/.storyteller_token"
chmod 600 "$HOME/.config/storyteller-skill/.storyteller_token"
```

## Book listing

- `GET /api/v2/books`
- Requires bearer token.

## Uploading EPUB and M4B (TUS)

- Create upload: `POST /api/v2/books/upload`
  - Headers: `Tus-Resumable: 1.0.0`, `Upload-Length`, `Upload-Metadata`
  - Requires bearer token.
- Upload bytes: `PATCH <Location from POST>`
  - Headers: `Tus-Resumable: 1.0.0`, `Upload-Offset: 0`, `Content-Type: application/offset+octet-stream`
  - Body: file bytes

Recommended upload metadata keys:

- `bookUuid`
- `filename`
- `filetype`
- `relativePath`
- Optional: `collection`

## Update title and series

- `PUT /api/v2/books/{bookId}`
- Content type: `multipart/form-data`
- Include `fields=title`, `fields=series`
- `title` form value should be a JSON string (for example `"Abaddon's Gate"`)
- `series` form value should be JSON object with `uuid`, `name`, `featured`, `position`

## Queue or cancel alignment

- Queue: `POST /api/v2/books/{bookId}/process`
- Queue with restart: `POST /api/v2/books/{bookId}/process?restart=1`
- Cancel: `DELETE /api/v2/books/{bookId}/process`

## Status and events

- Per book: `GET /api/v2/books/{bookId}`
- SSE stream: `GET /api/v2/books/events` with `Accept: text/event-stream`

## Operational safety learnings

- Avoid metadata edits while readaloud status is `PROCESSING` or `QUEUED`.
- A real failure pattern is `ENOENT` for `/data/assets/<book>/transcriptions/<chunk>.json` during `TRANSCRIBE_CHAPTERS` when the book path changed mid-run.
- Recovery sequence:
  1. Cancel processing (`DELETE /api/v2/books/{bookId}/process`) if still active.
  2. Apply metadata corrections.
  3. Requeue with restart (`POST /api/v2/books/{bookId}/process?restart=1`).
