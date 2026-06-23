#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IGNORE_FILE="$ROOT_DIR/.gitignore"
CALIBRE_SKILL="$ROOT_DIR/skills/calibre-library/SKILL.md"
CALIBRE_WORKFLOWS="$ROOT_DIR/skills/calibre-library/references/workflows.md"
CALIBRE_RECIPES="$ROOT_DIR/skills/calibre-library/references/command-recipes.md"
STORYTELLER_SKILL="$ROOT_DIR/skills/storyteller/SKILL.md"
STORYTELLER_WORKFLOWS="$ROOT_DIR/skills/storyteller/references/api-workflows.md"
AUDIBLE_SKILL="$ROOT_DIR/skills/audible-download-convert/SKILL.md"
AUDIBLE_DOWNLOAD="$ROOT_DIR/skills/audible-download-convert/scripts/download_and_convert.sh"
AUDIBLE_CONVERT="$ROOT_DIR/skills/audible-download-convert/scripts/convert_aax_to_m4b.sh"
AUDIBLE_PROJECT="$ROOT_DIR/skills/audible-download-convert/pyproject.toml"
AUDIBLE_LOCK="$ROOT_DIR/skills/audible-download-convert/uv.lock"
AUDIBLE_AGENT="$ROOT_DIR/skills/audible-download-convert/agents/openai.yaml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file" ||
    fail "$file does not contain: $expected"
}

assert_line() {
  local file="$1"
  local expected="$2"

  grep -Fxq -- "$expected" "$file" ||
    fail "$file does not contain exact line: $expected"
}

frontmatter() {
  local file="$1"

  awk 'NR == 1 && $0 == "---" {inside=1; next} inside && $0 == "---" {exit} inside' "$file"
}

assert_frontmatter_contract() {
  local file="$1"
  local commands="$2"
  local content
  content="$(frontmatter "$file")"

  grep -Fxq 'platforms: [linux, macos]' <<<"$content" ||
    fail "$file frontmatter does not declare top-level linux and macos platforms"
  grep -Fxq 'prerequisites:' <<<"$content" ||
    fail "$file frontmatter does not declare top-level prerequisites"
  grep -Fxq "  commands: $commands" <<<"$content" ||
    fail "$file frontmatter does not declare exact prerequisite commands: $commands"

  if grep -Fxq 'metadata:' <<<"$content"; then
    fail "$file runtime contract must not be nested under metadata"
  fi
}

assert_no_literal() {
  local literal="$1"
  shift

  if grep -Fn -- "$literal" "$@"; then
    fail "unexpected literal found: $literal"
  fi
}

assert_frontmatter_contract \
  "$CALIBRE_SKILL" '[calibredb, sqlite3, curl, jq]'
assert_contains "$CALIBRE_SKILL" \
  'CALIBRE_LIBRARY_PATH="${CALIBRE_LIBRARY_PATH:-/path/to/Calibre Library}"'
assert_contains "$CALIBRE_WORKFLOWS" '$CALIBRE_LIBRARY_PATH'
assert_contains "$CALIBRE_RECIPES" '$CALIBRE_LIBRARY_PATH'
assert_no_literal '/data/calibre' \
  "$CALIBRE_SKILL" "$CALIBRE_WORKFLOWS" "$CALIBRE_RECIPES"

while IFS= read -r match; do
  normalized="${match//\$\{CALIBRE_LIBRARY_PATH:-\/path\/to\/Calibre Library\}/}"
  if [[ "$normalized" == *"/path/to/Calibre Library"* ]]; then
    fail "the Calibre placeholder path is only allowed in CALIBRE_LIBRARY_PATH defaults: $match"
  fi
done < <(
  grep -Hn '/path/to/Calibre Library' \
    "$CALIBRE_SKILL" "$CALIBRE_WORKFLOWS" "$CALIBRE_RECIPES" || true
)

assert_frontmatter_contract "$STORYTELLER_SKILL" '[bash, curl, jq, file, uuidgen]'
assert_contains "$STORYTELLER_SKILL" \
  'STORYTELLER_API_BASE="${STORYTELLER_API_BASE:-http://localhost:8001}"'
assert_contains "$STORYTELLER_SKILL" \
  '${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}'
assert_contains "$STORYTELLER_WORKFLOWS" \
  '"${STORYTELLER_API_BASE:-http://localhost:8001}/api/v2/token"'
assert_contains "$STORYTELLER_WORKFLOWS" \
  '"${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"'
assert_contains "$STORYTELLER_WORKFLOWS" \
  'TOKEN_FILE="${STORYTELLER_TOKEN_FILE:-$HOME/.config/storyteller-skill/.storyteller_token}"'
assert_contains "$STORYTELLER_WORKFLOWS" 'mkdir -p "$(dirname "$TOKEN_FILE")"'
assert_contains "$STORYTELLER_WORKFLOWS" 'curl -fsS'
assert_contains "$STORYTELLER_WORKFLOWS" "jq -r '.access_token // empty'"
assert_contains "$STORYTELLER_WORKFLOWS" '[ -n "$TOKEN" ]'
assert_contains "$STORYTELLER_WORKFLOWS" "printf '%s\\n' \"\$TOKEN\" > \"\$TOKEN_FILE\""
assert_contains "$STORYTELLER_WORKFLOWS" 'chmod 600 "$TOKEN_FILE"'
assert_contains "$STORYTELLER_SKILL" 'network'
assert_contains "$STORYTELLER_WORKFLOWS" 'network'
assert_no_literal '"$STORYTELLER_API_BASE' "$STORYTELLER_WORKFLOWS"
assert_no_literal '"$STORYTELLER_TOKEN_FILE"' "$STORYTELLER_WORKFLOWS"

