#!/usr/bin/env bash
# Tests for Task 2 hardening: jq prereq, fallback removal, send stderr, temp cleanup.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  if eval "$2"; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $desc"
  fi
}

# ===================================================================
# 1. jq prereq — manifest mutations must fail when jq is missing
# ===================================================================
echo "--- jq prerequisite enforcement ---"

# We test by running party-lib functions in a subshell with jq removed from PATH.
# Current behavior: `command -v jq >/dev/null 2>&1 || return 0` (silent skip).
# Expected behavior: fail with non-zero exit and an error message.

SESSION="party-test-jq-$$"
export PARTY_STATE_ROOT="/tmp/party-state-root-jq-$$"
cleanup_jq() { rm -rf "$PARTY_STATE_ROOT" "/tmp/$SESSION"; }
trap cleanup_jq EXIT

mkdir -p "$PARTY_STATE_ROOT"

# Test party_state_upsert_manifest fails without jq
err=""
rc=0
err=$(PATH="/usr/bin:/bin" bash -c '
  # Remove jq from PATH entirely
  export PATH=$(echo "$PATH" | tr ":" "\n" | grep -v "$(dirname "$(command -v jq 2>/dev/null)")" | tr "\n" ":")
  # Ensure jq is genuinely missing
  if command -v jq >/dev/null 2>&1; then
    # jq is a builtin or in a path we cannot filter — skip
    echo "SKIP: cannot hide jq"
    exit 0
  fi
  source "'"$REPO_ROOT"'/session/party-lib.sh"
  party_state_upsert_manifest "test-sess" "title" "/tmp" "win" "/bin/claude" "" "/usr/bin" 2>&1
' 2>&1) || rc=$?

if [[ "$err" == *"SKIP"* ]]; then
  echo "  [SKIP] jq prereq tests — cannot hide jq from PATH"
else
  assert "upsert_manifest fails (non-zero) when jq is missing" \
    '[ "$rc" -ne 0 ]'
  assert "upsert_manifest emits jq error on stderr" \
    '[[ "$err" == *"jq"* ]]'

  # Test party_state_set_field fails without jq
  err2=""
  rc2=0
  err2=$(PATH="/usr/bin:/bin" bash -c '
    export PATH=$(echo "$PATH" | tr ":" "\n" | grep -v "$(dirname "$(command -v jq 2>/dev/null)")" | tr "\n" ":")
    if command -v jq >/dev/null 2>&1; then exit 0; fi
    source "'"$REPO_ROOT"'/session/party-lib.sh"
    party_state_set_field "test-sess" "key" "val" 2>&1
  ' 2>&1) || rc2=$?

  assert "set_field fails (non-zero) when jq is missing" \
    '[ "$rc2" -ne 0 ]'

  # Test worker mutators fail without jq
  err3=""
  rc3=0
  err3=$(PATH="/usr/bin:/bin" bash -c '
    export PATH=$(echo "$PATH" | tr ":" "\n" | grep -v "$(dirname "$(command -v jq 2>/dev/null)")" | tr "\n" ":")
    if command -v jq >/dev/null 2>&1; then exit 0; fi
    source "'"$REPO_ROOT"'/session/party-lib.sh"
    export PARTY_STATE_ROOT="/tmp/party-jq-test-$$"
    mkdir -p "$PARTY_STATE_ROOT"
    echo "{}" > "$PARTY_STATE_ROOT/test-master.json"
    party_state_remove_worker "test-master" "test-worker" 2>&1
  ' 2>&1) || rc3=$?

  assert "remove_worker fails (non-zero) when jq is missing" \
    '[ "$rc3" -ne 0 ]'
  assert "remove_worker emits jq error on stderr" \
    '[[ "$err3" == *"jq"* ]]'
fi

# ===================================================================
# 2. Legacy fallback removal — no more positional guessing
# ===================================================================
echo ""
echo "--- legacy fallback removal ---"

source "$REPO_ROOT/session/party-lib.sh"

# Mock tmux for routing tests
MOCK_PANE_DATA=""
tmux() {
  if [[ "$1" == "list-panes" ]]; then
    [[ -n "$MOCK_PANE_DATA" ]] && { printf '%s\n' "$MOCK_PANE_DATA"; return 0; }
    return 1
  fi
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'#{window_index}'* ]]; then
    echo "0"; return 0
  fi
  if [[ "$1" == "list-windows" ]]; then
    echo "0"; return 0
  fi
  command tmux "$@"
}

# Legacy 2-pane session without roles should now FAIL (no fallback)
MOCK_PANE_DATA=$'0 \n1 '

if party_role_pane_target_with_fallback "party-test" "claude" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] legacy 2-pane without roles now rejected (fallback removed)"
else
  PASS=$((PASS + 1))
  echo "  [PASS] legacy 2-pane without roles now rejected (fallback removed)"
