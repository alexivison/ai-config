#!/usr/bin/env bash
# Tests for sidebar layout helpers: layout mode detection, Codex routing, CLI resolution.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/session"
source "$REPO_ROOT/session/party-lib.sh"
source "$REPO_ROOT/session/party-master.sh"

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

# Default (no env var) → classic
unset PARTY_LAYOUT
result=$(party_layout_mode)
assert "layout_mode: default is classic" \
  '[ "$result" = "classic" ]'

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
# party_codex_pane_target — sidebar mode routes to window 0
# ===========================================================================

echo ""
echo "  === party_codex_pane_target ==="

# Sidebar mode: Codex is in window 0 pane 0 (hidden window)
PARTY_LAYOUT=sidebar
result=$(party_codex_pane_target "party-test")
assert "codex_target: sidebar mode resolves to session:0.0" \
  '[ "$result" = "party-test:0.0" ]'

# Classic mode: uses role-based resolution (Codex in window 0 pane 0 in the classic 3-pane layout)
PARTY_LAYOUT=classic
MOCK_PANE_DATA=$'0 codex\n1 claude\n2 shell'
MOCK_WINDOW_LIST="0"
result=$(party_codex_pane_target "party-test")
assert "codex_target: classic mode uses role resolution" \
  '[ "$result" = "party-test:0.0" ]'

# Classic mode with Codex in different pane position → resolves correctly
MOCK_PANE_DATA=$'0 claude\n1 codex\n2 shell'
result=$(party_codex_pane_target "party-test")
assert "codex_target: classic mode resolves codex at pane 1" \
  '[ "$result" = "party-test:0.1" ]'

# Sidebar mode ignores pane data — always window 0 pane 0
PARTY_LAYOUT=sidebar
MOCK_PANE_DATA=$'0 claude\n1 shell'
result=$(party_codex_pane_target "party-test")
assert "codex_target: sidebar always returns 0.0 regardless of pane data" \
  '[ "$result" = "party-test:0.0" ]'

unset PARTY_LAYOUT

# ===========================================================================
# party_resolve_cli_cmd — party-cli binary resolution
# ===========================================================================

echo ""
echo "  === party_resolve_cli_cmd ==="

# When party-cli is on PATH, uses it directly
_orig_path="$PATH"
MOCK_CLI_BIN="/tmp/test-party-cli-$$"
echo '#!/bin/sh' > "$MOCK_CLI_BIN" && chmod +x "$MOCK_CLI_BIN"
PATH="$(dirname "$MOCK_CLI_BIN"):$PATH"

result=$(party_resolve_cli_cmd "party-test-session" "$REPO_ROOT")
assert "resolve_cli: finds binary on PATH" \
  '[[ "$result" == *"party-cli"* ]]'
assert "resolve_cli: uses --session flag" \
  '[[ "$result" == *"--session"* ]]'
assert "resolve_cli: includes session arg" \
  '[[ "$result" == *"party-test-session"* ]]'

rm -f "$MOCK_CLI_BIN"
PATH="$_orig_path"

# When no binary but Go + source available, uses go run
_go_bin="$(command -v go 2>/dev/null || true)"
if [[ -n "$_go_bin" ]] && [[ -f "$REPO_ROOT/tools/party-cli/main.go" ]]; then
  # Temporarily hide party-cli but keep Go accessible
  PATH="$(dirname "$_go_bin"):/usr/bin:/bin"
  result=$(party_resolve_cli_cmd "party-test-session" "$REPO_ROOT")
  assert "resolve_cli: falls back to go run" \
    '[[ "$result" == *"go run"* ]]'
  assert "resolve_cli: go run changes to module dir" \
    '[[ "$result" == *"cd "* && "$result" == *"tools/party-cli"* ]]'
  assert "resolve_cli: go run uses --session flag" \
    '[[ "$result" == *"--session"* ]]'
  PATH="$_orig_path"
fi

# --strict mode returns 1 when no binary available
PATH="/usr/bin:/bin"
if party_resolve_cli_cmd --strict "party-test-session" "/nonexistent" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  [FAIL] resolve_cli: --strict fails when no binary"
else
  PASS=$((PASS + 1))
  echo "  [PASS] resolve_cli: --strict fails when no binary"
fi
PATH="$_orig_path"

# Non-strict mode returns placeholder when no binary available
PATH="/usr/bin:/bin"
result=$(party_resolve_cli_cmd "party-test-session" "/nonexistent" 2>/dev/null)
assert "resolve_cli: non-strict returns placeholder" \
  '[[ "$result" == *"party-cli"* ]]'
PATH="$_orig_path"

# ===========================================================================
# party_promote — sidebar guard
# ===========================================================================

echo ""
echo "  === party_promote sidebar guard ==="

# Mock tmux to simulate a sidebar session
_promote_result=$(
  tmux() {
    case "$1" in
      has-session) return 0 ;;
      show-environment)
        # Simulate PARTY_LAYOUT=sidebar in session env
        echo "PARTY_LAYOUT=sidebar"
        return 0 ;;
      display-message) echo "party-promote-test"; return 0 ;;
      *) return 0 ;;
    esac
  }
  party_promote "party-promote-test" 2>&1
  echo "EXIT:$?"
)
assert "promote: rejects sidebar mode" \
  '[[ "$_promote_result" == *"not yet supported"* ]]'
assert "promote: returns non-zero for sidebar" \
  '[[ "$_promote_result" == *"EXIT:1"* ]]'

# Mock tmux to simulate a classic session (PARTY_LAYOUT unset → guard passes)
_promote_classic=$(
  tmux() {
    case "$1" in
      has-session) return 0 ;;
      show-environment) echo "-PARTY_LAYOUT"; return 0 ;;  # unset marker
      display-message) echo "party-promote-test"; return 0 ;;
      list-panes) echo "0 codex"; return 0 ;;
      list-windows) echo "0"; return 0 ;;
      # respawn-pane etc. will be called — just succeed
      *) return 0 ;;
    esac
  }
  export PARTY_STATE_ROOT="/tmp/party-state-promote-test-$$"
  mkdir -p "$PARTY_STATE_ROOT"
  # Create minimal manifest for party_is_master check
  echo '{"party_id":"party-promote-test"}' > "$PARTY_STATE_ROOT/party-promote-test.json"
  party_promote "party-promote-test" 2>&1
  echo "EXIT:$?"
  rm -rf "$PARTY_STATE_ROOT"
)
assert "promote: classic mode passes guard" \
  '[[ "$_promote_classic" != *"not yet supported"* ]]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
