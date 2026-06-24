---
name: storyteller
description: Use when managing books, metadata, uploads, or alignment on a local Storyteller server.
platforms: [linux, macos]
prerequisites:
  commands: [bash, curl, jq, file, uuidgen]
---

# Storyteller

Use the bundled scripts for deterministic local API operations.

## Configuration and authentication

```bash
STORYTELLER_API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"
TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"
```

Authentication precedence:

1. `STORYTELLER_TOKEN`
2. Token file
3. `STORYTELLER_USERNAME_OR_EMAIL` plus `STORYTELLER_PASSWORD` when the token is missing or a protected request returns HTTP `401`

Credential refresh overwrites the configured token file and persists it securely: directory mode `700`, file mode `600`. Both credential variables are required.

## Scripts

- `scripts/get_token_from_clipboard.sh`
- `scripts/list_books.sh`
- `scripts/upload_epub_m4b.sh`
- `scripts/update_title_series.sh`
- `scripts/queue_alignment.sh`
- `scripts/diagnose_alignment_error.sh`

## Workflow

Use the scripts end-to-end: list/check existing books, upload paired EPUB+M4B with one UUID, update metadata only while idle, queue/cancel alignment, then monitor status/events. Do not edit while `PROCESSING` or `QUEUED`; cancel, edit, then restart if needed.

## EPUB3 / Readaloud from Existing EPUB + M4B

For “create EPUB3” from a matched ebook/audiobook pair, use Storyteller (not
Calibre conversion). Resolve EPUB and M4B paths, check for an existing matching
title, then use the scripts so auth refresh and TUS upload are handled:

```bash
scripts/upload_epub_m4b.sh "/path/book.epub" "/path/book.m4b"   # note BOOK_UUID
scripts/queue_alignment.sh "$BOOK_UUID"
scripts/list_books.sh --json | jq -r --arg id "$BOOK_UUID" \
  '.[]|select(.uuid==$id)|[.title,.ebook.isEpub2,.readaloud.status,.readaloud.currentStage,.readaloud.stageProgress,.readaloud.filepath]|@tsv'
```

`ALIGNED` means the EPUB3/readaloud file is ready at `readaloud.filepath`.
`TRANSCRIBE_CHAPTERS` can be long; `stageProgress` is fractional and may
fluctuate, so poll periodically or run a background monitor.

## Diagnosis

- A live `401 Unauthorized` or `Not authenticated` means the API is reachable but credentials are stale or invalid. Connection errors and timeouts indicate a network problem.
- During `TRANSCRIBE_CHAPTERS`, advancing `Transcribing audio file ...` logs indicate active processing.
- `ENOENT` for `/transcriptions/*.json` usually indicates transcription-path drift after metadata or path changes; use cancel-edit-restart recovery.

For endpoints, TUS details, commands, and recovery examples, read `references/api-workflows.md`.
