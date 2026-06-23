---
name: audible-download-convert
description: Download Audible titles into configured Audible data folders and convert them to M4B using the locked audible-cli environment and repository conversion workflow. Use when a user asks to fetch or download a title by ASIN and convert it.
platforms: [linux, macos]
prerequisites:
  commands: [bash, uv, ffmpeg, ffprobe, jq]
---

# Audible Download Convert

## Overview

Use the helper script to download an Audible title into a book-specific
`aax_orig` folder, convert it to `.m4b` with embedded cover and chapters, and
verify the outputs.

## Runtime Configuration

Resolve the repository default from the repository root:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"
```

Honor these host-configurable paths:

| Variable | Default | Role |
| --- | --- | --- |
| `AUDIBLE_DATA_DIR` | `<repository>/audible_data` | Root containing `aax_orig` and `aax_converted`. |
| `AUDIBLE_VENV_DIR` | `${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv` | uv project environment used by the helper. |
| `AUDIBLE_CONFIG_DIR` | `${XDG_CONFIG_HOME:-$HOME/.config}/audible` | Location for persistent Audible profiles and authentication configuration. |
| `AUDIBLE_AUTHCODE_FILE` | `$AUDIBLE_CONFIG_DIR/.authcode` | Activation-bytes file; fail if the configured file is unreadable. |

Do not assume a container path. Preserve existing environment values or ask the
user where persistent data, configuration, and credentials should live.

Example host configuration:

```bash
export AUDIBLE_DATA_DIR="$HOME/Audiobooks/audible"
export AUDIBLE_VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv"
export AUDIBLE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/audible"
export AUDIBLE_AUTHCODE_FILE="$AUDIBLE_CONFIG_DIR/.authcode"
mkdir -p \
  "$AUDIBLE_DATA_DIR/aax_orig" \
  "$AUDIBLE_DATA_DIR/aax_converted" \
  "$AUDIBLE_CONFIG_DIR"
```

## Frozen Environment

The skill-local project requires Python 3.13 and locks `audible-cli` with
`uv.lock`. From the repository root, initialize or refresh the configured
environment without changing the lock:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/skills/audible-download-convert"
AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"
AUDIBLE_VENV_DIR="${AUDIBLE_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv}"
uv python install 3.13
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv sync --project "$SKILL_DIR" --frozen --python 3.13
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible --help
```

Use the same configured paths for Audible authentication:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/skills/audible-download-convert"
AUDIBLE_VENV_DIR="${AUDIBLE_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv}"
AUDIBLE_CONFIG_DIR="${AUDIBLE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/audible}"
export AUDIBLE_CONFIG_DIR
AUDIBLE_AUTHCODE_FILE="${AUDIBLE_AUTHCODE_FILE:-$AUDIBLE_CONFIG_DIR/.authcode}"
mkdir -p "$(dirname "$AUDIBLE_AUTHCODE_FILE")"
umask 077
UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible quickstart

UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR" \
  uv run --project "$SKILL_DIR" --frozen audible activation-bytes \
  > "$AUDIBLE_AUTHCODE_FILE"
chmod 600 "$AUDIBLE_AUTHCODE_FILE"
```

## Core Workflow

1. Confirm the prerequisite commands and configured paths.
2. Choose a destination book folder name.
3. Run the helper for one ASIN or a TSV manifest.
4. Verify `<Book Folder>.m4b`, `<Book Folder>.jpg`, and
   `<Book Folder>.chapters.txt` under
   `$AUDIBLE_DATA_DIR/aax_converted/<Book Folder>`.

## Commands

Run the helper from the repository root.

Single title:

```bash
bash skills/audible-download-convert/scripts/download_and_convert.sh \
  --asin B07D9RHRH5 \
  --book-folder "Martha Wells - Rogue Protocol"
```

Select a configured Audible profile when needed:

```bash
bash skills/audible-download-convert/scripts/download_and_convert.sh \
  --asin B07D9RHRH5 \
  --book-folder "Martha Wells - Rogue Protocol" \
  --profile default
```

Bulk mode from manifest:

```bash
bash skills/audible-download-convert/scripts/download_and_convert.sh \
  --manifest /path/to/books.tsv \
  --dry-run
```

Manifest format:

```text
ASIN<TAB>Book Folder
# comments and blank lines are allowed
B07D9RHRH5	Martha Wells - Rogue Protocol
B07FF9TJ2K	Martha Wells - Exit Strategy
```

Audit format (`--audit-file`):

```text
timestamp_utc	asin	book_folder	status	output_file	size_bytes	sha256
```

Auditing is optional and requires `shasum` to calculate the successful output's
SHA256. Do not require `shasum` for normal download and conversion.

Use `--base-dir "$HOME/Audiobooks/audible"` for a one-command data-root
override.

## Guardrails

- Use one title per folder in `aax_orig`.
- The `aax_orig` folder name becomes the output folder name in
  `aax_converted`.
- ASIN input is normalized to uppercase and must resolve to 10 alphanumeric
  characters.
- Keep `--frozen` on direct uv commands; do not replace the locked workflow
  with pip or an ad hoc virtual environment.
- The helper pre-checks idempotency: if the final `.m4b` exists, it skips the
  title.
- The helper stops if the destination folder exists without the final `.m4b`.
- On download failure, a newly created empty source folder is removed.
- `--dry-run` validates inputs and prints planned actions without downloading
  or converting.
- `--audit-file` appends per-title results; success includes output size and
  SHA256.
- If Audible has no PDF for a title, continue with `.aax`, cover, and chapters.
- ffmpeg may print `Referenced QT chapter track not found`; it is non-fatal
  when the final outputs are present.
