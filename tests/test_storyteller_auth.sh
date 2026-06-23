#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON="$ROOT_DIR/skills/storyteller/scripts/_common.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [ "$actual" = "$expected" ] ||
    fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  local file="$1"
  local expected="$2"

  grep -Fq -- "$expected" "$file" ||
    fail "$file does not contain: $expected"
}

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_CURL_LOG"

case "$*" in
  *"/api/v2/token"*)
    cat >/dev/null
    printf '{"access_token":"%s"}' "${FAKE_REFRESH_TOKEN:-refreshed-token}"
    ;;
  *)
    printf '%s' "${FAKE_VALIDATE_STATUS:-200}"
    ;;
esac
EOF
chmod +x "$FAKE_BIN/curl"

run_resolve() {
  PATH="$FAKE_BIN:$PATH" \
  FAKE_CURL_LOG="$FAKE_CURL_LOG" \
  FAKE_VALIDATE_STATUS="${FAKE_VALIDATE_STATUS:-200}" \
  FAKE_REFRESH_TOKEN="${FAKE_REFRESH_TOKEN:-refreshed-token}" \
  STORYTELLER_TOKEN="${STORYTELLER_TOKEN:-}" \
  STORYTELLER_USERNAME_OR_EMAIL="${STORYTELLER_USERNAME_OR_EMAIL:-}" \
  STORYTELLER_PASSWORD="${STORYTELLER_PASSWORD:-}" \
    bash -c '. "$1"; resolve_token "$2" "$3"' _ \
      "$COMMON" "$TOKEN_FILE" "http://storyteller.test"
}

FAKE_CURL_LOG="$TEST_DIR/curl.log"
TOKEN_FILE="$TEST_DIR/config/token"

mkdir -p "$(dirname "$TOKEN_FILE")"
printf 'file-token' > "$TOKEN_FILE"
STORYTELLER_TOKEN="env-token"
FAKE_VALIDATE_STATUS=200
: > "$FAKE_CURL_LOG"
TOKEN="$(run_resolve)"
assert_eq "env-token" "$TOKEN" "environment token should take precedence"
assert_contains "$FAKE_CURL_LOG" "Authorization: Bearer env-token"

unset STORYTELLER_TOKEN
: > "$FAKE_CURL_LOG"
TOKEN="$(run_resolve)"
assert_eq "file-token" "$TOKEN" "saved token should be reused while valid"
assert_contains "$FAKE_CURL_LOG" "Authorization: Bearer file-token"

STORYTELLER_USERNAME_OR_EMAIL="reader@example.test"
STORYTELLER_PASSWORD="secret password"
FAKE_VALIDATE_STATUS=401
FAKE_REFRESH_TOKEN="new-token"
: > "$FAKE_CURL_LOG"
TOKEN="$(run_resolve)"
assert_eq "new-token" "$TOKEN" "401 should refresh the saved token"
assert_eq "new-token" "$(tr -d '\n' < "$TOKEN_FILE")" "refreshed token should be persisted"
assert_contains "$FAKE_CURL_LOG" "/api/v2/token"
if grep -Fq -- "$STORYTELLER_PASSWORD" "$FAKE_CURL_LOG"; then
  fail "password must not appear in curl arguments"
fi

FILE_MODE="$(stat -f '%Lp' "$TOKEN_FILE" 2>/dev/null || stat -c '%a' "$TOKEN_FILE")"
DIR_MODE="$(stat -f '%Lp' "$(dirname "$TOKEN_FILE")" 2>/dev/null || stat -c '%a' "$(dirname "$TOKEN_FILE")")"
assert_eq "600" "$FILE_MODE" "token file mode"
assert_eq "700" "$DIR_MODE" "token directory mode"

rm -f "$TOKEN_FILE"
FAKE_VALIDATE_STATUS=200
FAKE_REFRESH_TOKEN="bootstrap-token"
: > "$FAKE_CURL_LOG"
TOKEN="$(run_resolve)"
assert_eq "bootstrap-token" "$TOKEN" "credentials should bootstrap a missing token"
assert_eq "bootstrap-token" "$(tr -d '\n' < "$TOKEN_FILE")" "bootstrapped token should be persisted"

rm -f "$TOKEN_FILE"
unset STORYTELLER_PASSWORD
if ERROR="$(run_resolve 2>&1)"; then
  fail "incomplete credentials should fail without a token"
fi
case "$ERROR" in
  *"Set both STORYTELLER_USERNAME_OR_EMAIL and STORYTELLER_PASSWORD"*) ;;
  *) fail "incomplete credential error was unclear: $ERROR" ;;
esac

echo "storyteller auth: ok"
