#!/usr/bin/env bash
# Tests for primary-state.sh — event-to-state mapping and file output.
# Runtime artifact name remains claude-state.json in v1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../primary-state.sh"

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

setup() {
  SESSION_NAME="party-test-state-$$"
  STATE_DIR="/tmp/$SESSION_NAME"
  mkdir -p "$STATE_DIR"
}

cleanup() {
  rm -rf "$STATE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

hook_input() {
  local event="$1"
  jq -cn --arg ev "$event" '{hook_event_name: $ev, session_id: "test-session"}'
}

# Override discover_session and tmux for testing
export PARTY_SESSION=""

echo "--- test-claude-state.sh ---"

setup

# ─── Test: PreToolUse maps to active ──────────────────────────────
rm -f "$STATE_DIR/claude-state.json"
export PARTY_SESSION="$SESSION_NAME"
export MOCK_TMUX=1

OUTPUT=$(echo "$(hook_input 'PreToolUse')" | \
  PARTY_SESSION="$SESSION_NAME" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

# Hook must output {}
assert "PreToolUse outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'

# Check state file was written
if [[ -f "$STATE_DIR/claude-state.json" ]]; then
  STATE=$(jq -r '.state' "$STATE_DIR/claude-state.json")
  assert "PreToolUse → state=active" '[[ "$STATE" == "active" ]]'

  UPDATED=$(jq -r '.updated_at' "$STATE_DIR/claude-state.json")
  assert "PreToolUse → updated_at is set" '[[ -n "$UPDATED" ]]'
else
  assert "PreToolUse writes claude-state.json" 'false'
  assert "PreToolUse → state=active (skipped)" 'false'
fi

# ─── Test: Stop maps to idle ─────────────────────────────────────
rm -f "$STATE_DIR/claude-state.json"

OUTPUT=$(echo "$(hook_input 'Stop')" | \
  PARTY_SESSION="$SESSION_NAME" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

assert "Stop outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'

if [[ -f "$STATE_DIR/claude-state.json" ]]; then
  STATE=$(jq -r '.state' "$STATE_DIR/claude-state.json")
  assert "Stop → state=idle" '[[ "$STATE" == "idle" ]]'
else
  assert "Stop writes claude-state.json" 'false'
fi

# ─── Test: PermissionRequest maps to waiting ─────────────────────
rm -f "$STATE_DIR/claude-state.json"

OUTPUT=$(echo "$(hook_input 'PermissionRequest')" | \
  PARTY_SESSION="$SESSION_NAME" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

assert "PermissionRequest outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'

if [[ -f "$STATE_DIR/claude-state.json" ]]; then
  STATE=$(jq -r '.state' "$STATE_DIR/claude-state.json")
  assert "PermissionRequest → state=waiting" '[[ "$STATE" == "waiting" ]]'
else
  assert "PermissionRequest writes claude-state.json" 'false'
fi

# ─── Test: SessionEnd maps to done ──────────────────────────────
rm -f "$STATE_DIR/claude-state.json"

OUTPUT=$(echo "$(hook_input 'SessionEnd')" | \
  PARTY_SESSION="$SESSION_NAME" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

assert "SessionEnd outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'

if [[ -f "$STATE_DIR/claude-state.json" ]]; then
  STATE=$(jq -r '.state' "$STATE_DIR/claude-state.json")
  assert "SessionEnd → state=done" '[[ "$STATE" == "done" ]]'
else
  assert "SessionEnd writes claude-state.json" 'false'
fi

# ─── Test: Unknown event exits silently ──────────────────────────
rm -f "$STATE_DIR/claude-state.json"

OUTPUT=$(echo "$(hook_input 'UnknownEvent')" | \
  PARTY_SESSION="$SESSION_NAME" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

assert "Unknown event outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'
assert "Unknown event does not write state file" \
  '[[ ! -f "$STATE_DIR/claude-state.json" ]]'

# ─── Test: Non-party session exits silently ──────────────────────
rm -f "$STATE_DIR/claude-state.json"

OUTPUT=$(echo "$(hook_input 'PreToolUse')" | \
  PARTY_SESSION="" \
  MOCK_TMUX=1 \
  bash "$HOOK" 2>/dev/null || true)

assert "Non-party session outputs {}" \
  'echo "$OUTPUT" | grep -qF "{}"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
