#!/usr/bin/env bash
# Tests for session-discovery and companion pane routing helpers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/session"
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

# Mock tmux for routing tests
MOCK_PANE_DATA=""
MOCK_WINDOW_LIST=""
MOCK_CURRENT_WINDOW="0"
MOCK_SESSION_NAME=""
MOCK_SESSION_TARGET=""
MOCK_TARGET_SESSION_NAME=""
tmux() {
  if [[ "$1" == "list-panes" ]]; then
    # Extract window from target (e.g., "session:0" -> return window 0 data, "session:1" -> window 1 data)
    local target_win=""
    if [[ "$*" == *"-t"* ]]; then
      local t_arg=""
      local prev=""
      for arg in "$@"; do
        if [[ "$prev" == "-t" ]]; then
          t_arg="$arg"
          break
        fi
        prev="$arg"
      done
      target_win="${t_arg##*:}"
    fi
    local var_name="MOCK_PANE_DATA_WIN${target_win}"
    local data="${!var_name:-$MOCK_PANE_DATA}"
    if [[ -n "$data" ]]; then
      printf '%s\n' "$data"
      return 0
    fi
    return 1
  fi
  if [[ "$1" == "list-windows" ]]; then
    if [[ -n "$MOCK_WINDOW_LIST" ]]; then
      printf '%s\n' "$MOCK_WINDOW_LIST"
      return 0
    fi
    return 1
  fi
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'#{session_name}'* ]]; then
    local target=""
    local prev=""
    for arg in "$@"; do
      if [[ "$prev" == "-t" ]]; then
        target="$arg"
        break
      fi
      prev="$arg"
    done
    if [[ -n "$target" && -n "$MOCK_SESSION_TARGET" && "$target" == "$MOCK_SESSION_TARGET" ]]; then
      printf '%s\n' "$MOCK_TARGET_SESSION_NAME"
      return 0
    fi
    printf '%s\n' "${MOCK_SESSION_NAME:-party-test}"
    return 0
  fi
  if [[ "$1" == "display-message" ]] && [[ "$*" == *'#{window_index}'* ]]; then
    echo "$MOCK_CURRENT_WINDOW"
    return 0
  fi
  command tmux "$@"
}

echo "--- test-party-sidebar-layout.sh ---"

# ===========================================================================
# discover_session
# ===========================================================================

echo ""
echo "  === discover_session ==="

unset PARTY_SESSION
export TMUX=1
export TMUX_PANE="%42"
MOCK_SESSION_NAME="party-client"
MOCK_SESSION_TARGET="%42"
MOCK_TARGET_SESSION_NAME="party-from-pane"
discover_session
assert "discover_session: TMUX_PANE target wins over active client session" \
  '[ "$SESSION_NAME" = "party-from-pane" ]'
assert "discover_session: runtime dir follows pane-derived session" \
  '[ "$STATE_DIR" = "/tmp/party-from-pane" ]'
unset TMUX
unset TMUX_PANE
unset SESSION_NAME
unset STATE_DIR
unset MOCK_SESSION_NAME MOCK_SESSION_TARGET MOCK_TARGET_SESSION_NAME

# ===========================================================================
# party_companion_pane_target — resolves the hidden companion pane by role
# ===========================================================================

echo ""
echo "  === party_companion_pane_target ==="

# Sidebar layout with a companion: resolves the hidden companion pane
MOCK_WINDOW_LIST=$'0\n1'
MOCK_PANE_DATA_WIN0=$'0 companion'
MOCK_PANE_DATA_WIN1=$'0 tracker\n1 primary\n2 shell'
result=$(party_companion_pane_target "party-test")
assert "companion_target: resolves to session:0.0" \
  '[ "$result" = "party-test:0.0" ]'

# No-companion sessions reject the lookup instead of hitting the tracker.
MOCK_PANE_DATA=""
MOCK_PANE_DATA_WIN0=""
MOCK_PANE_DATA_WIN1=$'0 tracker\n1 primary\n2 shell'
if party_companion_pane_target "party-test" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] companion_target: no-companion sessions reject lookup"
else
  PASS=$((PASS + 1))
  echo "  [PASS] companion_target: no-companion sessions reject lookup"
fi

# NOTE: party_resolve_cli_cmd and party_promote tests removed —
# both now live in party-cli (Go). See tools/party-cli/ for tests.

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
