#!/usr/bin/env bash
# Tests for sidebar layout helpers: layout mode detection, Codex routing, CLI resolution.
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
# party_layout_mode
# ===========================================================================

echo ""
echo "  === party_layout_mode ==="

# Default (no env var) → sidebar
unset PARTY_LAYOUT
result=$(party_layout_mode)
assert "layout_mode: default is sidebar" \
  '[ "$result" = "sidebar" ]'

# Explicit classic
PARTY_LAYOUT=classic
result=$(party_layout_mode)
assert "layout_mode: PARTY_LAYOUT=classic returns classic" \
  '[ "$result" = "classic" ]'

# Sidebar opt-in
PARTY_LAYOUT=sidebar
result=$(party_layout_mode)
assert "layout_mode: PARTY_LAYOUT=sidebar returns sidebar" \
  '[ "$result" = "sidebar" ]'

# Unknown value → classic (safe default)
PARTY_LAYOUT=unknown
result=$(party_layout_mode)
assert "layout_mode: unknown value falls back to classic" \
  '[ "$result" = "classic" ]'

unset PARTY_LAYOUT

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
# party_companion_pane_target — resolves by role across layouts
# ===========================================================================

echo ""
echo "  === party_companion_pane_target ==="

# Sidebar mode with a companion: resolves the hidden companion pane
PARTY_LAYOUT=sidebar
MOCK_WINDOW_LIST=$'0\n1'
MOCK_PANE_DATA_WIN0=$'0 companion'
MOCK_PANE_DATA_WIN1=$'0 tracker\n1 primary\n2 shell'
result=$(party_companion_pane_target "party-test")
assert "companion_target: sidebar mode resolves to session:0.0" \
  '[ "$result" = "party-test:0.0" ]'

# Classic mode: uses role-based resolution on canonical tags.
PARTY_LAYOUT=classic
unset MOCK_PANE_DATA_WIN0 MOCK_PANE_DATA_WIN1 MOCK_WINDOW_LIST
MOCK_PANE_DATA=$'0 companion\n1 primary\n2 shell'
result=$(party_companion_pane_target "party-test")
assert "companion_target: classic mode uses canonical role resolution" \
  '[ "$result" = "party-test:0.0" ]'

# Classic mode with companion in different pane position → resolves correctly
MOCK_PANE_DATA=$'0 primary\n1 companion\n2 shell'
result=$(party_companion_pane_target "party-test")
assert "companion_target: classic mode resolves companion at pane 1" \
  '[ "$result" = "party-test:0.1" ]'

# Classic mode falls back to legacy codex tag.
MOCK_PANE_DATA=$'0 codex\n1 claude\n2 shell'
result=$(party_companion_pane_target "party-test")
assert "companion_target: classic mode falls back to legacy codex" \
  '[ "$result" = "party-test:0.0" ]'

# Sidebar mode with no companion now rejects the lookup instead of hitting the tracker.
PARTY_LAYOUT=sidebar
MOCK_PANE_DATA=""
MOCK_PANE_DATA_WIN0=""
MOCK_PANE_DATA_WIN1=$'0 tracker\n1 primary\n2 shell'
if party_companion_pane_target "party-test" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] companion_target: sidebar no-companion sessions reject lookup"
else
  PASS=$((PASS + 1))
  echo "  [PASS] companion_target: sidebar no-companion sessions reject lookup"
fi

# Backward-compatible wrapper delegates to companion helper.
PARTY_LAYOUT=classic
MOCK_PANE_DATA=$'0 companion\n1 primary\n2 shell'
unset MOCK_PANE_DATA_WIN0 MOCK_PANE_DATA_WIN1 MOCK_WINDOW_LIST
result=$(party_codex_pane_target "party-test")
assert "codex_target: wrapper delegates to companion helper" \
  '[ "$result" = "party-test:0.0" ]'

unset PARTY_LAYOUT

# NOTE: party_resolve_cli_cmd and party_promote tests removed —
# both now live in party-cli (Go). See tools/party-cli/ for tests.

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
