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

assert_invalid_book_folder() {
  local label="$1"
  local folder="$2"
  local output="$TMP_DIR/invalid-$label.out"

  if PATH="$FAKE_BIN:/usr/bin:/bin" \
    AUDIBLE_DATA_DIR="$DATA_DIR" \
    "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "$folder" --dry-run \
    >"$output" 2>&1; then
    fail "unsafe book folder unexpectedly accepted: $label"
  fi
  assert_contains "$output" "Invalid book folder"
}

assert_invalid_book_folder "parent" "../outside"
[[ ! -e "$TMP_DIR/outside" ]] ||
  fail "parent traversal created a path outside AUDIBLE_DATA_DIR"
assert_invalid_book_folder "absolute" "$TMP_DIR/outside"
assert_invalid_book_folder "slash" "Author/Book"
assert_invalid_book_folder "backslash" 'Author\Book'
assert_invalid_book_folder "dot" "."
assert_invalid_book_folder "dot-dot" ".."
assert_invalid_book_folder "newline" $'Author\nBook'
assert_invalid_book_folder "tab" $'Author\tBook'

CONTROL_NAMES=("newline" "tab" "carriage-return" "vertical-tab" "form-feed")
CONTROL_VALUES=($'\n' $'\t' $'\r' $'\v' $'\f')
for control_index in "${!CONTROL_NAMES[@]}"; do
  control_name="${CONTROL_NAMES[$control_index]}"
  control_value="${CONTROL_VALUES[$control_index]}"
  assert_invalid_book_folder "leading-$control_name" "${control_value}Author"
  assert_invalid_book_folder "trailing-$control_name" "Author${control_value}"
done

MANIFEST="$TMP_DIR/unsafe.tsv"
printf 'B07D9RHRH5\t../manifest-outside\n' >"$MANIFEST"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  "$DOWNLOAD_SCRIPT" --manifest "$MANIFEST" --dry-run \
  >"$TMP_DIR/invalid-manifest.out" 2>&1; then
  fail "unsafe manifest book folder unexpectedly accepted"
fi
assert_contains "$TMP_DIR/invalid-manifest.out" "Invalid book folder"
assert_contains "$TMP_DIR/invalid-manifest.out" "Aborting on manifest line 1."

VALID_FOLDER="Léon O'Brien - Vol. 2"
if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "$VALID_FOLDER" --dry-run \
  >"$TMP_DIR/valid-folder.out" 2>&1; then
  cat "$TMP_DIR/valid-folder.out" >&2
  fail "valid Unicode book folder was rejected"
fi
assert_contains "$TMP_DIR/valid-folder.out" "$DATA_DIR/aax_orig/$VALID_FOLDER"

if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Test Book" --dry-run \
  >"$TMP_DIR/dry-run.out" 2>&1; then
  cat "$TMP_DIR/dry-run.out" >&2
  fail "dry-run failed"
fi
assert_contains "$TMP_DIR/dry-run.out" "$DATA_DIR/aax_orig/Test Book"
assert_contains "$TMP_DIR/dry-run.out" "$DATA_DIR/aax_converted/Test Book/Test Book.m4b"

SYMLINK_DATA_DIR="$TMP_DIR/symlink-data"
EXTERNAL_BOOK_DIR="$TMP_DIR/external-book"
mkdir -p "$SYMLINK_DATA_DIR/aax_orig" "$SYMLINK_DATA_DIR/aax_converted" "$EXTERNAL_BOOK_DIR"
printf 'unchanged\n' >"$EXTERNAL_BOOK_DIR/sentinel"
ln -s "$EXTERNAL_BOOK_DIR" "$SYMLINK_DATA_DIR/aax_orig/Symlink Book"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  UV_LOG="$TMP_DIR/symlink-uv.log" \
  UV_MODE=success \
  AUDIBLE_DATA_DIR="$SYMLINK_DATA_DIR" \
  "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Symlink Book" \
  >"$TMP_DIR/symlink-download.out" 2>&1; then
  fail "download helper unexpectedly accepted a symlink book directory"
fi
assert_contains "$TMP_DIR/symlink-download.out" "unsafe symlink/path boundary"
[[ ! -e "$TMP_DIR/symlink-uv.log" ]] ||
  fail "download helper invoked uv before rejecting a symlink book directory"
[[ "$(cat "$EXTERNAL_BOOK_DIR/sentinel")" == "unchanged" ]] ||
  fail "download helper changed the external sentinel"
