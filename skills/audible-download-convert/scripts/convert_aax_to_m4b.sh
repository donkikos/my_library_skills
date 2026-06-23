#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
BASE_DIR="${BASE_DIR:-$REPO_ROOT/audible_data}"
SRC_DIR="${SRC_DIR:-$BASE_DIR/aax_orig}"
TARGET_DIR="${TARGET_DIR:-$BASE_DIR/aax_converted}"

usage() {
  cat <<'EOF'
Usage:
  convert_aax_to_m4b.sh [BOOK_DIR_OR_AAX ...]

Expected layout:
  aax_orig/<Book Folder>/<book>.aax
  aax_orig/<Book Folder>/<book>-chapters.json
  aax_orig/<Book Folder>/<book>_(1215).jpg

Behavior:
1. Converts to:
   aax_converted/<Book Folder>/<Book Folder>.m4b
2. Writes:
   aax_converted/<Book Folder>/<Book Folder>.chapters.txt
   aax_converted/<Book Folder>/<Book Folder>.jpg
3. Moves the full source folder to:
   aax_converted/<Book Folder>/ (source files moved directly here)

Notes:
- No dependency on mp4art/mp4chaps.
- Uses ffmpeg + ffprobe + jq only.
- No-clobber: skips when target folder already exists.

Env overrides:
  BASE_DIR, SRC_DIR, TARGET_DIR
EOF
}

log() {
  printf '%s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "ERROR Missing required command: $1"
    exit 1
  }
}

trim_metadata_value() {
  printf '%s' "$1" \
    | sed -E 's#\/##g; s/ \(Unabridged\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g'
}

abs_dir() {
  local p
  p="$1"
  (cd "$p" && pwd)
}

