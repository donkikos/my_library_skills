#!/usr/bin/env bash
set -euo pipefail

BASE_DIR=""
ASIN=""
BOOK_FOLDER=""
PROFILE=""
MANIFEST=""
DRY_RUN=0
AUDIT_FILE=""

usage() {
  cat <<'EOF'
Usage:
  Single title:
    download_and_convert.sh --asin <ASIN> --book-folder "<Book Folder>" [--profile <PROFILE>] [--base-dir <PATH>] [--dry-run] [--audit-file <FILE.tsv>]
  Bulk from manifest:
    download_and_convert.sh --manifest <FILE.tsv> [--profile <PROFILE>] [--base-dir <PATH>] [--dry-run] [--audit-file <FILE.tsv>]

Example:
  download_and_convert.sh \
    --asin B07D9RHRH5 \
    --book-folder "Martha Wells - Rogue Protocol"

Manifest format (TSV):
  ASIN<TAB>Book Folder
  # comments and blank lines are allowed

Audit file format (TSV):
  timestamp_utc<TAB>asin<TAB>book_folder<TAB>status<TAB>output_file<TAB>size_bytes<TAB>sha256
EOF
}

trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_valid_asin() {
  [[ "$1" =~ ^[A-Z0-9]{10}$ ]]
}

