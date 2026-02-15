---
name: storyteller
description: "Manage a local Storyteller server via API: authenticate with bearer tokens, list books, upload EPUB plus M4B with TUS, update title or series metadata, and queue or cancel alignment processing. Use when the user asks to add books, inspect library state, fix metadata, or run alignment in Storyteller."
---

# Storyteller

Use this skill to perform reliable Storyteller API operations on a local instance.

## Defaults

- Use API base URL `http://localhost:8001` unless the user specifies otherwise.
- Read auth token from `STORYTELLER_TOKEN` env var first.
- Fall back to token file `$HOME/.config/storyteller-skill/.storyteller_token` (or `STORYTELLER_TOKEN_FILE`).
- Keep token files out of git and permissioned to owner only (`chmod 600`).

## Token setup

Use the bundled script to avoid typing passwords in shell commands.

1. Copy the Storyteller password to clipboard.
2. Run:

```bash
scripts/get_token_from_clipboard.sh --username-or-email agent_user --clear-clipboard
```

This reads password from `pbpaste`, calls `POST /api/v2/token`, and stores `access_token` to `$HOME/.config/storyteller-skill/.storyteller_token`.

## Use scripts

Run bundled scripts for deterministic behavior:

- `scripts/get_token_from_clipboard.sh`
- `scripts/list_books.sh`
- `scripts/upload_epub_m4b.sh`
- `scripts/update_title_series.sh`
- `scripts/queue_alignment.sh`
- `scripts/diagnose_alignment_error.sh`

## Core workflow

1. Verify API health with `GET /api/health`.
2. List books and find target UUIDs.
3. Upload EPUB and M4B as one book with a shared `bookUuid` through TUS (`/api/v2/books/upload`).
4. Fix metadata (title, series name, series position) when needed.
5. Queue alignment with `POST /api/v2/books/{bookId}/process`.
6. Monitor status through `GET /api/v2/books/{bookId}` or SSE `GET /api/v2/books/events` with `Accept: text/event-stream`.

## Failure diagnosis

- Use `scripts/diagnose_alignment_error.sh <book_uuid>` to correlate API status with recent worker logs.
- If stage is `TRANSCRIBE_CHAPTERS` and logs keep advancing `Transcribing audio file ...`, treat it as active processing, not a failure.

## Safety rules

- Do not edit title or series while readaloud status is `PROCESSING` or `QUEUED`.
- If metadata must change for a processing book, cancel alignment first (`DELETE /api/v2/books/{bookId}/process`), apply metadata update, then restart with `POST /api/v2/books/{bookId}/process?restart=1`.
- Treat `ENOENT` errors under `/transcriptions/*.json` during transcription as likely path drift after metadata/path changes; recover with restart queueing.

## Notes from validated behavior

- Token endpoint: `POST /api/v2/token` with form fields `usernameOrEmail` and `password`.
- Auth response contains `access_token`, `expires_in`, `token_type`.
- Protected endpoints accept `Authorization: Bearer <token>`.
- TUS upload metadata must include at least `bookUuid` and `filename`; in practice include `filetype` and `relativePath`.
- Queue alignment endpoint supports `?restart=1` to force a fresh run.
- `PUT /api/v2/books/{bookId}/status` and `PUT /api/v2/books/status` update reading status, not alignment processing.
- `/api/openapi` UI may be present while `/api/openapi/schema.json` is incomplete; prefer validated endpoint workflows from this skill.

## References

For raw endpoint map and curl examples, read `references/api-workflows.md`.