find_cover_sidecar() {
  local dir base
  dir="$1"
  base="$2"

  shopt -s nullglob
  local candidates=("$dir/${base}_"*.jpg)
  shopt -u nullglob

  if ((${#candidates[@]} == 0)); then
    return 1
  fi

  printf '%s\n' "${candidates[0]}"
}

build_chapters_txt() {
  local chapters_json out_file tmp_file
  chapters_json="$1"
  out_file="$2"
  tmp_file="$3"

  jq -r '
    def pad(n): tostring | if (n > length) then ((n - length) * "0") + . else . end;
    .content_metadata.chapter_info.chapters |
    reduce .[] as $c ([]; if $c.chapters? then . + [$c | del(.chapters)] + [$c.chapters] else . + [$c] end) |
    flatten |
    to_entries |
    .[] |
    "CHAPTER\((.key))=\((((((.value.start_offset_ms / (1000*60*60)) /24 | floor)  *24 ) + ((.value.start_offset_ms / (1000*60*60)) %24 | floor)) | pad(2))):\(((.value.start_offset_ms / (1000*60)) %60 | floor | pad(2))):\(((.value.start_offset_ms / 1000) %60 | floor | pad(2))).\((.value.start_offset_ms % 1000 | pad(3)))
CHAPTER\((.key))NAME=\(.value.title)"' \
    "$chapters_json" >"$tmp_file"

  sed 's/,000/.000/g' "$tmp_file" >"$out_file"
}

build_ffmetadata_chapters() {
  local chapters_json out_file
  chapters_json="$1"
  out_file="$2"

  {
    printf ';FFMETADATA1\n'
    jq -r '
      .content_metadata.chapter_info.chapters |
      reduce .[] as $c ([]; if $c.chapters? then . + [$c | del(.chapters)] + [$c.chapters] else . + [$c] end) |
      flatten |
      .[] |
      "[CHAPTER]\nTIMEBASE=1/1000\nSTART=\(.start_offset_ms)\nEND=\(.start_offset_ms + .length_ms)\ntitle=\(.title|split("\n")|join(" "))\n"' \
      "$chapters_json"
  } >"$out_file"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd ffmpeg
require_cmd ffprobe
require_cmd jq

if [[ ! -d "$SRC_DIR" || ! -r "$SRC_DIR" ]]; then
  log "ERROR Source directory not readable: $SRC_DIR"
  exit 1
fi
if [[ ! -d "$TARGET_DIR" || ! -w "$TARGET_DIR" ]]; then
  log "ERROR Target directory missing or not writable: $TARGET_DIR"
  exit 1
fi

AUTH_CODE=""
if [[ -n "${AUDIBLE_AUTHCODE_FILE:-}" ]]; then
  if [[ ! -r "$AUDIBLE_AUTHCODE_FILE" ]]; then
    log "ERROR Authcode file not readable: $AUDIBLE_AUTHCODE_FILE"
    exit 1
  fi
  AUTH_CODE="$(head -n1 "$AUDIBLE_AUTHCODE_FILE" | tr -d '[:space:]')"
elif [[ -r ".authcode" ]]; then
  AUTH_CODE="$(head -n1 .authcode | tr -d '[:space:]')"
elif [[ -r "$HOME/.authcode" ]]; then
  AUTH_CODE="$(head -n1 "$HOME/.authcode" | tr -d '[:space:]')"
fi

if [[ -z "$AUTH_CODE" ]]; then
  log "ERROR Missing authcode. Provide .authcode in cwd or ~/.authcode."
  exit 1
fi

SRC_DIR_ABS="$(abs_dir "$SRC_DIR")"
TARGET_DIR_ABS="$(abs_dir "$TARGET_DIR")"

declare -a SOURCE_DIRS
if (($# > 0)); then
  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      SOURCE_DIRS+=("$(abs_dir "$arg")")
    elif [[ -f "$arg" && "${arg##*.}" == "aax" ]]; then
      SOURCE_DIRS+=("$(abs_dir "$(dirname "$arg")")")
    else
      log "ERROR Argument must be a book folder or .aax file: $arg"
      exit 1
    fi
  done
else
  while IFS= read -r d; do
    SOURCE_DIRS+=("$d")
  done < <(find "$SRC_DIR_ABS" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if ((${#SOURCE_DIRS[@]} == 0)); then
  log "No source folders found under: $SRC_DIR_ABS"
  exit 0
fi

declare -a UNIQUE_SOURCE_DIRS
for d in "${SOURCE_DIRS[@]}"; do
  already_added=0
  for u in "${UNIQUE_SOURCE_DIRS[@]:-}"; do
    if [[ "$u" == "$d" ]]; then
      already_added=1
      break
    fi
  done
  if [[ "$already_added" -eq 0 ]]; then
    UNIQUE_SOURCE_DIRS+=("$d")
  fi
done

for source_dir in "${UNIQUE_SOURCE_DIRS[@]}"; do
  if [[ ! -d "$source_dir" ]]; then
    log "WARN Source folder disappeared, skipping: $source_dir"
    continue
  fi

  if [[ "$(dirname "$source_dir")" != "$SRC_DIR_ABS" ]]; then
    log "ERROR Source folder must be directly under $SRC_DIR_ABS: $source_dir"
    exit 1
  fi

  aax_files=()
  while IFS= read -r f; do
    aax_files+=("$f")
  done < <(find "$source_dir" -maxdepth 1 -type f -name '*.aax' | sort)
  if ((${#aax_files[@]} == 0)); then
    log "WARN No .aax file in $source_dir, skipping."
    continue
  fi
  if ((${#aax_files[@]} > 1)); then
    log "ERROR More than one .aax in $source_dir; keep one title per folder."
    exit 1
  fi

  aax_file="${aax_files[0]}"
  source_folder_name="$(basename "$source_dir")"

  base_name="$(basename "$aax_file" .aax)"
  sidecar_prefix="${base_name%-*}"
  chapter_json="$source_dir/${sidecar_prefix}-chapters.json"
  cover_sidecar="$(find_cover_sidecar "$source_dir" "$sidecar_prefix")" || {
    log "ERROR Cover sidecar not found in $source_dir for $aax_file"
    exit 1
  }

  if [[ ! -r "$chapter_json" ]]; then
    log "ERROR Chapter sidecar not found: $chapter_json"
    exit 1
  fi

  meta_json="$(ffprobe -v error -activation_bytes "$AUTH_CODE" -print_format json -show_entries format=bit_rate:format_tags "$aax_file")"

  raw_artist="$(jq -r '.format.tags.artist // ""' <<<"$meta_json")"
  raw_album_artist="$(jq -r '.format.tags.album_artist // ""' <<<"$meta_json")"
  raw_title="$(jq -r '.format.tags.title // ""' <<<"$meta_json")"
  raw_album="$(jq -r '.format.tags.album // ""' <<<"$meta_json")"
  raw_date="$(jq -r '.format.tags.date // ""' <<<"$meta_json")"
  raw_genre="$(jq -r '.format.tags.genre // ""' <<<"$meta_json")"
  raw_copyright="$(jq -r '.format.tags.copyright // ""' <<<"$meta_json")"

  artist="$(trim_metadata_value "$raw_artist")"
  album_artist="$(trim_metadata_value "$raw_album_artist")"
  title="$(trim_metadata_value "$raw_title")"
  album="$(trim_metadata_value "$raw_album")"
  album_date="$(trim_metadata_value "$raw_date")"
  genre="$(trim_metadata_value "$raw_genre")"
  copyright="$(trim_metadata_value "$raw_copyright")"

  if [[ -z "$artist" || -z "$title" ]]; then
    log "ERROR Could not read artist/title metadata from $aax_file"
    exit 1
  fi
  title="${title:0:128}"

  expected_folder_name="${artist} - ${title}"
  if [[ "$source_folder_name" != "$expected_folder_name" ]]; then
    log "WARN Folder '$source_folder_name' differs from metadata name '$expected_folder_name'; using folder name."
  fi

  bitrate_bps="$(jq -r '.format.bit_rate // 64000' <<<"$meta_json")"
  if [[ "$bitrate_bps" =~ ^[0-9]+$ ]] && (( bitrate_bps > 0 )); then
    bitrate_k="$((bitrate_bps / 1000))k"
  else
    bitrate_k="64k"
  fi

  narrator=""
  description=""
  publisher=""
  if command -v mediainfo >/dev/null 2>&1; then
    description="$(trim_metadata_value "$(mediainfo --Inform='General;%Track_More%' "$aax_file" || true)")"
    narrator="$(trim_metadata_value "$(mediainfo --Inform='General;%nrt%' "$aax_file" || true)")"
    publisher="$(trim_metadata_value "$(mediainfo --Inform='General;%pub%' "$aax_file" || true)")"
  fi

  output_directory="$TARGET_DIR_ABS/$source_folder_name"
  output_file="$output_directory/$source_folder_name.m4b"
  cover_file="$output_directory/$source_folder_name.jpg"
  chapters_txt="$output_directory/$source_folder_name.chapters.txt"

  if [[ -d "$output_directory" ]]; then
    log "Noclobber enabled but directory '$output_directory' exists. Skipping."
    continue
  fi
  mkdir -p "$output_directory"

  log "Converting: $aax_file"
  ffmpeg -loglevel error -stats \
    -activation_bytes "$AUTH_CODE" \
    -i "$aax_file" \
    -vn \
    -codec:a copy \
    -ab "$bitrate_k" \
    -map_metadata -1 \
    -metadata title="$title" \
    -metadata artist="$artist" \
    -metadata album_artist="$album_artist" \
    -metadata album="$album" \
    -metadata date="$album_date" \
    -metadata track="1/1" \
    -metadata genre="$genre" \
    -metadata copyright="$copyright" \
    -metadata description="$description" \
    -metadata composer="$narrator" \
    -metadata publisher="$publisher" \
    -metadata series="" \
    -metadata series_sequence="" \
    -f mp4 \
    "$output_file"

  cp "$cover_sidecar" "$cover_file"

  tmp_chapters="$(mktemp)"
  build_chapters_txt "$chapter_json" "$chapters_txt" "$tmp_chapters"
  rm -f "$tmp_chapters"

  tmp_ffmeta="$(mktemp)"
  build_ffmetadata_chapters "$chapter_json" "$tmp_ffmeta"
  tmp_output="${output_file%.m4b}.tmp.m4b"

  ffmpeg -loglevel error -y \
    -i "$output_file" \
    -i "$cover_file" \
    -i "$tmp_ffmeta" \
    -map 0:a \
    -map 1:v \
    -map_metadata 0 \
    -map_chapters 2 \
    -c:a copy \
    -c:v mjpeg \
    -disposition:v attached_pic \
    -metadata:s:v title="Album cover" \
    -metadata:s:v comment="Cover (front)" \
    -f mp4 \
    "$tmp_output"

  mv "$tmp_output" "$output_file"
  rm -f "$tmp_ffmeta"

  # Move original source files into destination folder (no nested source folder).
  while IFS= read -r -d '' src_item; do
    src_name="$(basename "$src_item")"
    dst_item="$output_directory/$src_name"
    if [[ -e "$dst_item" ]]; then
      log "ERROR Destination already has '$dst_item'"
      exit 1
    fi
    mv "$src_item" "$output_directory/"
  done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)

  rmdir "$source_dir"

  log "Complete: $output_file"
done
