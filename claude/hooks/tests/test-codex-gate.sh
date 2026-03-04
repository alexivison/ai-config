#!/usr/bin/env bash
# Tests for codex-gate.sh
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$HOOK_DIR/codex-gate.sh"
PASS=0
FAIL=0
SESSION_ID="test-codex-gate-$$"

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
  rm -f "/tmp/claude-code-critic-$SESSION_ID"
  rm -f "/tmp/claude-minimizer-$SESSION_ID"
  rm -f "/tmp/claude-codex-ran-$SESSION_ID"
}
trap cleanup EXIT

echo "--- test-codex-gate.sh ---"

# Test: gate allows non-tmux-codex commands
OUTPUT=$(echo '{"tool_input":{"command":"ls -la"},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows non-tmux-codex commands" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --review without critic markers
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --review main \"test\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate blocks --review without critic markers" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --review with both critic markers
touch "/tmp/claude-code-critic-$SESSION_ID"
touch "/tmp/claude-minimizer-$SESSION_ID"
OUTPUT=$(echo '{"tool_input":{"command":"~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review main \"test\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows --review with both critic markers" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --approve without codex-ran marker
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --approve"},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate blocks --approve without codex-ran marker" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --approve with codex-ran marker
touch "/tmp/claude-codex-ran-$SESSION_ID"
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --approve"},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows --approve with codex-ran marker" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --prompt without markers
cleanup
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --prompt \"debug this\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows --prompt without markers" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --plan-review without markers
cleanup
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --plan-review PLAN.md /tmp/work"},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows --plan-review without markers" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
