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

1. Check health, then list books and identify UUIDs.
2. Upload the EPUB and M4B together using one shared book UUID.
3. Correct title or series metadata.
4. Queue alignment.
5. Monitor the book status or event stream.

Do not edit metadata while alignment is `PROCESSING` or `QUEUED`. If an edit is required, cancel processing, edit metadata, then restart alignment.

## Diagnosis

- A live `401 Unauthorized` or `Not authenticated` means the API is reachable but credentials are stale or invalid. Connection errors and timeouts indicate a network problem.
- During `TRANSCRIBE_CHAPTERS`, advancing `Transcribing audio file ...` logs indicate active processing.
- `ENOENT` for `/transcriptions/*.json` usually indicates transcription-path drift after metadata or path changes; use cancel-edit-restart recovery.

For endpoints, TUS details, commands, and recovery examples, read `references/api-workflows.md`.