fi

err=$(party_role_pane_target_with_fallback "party-test" "codex" 2>&1 >/dev/null || true)
assert "legacy 2-pane emits ROUTING_UNRESOLVED (not a positional guess)" \
  '[[ "$err" == *"ROUTING_UNRESOLVED"* || "$err" == *"ROLE_NOT_FOUND"* ]]'

# With role metadata, resolution still works
MOCK_PANE_DATA=$'0 codex\n1 claude'
result=$(party_role_pane_target_with_fallback "party-test" "claude")
assert "role metadata present: still resolves correctly" \
  '[ "$result" = "party-test:0.1" ]'

# ===================================================================
# 3. tmux_send failure produces stderr output
# ===================================================================
echo ""
echo "--- tmux_send stderr on failure ---"

# Override tmux to always claim pane is in copy mode (busy), causing timeout
tmux() {
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'pane_in_mode'* ]]; then
    echo "1"; return 0  # in copy mode = busy
  fi
  command tmux "$@" 2>/dev/null || true
}

# Re-source to pick up the mock — but tmux_send/tmux_pane_idle are already defined
# We just need the mock to shadow the tmux command

export TMUX_SEND_TIMEOUT=0.2  # fast timeout for tests
export TMUX_SEND_FORCE=""      # ensure force bypass is off

stderr_output=""
rc=0
stderr_output=$(tmux_send "fake-pane" "test message" "test-caller" 2>&1 >/dev/null) || rc=$?

assert "tmux_send returns 75 (EX_TEMPFAIL) on timeout" \
  '[ "$rc" -eq 75 ]'
assert "tmux_send emits stderr on timeout" \
  '[[ -n "$stderr_output" ]]'
assert "tmux_send stderr includes target pane" \
  '[[ "$stderr_output" == *"fake-pane"* ]]'
assert "tmux_send stderr includes payload excerpt" \
  '[[ "$stderr_output" == *"test message"* ]]'

# ===================================================================
# 4. Temp file cleanup via traps
# ===================================================================
echo ""
echo "--- temp file cleanup ---"

# Restore working tmux mock for state operations
tmux() {
  if [[ "$1" == "list-panes" ]]; then
    [[ -n "$MOCK_PANE_DATA" ]] && { printf '%s\n' "$MOCK_PANE_DATA"; return 0; }
    return 1
  fi
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'#{window_index}'* ]]; then
    echo "0"; return 0
  fi
  command tmux "$@" 2>/dev/null || true
}

# Test: after a successful manifest upsert, no temp files remain
if command -v jq >/dev/null 2>&1; then
  TEST_SESSION="party-test-temp-$$"
  TEST_TMPDIR="/tmp/party-tmpdir-test-$$"
  mkdir -p "$TEST_TMPDIR"
  export TMPDIR="$TEST_TMPDIR"
  export PARTY_STATE_ROOT="/tmp/party-state-root-temp-$$"
  mkdir -p "$PARTY_STATE_ROOT"

  party_state_upsert_manifest "$TEST_SESSION" "test" "/tmp" "win" "/bin/claude" "" "/usr/bin" || true

  leftover=$(find "$TEST_TMPDIR" -name 'party-state.*' 2>/dev/null | wc -l | tr -d ' ')
  assert "no leaked temp files after successful upsert" \
    '[ "$leftover" -eq 0 ]'

  # Test: temp files are cleaned even on jq failure (bad JSON input)
  BAD_FILE="$(party_state_file "$TEST_SESSION")"
  echo "NOT VALID JSON" > "$BAD_FILE"

  party_state_set_field "$TEST_SESSION" "key" "val" 2>/dev/null || true
  leftover=$(find "$TEST_TMPDIR" -name 'party-state.*' 2>/dev/null | wc -l | tr -d ' ')
  assert "no leaked temp files after failed jq operation" \
    '[ "$leftover" -eq 0 ]'

  rm -rf "$PARTY_STATE_ROOT" "/tmp/$TEST_SESSION" "$TEST_TMPDIR"
  unset TMPDIR
else
  echo "  [SKIP] temp file tests — jq not available"
fi

# ===================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
