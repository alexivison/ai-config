#!/usr/bin/env bash
# Tests for role-based pane routing helpers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/session/party-lib.sh"

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

# Mock tmux list-panes. Tests set MOCK_PANE_DATA before each case.
# Format per line: "index role" (matches '#{pane_index} #{@party_role}')
MOCK_PANE_DATA=""
tmux() {
  if [[ "$1" == "list-panes" ]]; then
    if [[ -n "$MOCK_PANE_DATA" ]]; then
      printf '%s\n' "$MOCK_PANE_DATA"
      return 0
    fi
    return 1
  fi
  # Mock display-message to always return window 0 for deterministic tests
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'#{window_index}'* ]]; then
    echo "0"
    return 0
  fi
  command tmux "$@"
}

echo "--- test-party-routing.sh ---"

# === party_role_pane_target ===

MOCK_PANE_DATA=$'0 codex\n1 claude\n2 shell'

result=$(party_role_pane_target "party-test" "codex")
assert "role resolver: codex resolves to pane 0" \
  '[ "$result" = "party-test:0.0" ]'

result=$(party_role_pane_target "party-test" "claude")
assert "role resolver: claude resolves to pane 1" \
  '[ "$result" = "party-test:0.1" ]'

result=$(party_role_pane_target "party-test" "shell")
assert "role resolver: shell resolves to pane 2" \
  '[ "$result" = "party-test:0.2" ]'

# Missing role → ROLE_NOT_FOUND
if party_role_pane_target "party-test" "missing" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] role resolver: missing role returns error"
else
  PASS=$((PASS + 1))
  echo "  [PASS] role resolver: missing role returns error"
fi

err=$(party_role_pane_target "party-test" "missing" 2>&1 >/dev/null || true)
assert "role resolver: missing role emits ROLE_NOT_FOUND" \
  '[[ "$err" == *"ROLE_NOT_FOUND"* ]]'

# Duplicate role → ROLE_AMBIGUOUS
MOCK_PANE_DATA=$'0 codex\n1 codex\n2 shell'

if party_role_pane_target "party-test" "codex" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] role resolver: duplicate role returns error"
else
  PASS=$((PASS + 1))
  echo "  [PASS] role resolver: duplicate role returns error"
fi

err=$(party_role_pane_target "party-test" "codex" 2>&1 >/dev/null || true)
assert "role resolver: duplicate role emits ROLE_AMBIGUOUS" \
  '[[ "$err" == *"ROLE_AMBIGUOUS"* ]]'

# === party_role_pane_target_with_fallback (legacy fallback removed) ===

# Role metadata present → resolves by role
MOCK_PANE_DATA=$'0 codex\n1 claude\n2 shell'

result=$(party_role_pane_target_with_fallback "party-test" "claude")
assert "wrapper: role present, resolves by role" \
  '[ "$result" = "party-test:0.1" ]'

# 2-pane session without roles → now rejected (no legacy fallback)
MOCK_PANE_DATA=$'0 \n1 '

if party_role_pane_target_with_fallback "party-test" "claude" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] wrapper: 2-pane without roles now rejected"
else
  PASS=$((PASS + 1))
  echo "  [PASS] wrapper: 2-pane without roles now rejected"
fi

err=$(party_role_pane_target_with_fallback "party-test" "codex" 2>&1 >/dev/null || true)
assert "wrapper: 2-pane without roles emits ROLE_NOT_FOUND" \
  '[[ "$err" == *"ROLE_NOT_FOUND"* ]]'

# 3-pane session without roles → rejected
MOCK_PANE_DATA=$'0 \n1 \n2 '

if party_role_pane_target_with_fallback "party-test" "claude" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] wrapper: 3-pane without roles rejected"
else
  PASS=$((PASS + 1))
  echo "  [PASS] wrapper: 3-pane without roles rejected"
fi

# Duplicate role through wrapper → ROLE_AMBIGUOUS propagated
MOCK_PANE_DATA=$'0 codex\n1 codex\n2 shell'

if party_role_pane_target_with_fallback "party-test" "codex" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] wrapper: duplicate role returns error"
else
  PASS=$((PASS + 1))
  echo "  [PASS] wrapper: duplicate role returns error"
fi

err=$(party_role_pane_target_with_fallback "party-test" "codex" 2>&1 >/dev/null || true)
assert "wrapper: duplicate role propagates ROLE_AMBIGUOUS" \
  '[[ "$err" == *"ROLE_AMBIGUOUS"* ]]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
