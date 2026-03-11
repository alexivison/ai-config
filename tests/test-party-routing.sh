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

# === party_role_pane_target_with_fallback ===

# Role metadata present → resolves by role
MOCK_PANE_DATA=$'0 codex\n1 claude\n2 shell'

result=$(party_role_pane_target_with_fallback "party-test" "claude")
assert "fallback: role present, resolves by role" \
  '[ "$result" = "party-test:0.1" ]'

# Legacy 2-pane session without roles → fallback activates
MOCK_PANE_DATA=$'0 \n1 '

result=$(party_role_pane_target_with_fallback "party-test" "claude")
assert "fallback: legacy 2-pane, claude falls back to 0.0" \
  '[ "$result" = "party-test:0.0" ]'

result=$(party_role_pane_target_with_fallback "party-test" "codex")
assert "fallback: legacy 2-pane, codex falls back to 0.1" \
  '[ "$result" = "party-test:0.1" ]'

# 3-pane session without roles → topology guard rejects
MOCK_PANE_DATA=$'0 \n1 \n2 '

if party_role_pane_target_with_fallback "party-test" "claude" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] fallback: 3-pane without roles rejects fallback"
else
  PASS=$((PASS + 1))
  echo "  [PASS] fallback: 3-pane without roles rejects fallback"
fi

err=$(party_role_pane_target_with_fallback "party-test" "claude" 2>&1 >/dev/null || true)
assert "fallback: 3-pane without roles emits ROUTING_UNRESOLVED" \
  '[[ "$err" == *"ROUTING_UNRESOLVED"* ]]'

# Duplicate role through fallback wrapper → ROLE_AMBIGUOUS propagated (not masked)
MOCK_PANE_DATA=$'0 codex\n1 codex\n2 shell'

if party_role_pane_target_with_fallback "party-test" "codex" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] fallback: duplicate role returns error"
else
  PASS=$((PASS + 1))
  echo "  [PASS] fallback: duplicate role returns error"
fi

err=$(party_role_pane_target_with_fallback "party-test" "codex" 2>&1 >/dev/null || true)
assert "fallback: duplicate role propagates ROLE_AMBIGUOUS (not ROUTING_UNRESOLVED)" \
  '[[ "$err" == *"ROLE_AMBIGUOUS"* ]]'

# Unknown role in legacy session → unresolved (no fallback for non-agent roles)
MOCK_PANE_DATA=$'0 \n1 '

if party_role_pane_target_with_fallback "party-test" "shell" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] fallback: unknown role in legacy session unresolved"
else
  PASS=$((PASS + 1))
  echo "  [PASS] fallback: unknown role in legacy session unresolved"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