is_valid_book_folder() {
  local folder="$1"
  local LC_ALL=C

  [[ -n "$folder" ]] || return 1
  [[ "$folder" != "." && "$folder" != ".." ]] || return 1
  case "$folder" in
    */*|*\\*)
      return 1
      ;;
  esac
  [[ ! "$folder" =~ [[:cntrl:]] ]]
}

ensure_audit_header() {
  if [[ -z "$AUDIT_FILE" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$AUDIT_FILE")"
  if [[ ! -s "$AUDIT_FILE" ]]; then
    printf 'timestamp_utc\tasin\tbook_folder\tstatus\toutput_file\tsize_bytes\tsha256\n' > "$AUDIT_FILE"
  fi
}

audit_event() {
  local asin="$1"
  local folder="$2"
  local status="$3"
  local output_file="${4:-}"
  local size_bytes="${5:-}"
  local sha256="${6:-}"
  local timestamp_utc

  if [[ -z "$AUDIT_FILE" ]]; then
    return 0
  fi

  timestamp_utc="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$timestamp_utc" "$asin" "$folder" "$status" "$output_file" "$size_bytes" "$sha256" >> "$AUDIT_FILE"
}

cleanup_empty_dir() {
  local dir="$1"
  if [[ -d "$dir" ]] && [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    rmdir "$dir" 2>/dev/null || true
  fi
}

verify_outputs() {
  local out_dir="$1"
  local folder="$2"
  local m4b="$out_dir/$folder.m4b"
  local cover="$out_dir/$folder.jpg"
  local chapters="$out_dir/$folder.chapters.txt"
  local missing=0

  for f in "$m4b" "$cover" "$chapters"; do
    if [[ ! -f "$f" ]]; then
      echo "Missing expected output: $f" >&2
      missing=1
    fi
  done

  if ((missing)); then
    return 1
  fi
}

while (($#)); do
  case "$1" in
    --asin)
      ASIN="${2:-}"
      shift 2
      ;;
    --book-folder)
      BOOK_FOLDER="${2:-}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --audit-file)
      AUDIT_FILE="${2:-}"
      shift 2
      ;;
    --base-dir)
      BASE_DIR="${2:-}"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
if [[ -z "$BASE_DIR" ]]; then
  BASE_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"
fi

AUDIBLE_VENV_DIR="${AUDIBLE_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv}"
AUDIBLE_CONFIG_DIR="${AUDIBLE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/audible}"
AUDIBLE_AUTHCODE_FILE="${AUDIBLE_AUTHCODE_FILE:-$AUDIBLE_CONFIG_DIR/.authcode}"
export AUDIBLE_CONFIG_DIR AUDIBLE_AUTHCODE_FILE
export UV_PROJECT_ENVIRONMENT="$AUDIBLE_VENV_DIR"
CONVERT_CMD="$SCRIPT_DIR/convert_aax_to_m4b.sh"

if ! command -v uv >/dev/null 2>&1; then
  echo "Required command not found: uv" >&2
  exit 1
fi
if [[ ! -x "$CONVERT_CMD" ]]; then
  echo "Converter script not found or not executable: $CONVERT_CMD" >&2
  exit 1
fi

if [[ -n "$AUDIT_FILE" ]]; then
  ensure_audit_header
fi

process_one() {
  local asin folder book_dir out_dir out_file created_dir
  local -a download_cmd
  asin="$(trim_ws "$1")"
  folder="$(trim_ws "$2")"
  asin="$(printf '%s' "$asin" | tr '[:lower:]' '[:upper:]')"

  if [[ -z "$asin" || -z "$folder" ]]; then
    echo "ASIN and book folder must be non-empty." >&2
    return 1
  fi
  if ! is_valid_asin "$asin"; then
    echo "Invalid ASIN '$asin'. Expected 10 uppercase alphanumeric chars." >&2
    return 1
  fi
  if ! is_valid_book_folder "$folder"; then
    printf "Invalid book folder '%q'. Expected a single folder name without path separators, dot components, or control characters.\n" \
      "$folder" >&2
    return 1
  fi

  book_dir="$BASE_DIR/aax_orig/$folder"
  out_dir="$BASE_DIR/aax_converted/$folder"
  out_file="$out_dir/$folder.m4b"

  if [[ -f "$out_file" ]]; then
    echo "Skip: output already exists: $out_file"
    audit_event "$asin" "$folder" "SKIP_EXISTS" "$out_file"
    return 0
  fi
  if [[ -d "$out_dir" && ! -f "$out_file" ]]; then
    echo "Destination exists without final m4b: $out_dir" >&2
    echo "Resolve folder state before retrying this title." >&2
    audit_event "$asin" "$folder" "ERROR_PARTIAL_DEST" "$out_dir"
    return 1
  fi

  if ((DRY_RUN)); then
    echo "DRY-RUN: would download ASIN $asin into $book_dir"
    echo "DRY-RUN: would convert into $out_file"
    audit_event "$asin" "$folder" "DRY_RUN" "$out_file"
    return 0
  fi

  created_dir=0
  if [[ ! -d "$book_dir" ]]; then
    mkdir -p "$book_dir"
    created_dir=1
  fi

  download_cmd=(uv run --project "$SKILL_DIR" --frozen audible)
  if [[ -n "$PROFILE" ]]; then
    download_cmd+=("-P" "$PROFILE")
  fi
  download_cmd+=(
    download
    --output-dir "$book_dir"
    --asin "$asin"
    --aax
    --pdf
    --cover
    --cover-size 1215
    --chapter
    -y
  )

  echo "Downloading ASIN $asin into $book_dir"
  if ! "${download_cmd[@]}"; then
    echo "Download failed: $asin ($folder)" >&2
    if ((created_dir)); then
      cleanup_empty_dir "$book_dir"
    fi
    audit_event "$asin" "$folder" "ERROR_DOWNLOAD" "$book_dir"
    return 1
  fi

  echo "Converting $book_dir"
  if ! BASE_DIR="$BASE_DIR" bash "$CONVERT_CMD" "$book_dir"; then
    echo "Conversion failed: $folder" >&2
    audit_event "$asin" "$folder" "ERROR_CONVERT" "$book_dir"
    return 1
  fi

  if ! verify_outputs "$out_dir" "$folder"; then
    echo "Post-check failed: expected outputs missing for '$folder'." >&2
    audit_event "$asin" "$folder" "ERROR_VERIFY" "$out_file"
    return 1
  fi

  if [[ -n "$AUDIT_FILE" ]]; then
    local size_bytes sha256
    size_bytes="$(wc -c < "$out_file" | tr -d '[:space:]')"
    sha256="$(shasum -a 256 "$out_file" | awk '{print $1}')"
    audit_event "$asin" "$folder" "OK" "$out_file" "$size_bytes" "$sha256"
    echo "Audit: asin=$asin size_bytes=$size_bytes sha256=$sha256"
  fi

  echo "Done. Output verified in: $out_dir"
}

if [[ -n "$MANIFEST" ]]; then
  if [[ -n "$ASIN" || -n "$BOOK_FOLDER" ]]; then
    echo "Use either --manifest or --asin/--book-folder, not both." >&2
    exit 1
  fi
  if [[ ! -r "$MANIFEST" ]]; then
    echo "Manifest not found or not readable: $MANIFEST" >&2
    exit 1
  fi

  count=0
  line_no=0
  while IFS=$'\t' read -r manifest_asin manifest_folder extra || [[ -n "$manifest_asin$manifest_folder$extra" ]]; do
    line_no=$((line_no + 1))
    manifest_asin="${manifest_asin%$'\r'}"
    manifest_folder="${manifest_folder%$'\r'}"
    extra="${extra%$'\r'}"

    if [[ -z "$(trim_ws "$manifest_asin")" && -z "$(trim_ws "$manifest_folder")" ]]; then
      continue
    fi
    if [[ "$manifest_asin" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ -n "$extra" ]]; then
      echo "Invalid manifest line $line_no: expected 2 tab-separated columns." >&2
      exit 1
    fi

    if ! process_one "$manifest_asin" "$manifest_folder"; then
      echo "Aborting on manifest line $line_no." >&2
      exit 1
    fi
    count=$((count + 1))
  done < "$MANIFEST"

  if ((count == 0)); then
    echo "No titles found in manifest: $MANIFEST" >&2
    exit 1
  fi
  echo "Completed $count title(s) from manifest."
else
  if [[ -z "$ASIN" || -z "$BOOK_FOLDER" ]]; then
    echo "Both --asin and --book-folder are required in single-title mode." >&2
    usage
    exit 1
  fi
  process_one "$ASIN" "$BOOK_FOLDER"
fi