[[ "$(find "$EXTERNAL_BOOK_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')" == "1" ]] ||
  fail "download helper altered the external directory"

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

DEFAULT_CONFIG_DIR="$TMP_DIR/default-config"
if ! /usr/bin/env -u AUDIBLE_AUTHCODE_FILE \
  PATH="$FAKE_BIN:/usr/bin:/bin" \
  UV_LOG="$TMP_DIR/default-success-uv.log" \
  UV_MODE=success \
  CONVERTER_LOG="$CONVERTER_LOG" \
  AUDIBLE_DATA_DIR="$DATA_DIR" \
  AUDIBLE_CONFIG_DIR="$DEFAULT_CONFIG_DIR" \
  /bin/bash "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Default Authcode Book" \
  >"$TMP_DIR/default-success.out" 2>&1; then
  cat "$TMP_DIR/default-success.out" >&2
  fail "fake conversion with default authcode path failed"
fi
cat >"$TMP_DIR/expected-default-converter.log" <<EOF
BASE_DIR=$DATA_DIR
AUDIBLE_AUTHCODE_FILE=$DEFAULT_CONFIG_DIR/.authcode
ARG=$CONVERT_SCRIPT
ARG=$DATA_DIR/aax_orig/Default Authcode Book
EOF
cmp "$TMP_DIR/expected-default-converter.log" "$CONVERTER_LOG" ||
  fail "default authcode path did not reach converter"

ROOT_LINK_REAL="$TMP_DIR/root-link-real"
ROOT_LINK="$TMP_DIR/root-link"
mkdir -p "$ROOT_LINK_REAL/aax_orig" "$ROOT_LINK_REAL/aax_converted"
ln -s "$ROOT_LINK_REAL" "$ROOT_LINK"
if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  UV_LOG="$TMP_DIR/root-link-uv.log" \
  UV_MODE=success \
  CONVERTER_LOG="$TMP_DIR/root-link-converter.log" \
  AUDIBLE_DATA_DIR="$ROOT_LINK" \
  AUDIBLE_AUTHCODE_FILE="$AUTHCODE_FILE" \
  /bin/bash "$DOWNLOAD_SCRIPT" --asin B07D9RHRH5 --book-folder "Root Link Book" \
  >"$TMP_DIR/root-link-download.out" 2>&1; then
  cat "$TMP_DIR/root-link-download.out" >&2
  fail "download helper rejected a configured data-root symlink"
fi
[[ -f "$ROOT_LINK_REAL/aax_converted/Root Link Book/Root Link Book.m4b" ]] ||
  fail "download helper did not preserve configured data-root symlink support"

for command_name in ffmpeg ffprobe jq; do
  cat >"$FAKE_BIN/$command_name" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$FAKE_BIN/$command_name"
done

CONVERTER_SOURCE="$TMP_DIR/converter-source"
CONVERTER_TARGET="$TMP_DIR/converter-target"
CONVERTER_EXTERNAL="$TMP_DIR/converter-external"
mkdir -p "$CONVERTER_SOURCE" "$CONVERTER_TARGET" "$CONVERTER_EXTERNAL"
touch \
  "$CONVERTER_EXTERNAL/book.aax" \
  "$CONVERTER_EXTERNAL/book-chapters.json" \
  "$CONVERTER_EXTERNAL/book_(1215).jpg"
printf 'unchanged\n' >"$CONVERTER_EXTERNAL/sentinel"
ln -s "$CONVERTER_EXTERNAL" "$CONVERTER_SOURCE/Symlink Book"
printf '12345678\n' >"$TMP_DIR/converter.authcode"
cat >"$FAKE_BIN/ffprobe" <<'EOF'
#!/bin/bash
printf 'called\n' >"$FFPROBE_LOG"
exit 0
EOF
chmod +x "$FAKE_BIN/ffprobe"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  HOME="$TMP_DIR/home" \
  SRC_DIR="$CONVERTER_SOURCE" \
  TARGET_DIR="$CONVERTER_TARGET" \
  AUDIBLE_AUTHCODE_FILE="$TMP_DIR/converter.authcode" \
  FFPROBE_LOG="$TMP_DIR/ffprobe.log" \
  /bin/bash "$CONVERT_SCRIPT" "$CONVERTER_SOURCE/Symlink Book" \
  >"$TMP_DIR/converter-symlink.out" 2>&1; then
  fail "converter unexpectedly accepted a symlink source argument"
fi
assert_contains "$TMP_DIR/converter-symlink.out" "unsafe symlink/path boundary"
[[ ! -e "$TMP_DIR/ffprobe.log" ]] ||
  fail "converter invoked ffprobe before rejecting a symlink source argument"
[[ "$(cat "$CONVERTER_EXTERNAL/sentinel")" == "unchanged" ]] ||
  fail "converter changed the external sentinel"
[[ "$(find "$CONVERTER_EXTERNAL" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')" == "4" ]] ||
  fail "converter altered the external directory"

TARGET_LINK_SOURCE="$TMP_DIR/target-link-source"
TARGET_LINK_ROOT="$TMP_DIR/target-link-root"
TARGET_LINK_EXTERNAL="$TMP_DIR/target-link-external"
TARGET_LINK_BOOK="Author - Title"
mkdir -p \
  "$TARGET_LINK_SOURCE/$TARGET_LINK_BOOK" \
  "$TARGET_LINK_ROOT" \
  "$TARGET_LINK_EXTERNAL"
touch \
  "$TARGET_LINK_SOURCE/$TARGET_LINK_BOOK/book.aax" \
  "$TARGET_LINK_SOURCE/$TARGET_LINK_BOOK/book-chapters.json" \
  "$TARGET_LINK_SOURCE/$TARGET_LINK_BOOK/book_(1215).jpg"
printf 'unchanged\n' >"$TARGET_LINK_EXTERNAL/sentinel"
ln -s "$TARGET_LINK_EXTERNAL" "$TARGET_LINK_ROOT/$TARGET_LINK_BOOK"
cat >"$FAKE_BIN/ffprobe" <<'EOF'
#!/bin/bash
printf '{}\n'
EOF
cat >"$FAKE_BIN/jq" <<'EOF'
#!/bin/bash
case "$2" in
  *'.format.tags.artist'*) printf 'Author\n' ;;
  *'.format.tags.album_artist'*) printf 'Author\n' ;;
  *'.format.tags.title'*) printf 'Title\n' ;;
  *'.format.tags.album'*) printf 'Title\n' ;;
  *'.format.bit_rate'*) printf '64000\n' ;;
  *) printf '\n' ;;
