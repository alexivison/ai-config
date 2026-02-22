#!/usr/bin/env bash
# Tests for codex/skills/claude-cli/scripts/tmux-claude.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/codex/skills/claude-cli/scripts/tmux-claude.sh"
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

# Setup: create a mock party session with tmux (party- prefix required)
SESSION="party-test-claude-$$"
STATE_DIR="/tmp/$SESSION"
export PARTY_SESSION="$SESSION"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT

mkdir -p "$STATE_DIR"
echo "$SESSION" > "$STATE_DIR/session-name"

# Create tmux session with 2 panes
tmux new-session -d -s "$SESSION" -n work
tmux split-window -h -t "$SESSION:work"

echo "--- test-tmux-claude.sh ---"

# Test: sends [CODEX] prefixed message to Claude pane
OUTPUT=$("$SCRIPT" "Review complete. Findings at: /tmp/test.json" 2>&1)
assert "outputs CLAUDE_MESSAGE_SENT" \
  'echo "$OUTPUT" | grep -q "CLAUDE_MESSAGE_SENT"'

# Test: message appears in Claude pane (pane 0)
sleep 0.3
PANE_CONTENT=$(tmux capture-pane -t "$SESSION:work.0" -p)
assert "message sent to Claude pane with [CODEX] prefix" \
  'echo "$PANE_CONTENT" | grep -q "\[CODEX\]"'

# Test: no session fails gracefully
unset PARTY_SESSION
assert "fails gracefully with no active session" \
  '! "$SCRIPT" "test message" 2>/dev/null'

# Test: no message fails
assert "fails with no message argument" \
  '! "$SCRIPT" 2>/dev/null'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
