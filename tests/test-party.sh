#!/usr/bin/env bash
# Tests for session/party.sh and session/party-lib.sh
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

cleanup() {
  tmux kill-session -t "party-test-$$" 2>/dev/null || true
  rm -rf "/tmp/party-test-$$"
}
trap cleanup EXIT

echo "--- test-party.sh ---"

source "$REPO_ROOT/session/party-lib.sh"

# Test: discover_session fails outside tmux (no TMUX, no PARTY_SESSION)
unset TMUX 2>/dev/null || true
unset PARTY_SESSION 2>/dev/null || true
assert "discover_session fails outside tmux" \
  '! discover_session 2>/dev/null'

# Test: discover_session fails with non-party PARTY_SESSION override
export PARTY_SESSION="not-a-party-session"
assert "discover_session rejects non-party session names" \
  '! discover_session 2>/dev/null'
unset PARTY_SESSION

# Test: party.sh --stop with no sessions exits cleanly
assert "party.sh --stop with no sessions exits cleanly" \
  '"$REPO_ROOT/session/party.sh" --stop 2>/dev/null'

# Test: party.sh --list with no sessions
OUTPUT=$("$REPO_ROOT/session/party.sh" --list 2>&1)
assert "party.sh --list shows no sessions when none running" \
  'echo "$OUTPUT" | grep -q "No active"'

# Test: party.sh --stop specific session
tmux new-session -d -s "party-test-$$" -n work
mkdir -p "/tmp/party-test-$$"
echo "party-test-$$" > "/tmp/party-test-$$/session-name"
"$REPO_ROOT/session/party.sh" --stop "party-test-$$" 2>/dev/null
assert "party.sh --stop <name> kills specific session" \
  '! tmux has-session -t "party-test-$$" 2>/dev/null'

# Test: party.sh --stop rejects invalid session names (path traversal guard)
OUTPUT=$("$REPO_ROOT/session/party.sh" --stop "../../etc" 2>&1 || true)
assert "party.sh --stop rejects non-party names" \
  'echo "$OUTPUT" | grep -q "invalid session name"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
