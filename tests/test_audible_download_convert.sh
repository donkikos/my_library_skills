#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_SCRIPT="$REPO_ROOT/skills/audible-download-convert/scripts/download_and_convert.sh"
SKILL_DIR="$REPO_ROOT/skills/audible-download-convert"
CONVERT_SCRIPT="$SKILL_DIR/scripts/convert_aax_to_m4b.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F -- "$expected" "$file" >/dev/null || fail "missing '$expected' in $file"
}

# Direct converter use must keep the repository-level audible_data default after
# the script is relocated under the skill.
assert_contains "$CONVERT_SCRIPT" 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
assert_contains "$CONVERT_SCRIPT" 'SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"'
assert_contains "$CONVERT_SCRIPT" 'REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"'
assert_contains "$CONVERT_SCRIPT" 'BASE_DIR="${BASE_DIR:-$REPO_ROOT/audible_data}"'

FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/uv" <<'EOF'
#!/bin/bash
{
  printf 'UV_PROJECT_ENVIRONMENT=%s\n' "${UV_PROJECT_ENVIRONMENT:-}"
  printf 'AUDIBLE_CONFIG_DIR=%s\n' "${AUDIBLE_CONFIG_DIR:-}"
  printf 'ARG=%s\n' "$@"
} >"$UV_LOG"
if [[ "${UV_MODE:-fail}" == "success" ]]; then
  while (($#)); do
    if [[ "$1" == "--output-dir" ]]; then
      output_dir="$2"
      mkdir -p "$output_dir"
      touch \
        "$output_dir/book.aax" \
        "$output_dir/book-chapters.json" \
        "$output_dir/book_(1215).jpg"
      exit 0
    fi
    shift
  done
fi
exit 23
EOF
chmod +x "$FAKE_BIN/uv"

DATA_DIR="$TMP_DIR/data"
if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Test Book" --dry-run \
  >"$TMP_DIR/dry-run.out" 2>&1; then
  cat "$TMP_DIR/dry-run.out" >&2
  fail "dry-run failed"
fi
assert_contains "$TMP_DIR/dry-run.out" "$DATA_DIR/aax_orig/Test Book"
assert_contains "$TMP_DIR/dry-run.out" "$DATA_DIR/aax_converted/Test Book/Test Book.m4b"

UV_LOG="$TMP_DIR/uv.log"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  UV_LOG="$UV_LOG" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  AUDIBLE_VENV_DIR="$TMP_DIR/venv" \
  AUDIBLE_CONFIG_DIR="$TMP_DIR/config" \
  "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Runtime Book" --profile portable \
  >"$TMP_DIR/download.out" 2>&1; then
  fail "download unexpectedly succeeded"
fi

cat >"$TMP_DIR/expected-uv.log" <<EOF
UV_PROJECT_ENVIRONMENT=$TMP_DIR/venv
AUDIBLE_CONFIG_DIR=$TMP_DIR/config
ARG=run
ARG=--project
ARG=$SKILL_DIR
ARG=--frozen
ARG=audible
ARG=-P
ARG=portable
ARG=download
ARG=--output-dir
ARG=$DATA_DIR/aax_orig/Runtime Book
ARG=--asin
ARG=B07D9RHRH5
ARG=--aax
ARG=--pdf
ARG=--cover
ARG=--cover-size
ARG=1215
ARG=--chapter
ARG=-y
EOF
cmp "$TMP_DIR/expected-uv.log" "$UV_LOG" || fail "unexpected uv invocation"

cat >"$FAKE_BIN/bash" <<'EOF'
#!/bin/sh
printf 'BASE_DIR=%s\n' "${BASE_DIR:-}" >"$CONVERTER_LOG"
printf 'AUDIBLE_AUTHCODE_FILE=%s\n' "${AUDIBLE_AUTHCODE_FILE:-}" >>"$CONVERTER_LOG"
printf 'ARG=%s\n' "$@" >>"$CONVERTER_LOG"
book_dir="$2"
data_dir="$(dirname "$(dirname "$book_dir")")"
book_folder="$(basename "$book_dir")"
out_dir="$data_dir/aax_converted/$book_folder"
mkdir -p "$out_dir"
touch \
  "$out_dir/$book_folder.m4b" \
  "$out_dir/$book_folder.jpg" \
  "$out_dir/$book_folder.chapters.txt"
EOF
chmod +x "$FAKE_BIN/bash"

CONVERTER_LOG="$TMP_DIR/converter.log"
AUTHCODE_FILE="$TMP_DIR/explicit.authcode"
touch "$AUTHCODE_FILE"
if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  UV_LOG="$TMP_DIR/success-uv.log" \
  UV_MODE=success \
  CONVERTER_LOG="$CONVERTER_LOG" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  AUDIBLE_AUTHCODE_FILE="$AUTHCODE_FILE" \
  /bin/bash "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Converted Book" \
  >"$TMP_DIR/success.out" 2>&1; then
  cat "$TMP_DIR/success.out" >&2
  fail "successful fake download and conversion failed"
fi
cat >"$TMP_DIR/expected-converter.log" <<EOF
BASE_DIR=$DATA_DIR
AUDIBLE_AUTHCODE_FILE=$AUTHCODE_FILE
ARG=$CONVERT_SCRIPT
ARG=$DATA_DIR/aax_orig/Converted Book
EOF
cmp "$TMP_DIR/expected-converter.log" "$CONVERTER_LOG" ||
  fail "configured data root did not reach converter"

for command_name in ffmpeg ffprobe jq; do
  cat >"$FAKE_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/$command_name"
done
mkdir -p "$TMP_DIR/source" "$TMP_DIR/target" "$TMP_DIR/home"
AUTHCODE_FILE="$TMP_DIR/missing.authcode"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  HOME="$TMP_DIR/home" \
  SRC_DIR="$TMP_DIR/source" \
  TARGET_DIR="$TMP_DIR/target" \
  AUDIBLE_AUTHCODE_FILE="$AUTHCODE_FILE" \
  /bin/bash "$CONVERT_SCRIPT" >"$TMP_DIR/convert.out" 2>&1; then
  fail "converter unexpectedly accepted an unreadable explicit authcode file"
fi
assert_contains "$TMP_DIR/convert.out" "ERROR Authcode file not readable: $AUTHCODE_FILE"

echo "PASS"