while IFS= read -r match; do
  normalized="${match//\$\{STORYTELLER_TOKEN_FILE:-\$HOME\/.config\/storyteller-skill\/.storyteller_token\}/}"
  if [[ "$normalized" == *".storyteller_token"* ]]; then
    fail "the default token path must use the STORYTELLER_TOKEN_FILE expansion: $match"
  fi
done < <(
  grep -Hn '.storyteller_token' "$STORYTELLER_SKILL" "$STORYTELLER_WORKFLOWS" || true
)

while IFS= read -r match; do
  normalized="${match//\$\{STORYTELLER_API_BASE:-http:\/\/localhost:8001\}/}"
  if [[ "$normalized" == *"localhost"* ]]; then
    fail "localhost is only allowed in the STORYTELLER_API_BASE default expansion: $match"
  fi
done < <(grep -Hn 'localhost' "$STORYTELLER_SKILL" "$STORYTELLER_WORKFLOWS" || true)

for required_file in \
  "$AUDIBLE_DOWNLOAD" \
  "$AUDIBLE_CONVERT" \
  "$AUDIBLE_PROJECT" \
  "$AUDIBLE_LOCK" \
  "$AUDIBLE_AGENT"; do
  [[ -f "$required_file" ]] || fail "required file does not exist: $required_file"
done

assert_contains "$AUDIBLE_CONVERT" 'SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"'
assert_contains "$AUDIBLE_CONVERT" 'REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"'
assert_contains "$AUDIBLE_CONVERT" \
  'BASE_DIR="${BASE_DIR:-$REPO_ROOT/audible_data}"'

[[ -f "$AUDIBLE_SKILL" ]] || fail "required file does not exist: $AUDIBLE_SKILL"
assert_frontmatter_contract "$AUDIBLE_SKILL" '[bash, uv, ffmpeg, ffprobe, jq]'
assert_line "$AUDIBLE_SKILL" \
  'AUDIBLE_DATA_DIR="${AUDIBLE_DATA_DIR:-$REPO_ROOT/audible_data}"'
assert_line "$AUDIBLE_SKILL" \
  'AUDIBLE_VENV_DIR="${AUDIBLE_VENV_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/audible-download-convert/venv}"'
assert_line "$AUDIBLE_SKILL" \
  'AUDIBLE_CONFIG_DIR="${AUDIBLE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/audible}"'
assert_line "$AUDIBLE_SKILL" 'export AUDIBLE_CONFIG_DIR'
assert_line "$AUDIBLE_SKILL" \
  'AUDIBLE_AUTHCODE_FILE="${AUDIBLE_AUTHCODE_FILE:-$AUDIBLE_CONFIG_DIR/.authcode}"'
assert_line "$AUDIBLE_SKILL" 'export AUDIBLE_AUTHCODE_FILE'
assert_line "$AUDIBLE_SKILL" 'mkdir -p "$(dirname "$AUDIBLE_AUTHCODE_FILE")"'
assert_line "$AUDIBLE_SKILL" 'umask 077'
assert_line "$AUDIBLE_SKILL" 'chmod 600 "$AUDIBLE_AUTHCODE_FILE"'
assert_line "$IGNORE_FILE" '.venv/'
assert_line "$IGNORE_FILE" '.authcode'
assert_line "$IGNORE_FILE" 'audible_data/'
assert_contains "$AUDIBLE_DOWNLOAD" 'SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"'
assert_contains "$AUDIBLE_DOWNLOAD" 'REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"'
assert_line "$AUDIBLE_DOWNLOAD" \
  'AUDIBLE_CONFIG_DIR="${AUDIBLE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/audible}"'
assert_line "$AUDIBLE_DOWNLOAD" \
  'AUDIBLE_AUTHCODE_FILE="${AUDIBLE_AUTHCODE_FILE:-$AUDIBLE_CONFIG_DIR/.authcode}"'
assert_line "$AUDIBLE_DOWNLOAD" \
  'export AUDIBLE_CONFIG_DIR AUDIBLE_AUTHCODE_FILE'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'download_cmd=(uv run --project "$SKILL_DIR" --frozen audible)'
assert_contains "$AUDIBLE_DOWNLOAD" \
  'CONVERT_CMD="$SCRIPT_DIR/convert_aax_to_m4b.sh"'
assert_contains "$AUDIBLE_PROJECT" 'audible-cli==0.3.3'
assert_no_literal '/path/to/audible' \
  "$AUDIBLE_SKILL" "$AUDIBLE_DOWNLOAD" "$AUDIBLE_CONVERT"
assert_no_literal '../audible' \
  "$AUDIBLE_SKILL" "$AUDIBLE_DOWNLOAD" "$AUDIBLE_CONVERT"

echo "skill runtime contracts: ok"
