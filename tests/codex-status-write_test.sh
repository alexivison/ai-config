#!/usr/bin/env bash
# Tests for the companion status write side (`tmux-companion.sh` + `tmux-primary.sh`).
# The Codex runtime still owns codex-status.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
ERRORS=""

# Source party-lib for write_codex_status helper
source "$REPO_ROOT/session/party-lib.sh"

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+="  FAIL: $label — expected '$expected', got '$actual'\n"
  fi
}

assert_not_empty() {
  local label="$1" actual="$2"
  if [[ -n "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+="  FAIL: $label — expected non-empty value\n"
  fi
}

assert_file_valid_json() {
  local label="$1" file="$2"
  if jq empty "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS+="  FAIL: $label — file is not valid JSON: $file\n"
  fi
}

# ---------------------------------------------------------------------------
# Setup: create a temp runtime dir simulating party_runtime_dir
# ---------------------------------------------------------------------------
TEST_RUNTIME_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_RUNTIME_DIR"' EXIT

STATUS_FILE="$TEST_RUNTIME_DIR/codex-status.json"

# ---------------------------------------------------------------------------
# Test 1: write_codex_status dispatch (working state)
# ---------------------------------------------------------------------------
echo "--- Test: write_codex_status dispatch"

write_codex_status "$TEST_RUNTIME_DIR" "working" "main" "review"

assert_file_valid_json "dispatch is valid JSON" "$STATUS_FILE"
assert_eq "dispatch state" "working" "$(jq -r '.state' "$STATUS_FILE")"
assert_eq "dispatch target" "main" "$(jq -r '.target' "$STATUS_FILE")"
assert_eq "dispatch mode" "review" "$(jq -r '.mode' "$STATUS_FILE")"
assert_not_empty "dispatch started_at" "$(jq -r '.started_at' "$STATUS_FILE")"

# ---------------------------------------------------------------------------
# Test 2: write_codex_status completion (idle state with verdict)
# ---------------------------------------------------------------------------
echo "--- Test: write_codex_status completion"

write_codex_status "$TEST_RUNTIME_DIR" "idle" "" "" "APPROVE"

assert_file_valid_json "completion is valid JSON" "$STATUS_FILE"
assert_eq "completion state" "idle" "$(jq -r '.state' "$STATUS_FILE")"
assert_eq "completion verdict" "APPROVE" "$(jq -r '.verdict' "$STATUS_FILE")"
assert_not_empty "completion finished_at" "$(jq -r '.finished_at' "$STATUS_FILE")"

# ---------------------------------------------------------------------------
# Test 3: write_codex_status error state
# ---------------------------------------------------------------------------
echo "--- Test: write_codex_status error"

write_codex_status "$TEST_RUNTIME_DIR" "error" "" "" "" "transport timeout"

assert_file_valid_json "error is valid JSON" "$STATUS_FILE"
assert_eq "error state" "error" "$(jq -r '.state' "$STATUS_FILE")"
assert_eq "error message" "transport timeout" "$(jq -r '.error' "$STATUS_FILE")"

# ---------------------------------------------------------------------------
# Test 4: Atomicity — .tmp file should not linger after write
# ---------------------------------------------------------------------------
echo "--- Test: atomicity (no .tmp residue)"

write_codex_status "$TEST_RUNTIME_DIR" "idle" "" "" "REQUEST_CHANGES"

TMP_COUNT=$(find "$TEST_RUNTIME_DIR" -name '*.tmp' | wc -l | tr -d ' ')
assert_eq "no .tmp files remain" "0" "$TMP_COUNT"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  printf '%b' "$ERRORS"
  exit 1
fi
