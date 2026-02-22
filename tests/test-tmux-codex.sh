#!/usr/bin/env bash
# Tests for claude/skills/codex-cli/scripts/tmux-codex.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/claude/skills/codex-cli/scripts/tmux-codex.sh"
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
SESSION="party-test-codex-$$"
STATE_DIR="/tmp/$SESSION"
export PARTY_SESSION="$SESSION"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT

mkdir -p "$STATE_DIR"
echo "$SESSION" > "$STATE_DIR/session-name"

# Create tmux session with 2 panes (mock agents are just shells)
tmux new-session -d -s "$SESSION" -n work
tmux split-window -h -t "$SESSION:work"

echo "--- test-tmux-codex.sh ---"

# Test: --review sends message to Codex pane and returns immediately
OUTPUT=$("$SCRIPT" --review main "Test PR" 2>&1)
assert "--review outputs CODEX_REVIEW_REQUESTED" \
  'echo "$OUTPUT" | grep -q "CODEX_REVIEW_REQUESTED"'
assert "--review outputs findings file path" \
  'echo "$OUTPUT" | grep -q "codex-findings-"'

# Test: --review sends to the right pane
sleep 0.5
PANE_CONTENT=$(tmux capture-pane -t "$SESSION:work.1" -p)
assert "--review sends message to Codex pane (pane 1)" \
  'echo "$PANE_CONTENT" | grep -q "Review the changes"'

# Test: --prompt sends message
OUTPUT=$("$SCRIPT" --prompt "Analyze the auth module" 2>&1)
assert "--prompt outputs CODEX_TASK_REQUESTED" \
  'echo "$OUTPUT" | grep -q "CODEX_TASK_REQUESTED"'
assert "--prompt outputs response file path" \
  'echo "$OUTPUT" | grep -q "codex-response-"'

# Test: --review-complete fails without findings file
assert "--review-complete fails without file" \
  '! "$SCRIPT" --review-complete "/tmp/nonexistent-file" 2>/dev/null'

# Test: --review-complete succeeds with findings file
FINDINGS="/tmp/test-findings-$$.json"
echo '{"findings":[],"summary":"ok","stats":{"blocking_count":0}}' > "$FINDINGS"
OUTPUT=$("$SCRIPT" --review-complete "$FINDINGS" 2>&1)
assert "--review-complete emits CODEX_REVIEW_RAN with valid file" \
  'echo "$OUTPUT" | grep -qx "CODEX_REVIEW_RAN"'
rm -f "$FINDINGS"

# Test: --approve outputs sentinel
OUTPUT=$("$SCRIPT" --approve 2>&1)
assert "--approve outputs CODEX APPROVED sentinel" \
  'echo "$OUTPUT" | grep -q "^CODEX APPROVED"'

# Test: --re-review outputs sentinel
OUTPUT=$("$SCRIPT" --re-review "Fixed null check" 2>&1)
assert "--re-review outputs CODEX REQUEST_CHANGES sentinel" \
  'echo "$OUTPUT" | grep -q "^CODEX REQUEST_CHANGES"'

# Test: --needs-discussion outputs sentinel
OUTPUT=$("$SCRIPT" --needs-discussion "Multiple approaches" 2>&1)
assert "--needs-discussion outputs CODEX NEEDS_DISCUSSION sentinel" \
  'echo "$OUTPUT" | grep -q "^CODEX NEEDS_DISCUSSION"'

# Test: unknown mode fails
assert "unknown mode fails" \
  '! "$SCRIPT" --bogus 2>/dev/null'

# Test: verdict modes work without a session (they only emit sentinels)
unset PARTY_SESSION
OUTPUT=$("$SCRIPT" --approve 2>&1)
assert "--approve works without active session" \
  'echo "$OUTPUT" | grep -q "^CODEX APPROVED"'

# Test: transport modes fail without a session
assert "--review fails without active session" \
  '! "$SCRIPT" --review main "test" 2>/dev/null'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