esac
EOF
cat >"$FAKE_BIN/ffmpeg" <<'EOF'
#!/bin/bash
printf 'called\n' >"$FFMPEG_LOG"
exit 0
EOF
chmod +x "$FAKE_BIN/ffprobe" "$FAKE_BIN/jq" "$FAKE_BIN/ffmpeg"
if PATH="$FAKE_BIN:/usr/bin:/bin" \
  HOME="$TMP_DIR/home" \
  SRC_DIR="$TARGET_LINK_SOURCE" \
  TARGET_DIR="$TARGET_LINK_ROOT" \
  AUDIBLE_AUTHCODE_FILE="$TMP_DIR/converter.authcode" \
  FFMPEG_LOG="$TMP_DIR/ffmpeg.log" \
  /bin/bash "$CONVERT_SCRIPT" "$TARGET_LINK_SOURCE/$TARGET_LINK_BOOK" \
  >"$TMP_DIR/converter-target-symlink.out" 2>&1; then
  fail "converter unexpectedly accepted a symlink target directory"
fi
assert_contains "$TMP_DIR/converter-target-symlink.out" "unsafe symlink/path boundary"
[[ ! -e "$TMP_DIR/ffmpeg.log" ]] ||
  fail "converter invoked ffmpeg before rejecting a symlink target"
[[ "$(cat "$TARGET_LINK_EXTERNAL/sentinel")" == "unchanged" ]] ||
  fail "converter changed the target-side external sentinel"
[[ "$(find "$TARGET_LINK_EXTERNAL" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')" == "1" ]] ||
  fail "converter altered the target-side external directory"

CONVERTER_ROOT_REAL="$TMP_DIR/converter-root-real"
CONVERTER_SOURCE_LINK="$TMP_DIR/converter-source-link"
CONVERTER_TARGET_LINK="$TMP_DIR/converter-target-link"
mkdir -p \
  "$CONVERTER_ROOT_REAL/aax_orig/Normal Book" \
  "$CONVERTER_ROOT_REAL/aax_converted"
ln -s "$CONVERTER_ROOT_REAL/aax_orig" "$CONVERTER_SOURCE_LINK"
ln -s "$CONVERTER_ROOT_REAL/aax_converted" "$CONVERTER_TARGET_LINK"
if ! PATH="$FAKE_BIN:/usr/bin:/bin" \
  HOME="$TMP_DIR/home" \
  SRC_DIR="$CONVERTER_SOURCE_LINK" \
  TARGET_DIR="$CONVERTER_TARGET_LINK" \
  AUDIBLE_AUTHCODE_FILE="$TMP_DIR/converter.authcode" \
  /bin/bash "$CONVERT_SCRIPT" "$CONVERTER_SOURCE_LINK/Normal Book" \
  >"$TMP_DIR/converter-root-link.out" 2>&1; then
  cat "$TMP_DIR/converter-root-link.out" >&2
  fail "converter rejected configured source/target root symlinks"
fi
assert_contains "$TMP_DIR/converter-root-link.out" "WARN No .aax file"

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
