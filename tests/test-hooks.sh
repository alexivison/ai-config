#!/usr/bin/env bash
# Tests for hook updates (codex-gate.sh, codex-trace.sh)
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

SESSION_ID="test-hooks-$$"

cleanup() {
  rm -f "/tmp/claude-code-critic-$SESSION_ID"
  rm -f "/tmp/claude-minimizer-$SESSION_ID"
  rm -f "/tmp/claude-codex-ran-$SESSION_ID"
  rm -f "/tmp/claude-codex-$SESSION_ID"
}
trap cleanup EXIT

echo "--- test-hooks.sh ---"

# ── codex-gate.sh tests ──

GATE="$REPO_ROOT/claude/hooks/codex-gate.sh"

# Test: gate allows non-tmux-codex commands
OUTPUT=$(echo '{"tool_input":{"command":"ls -la"},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows non-tmux-codex commands" \
  'echo "$OUTPUT" | jq -e ".hookSpecificOutput" 2>/dev/null; [ $? -ne 0 ]'

# Test: gate blocks --review without critic markers
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --review main \"test\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate blocks --review without critic markers" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --review with both critic markers
touch "/tmp/claude-code-critic-$SESSION_ID"
touch "/tmp/claude-minimizer-$SESSION_ID"
OUTPUT=$(echo '{"tool_input":{"command":"~/.claude/skills/codex-cli/scripts/tmux-codex.sh --review main \"test\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
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

# Test: gate allows --prompt without any markers (debugging/architecture)
rm -f "/tmp/claude-code-critic-$SESSION_ID" "/tmp/claude-minimizer-$SESSION_ID" "/tmp/claude-codex-ran-$SESSION_ID"
OUTPUT=$(echo '{"tool_input":{"command":"tmux-codex.sh --prompt \"debug this\""},"session_id":"'"$SESSION_ID"'"}' | bash "$GATE")
assert "gate allows --prompt without markers" \
  '! echo "$OUTPUT" | grep -q "deny"'

# ── codex-trace.sh tests ──

TRACE="$REPO_ROOT/claude/hooks/codex-trace.sh"

# Test: trace ignores non-tmux-codex commands
echo '{"tool_input":{"command":"ls -la"},"tool_response":"ok","tool_exit_code":"0","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "trace ignores non-tmux-codex commands" \
  '[ ! -f "/tmp/claude-codex-ran-$SESSION_ID" ]'

# Test: trace creates codex-ran marker on CODEX_REVIEW_RAN
cleanup
echo '{"tool_input":{"command":"tmux-codex.sh --review-complete /tmp/f.json"},"tool_response":"CODEX_REVIEW_RAN","tool_exit_code":"0","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "trace creates codex-ran marker on CODEX_REVIEW_RAN" \
  '[ -f "/tmp/claude-codex-ran-$SESSION_ID" ]'

# Test: trace creates codex-approved marker on CODEX APPROVED (with codex-ran)
echo '{"tool_input":{"command":"tmux-codex.sh --approve"},"tool_response":"CODEX APPROVED","tool_exit_code":"0","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "trace creates codex-approved marker on CODEX APPROVED" \
  '[ -f "/tmp/claude-codex-$SESSION_ID" ]'

# Test: trace does NOT create codex-approved without codex-ran
cleanup
echo '{"tool_input":{"command":"tmux-codex.sh --approve"},"tool_response":"CODEX APPROVED","tool_exit_code":"0","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "trace blocks approval without codex-ran marker" \
  '[ ! -f "/tmp/claude-codex-$SESSION_ID" ]'

# Test: --re-review deletes codex-ran marker (prevents stale approval)
cleanup
touch "/tmp/claude-codex-ran-$SESSION_ID"
touch "/tmp/claude-codex-$SESSION_ID"
echo '{"tool_input":{"command":"tmux-codex.sh --re-review \"fixed null check\""},"tool_response":"CODEX REQUEST_CHANGES — fixed null check","tool_exit_code":"0","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "--re-review deletes codex-ran marker" \
  '[ ! -f "/tmp/claude-codex-ran-$SESSION_ID" ]'
assert "--re-review deletes codex-approved marker" \
  '[ ! -f "/tmp/claude-codex-$SESSION_ID" ]'

# Test: trace ignores failed commands
cleanup
echo '{"tool_input":{"command":"tmux-codex.sh --review-complete /tmp/f.json"},"tool_response":"CODEX_REVIEW_RAN","tool_exit_code":"1","session_id":"'"$SESSION_ID"'"}' | bash "$TRACE"
assert "trace ignores failed commands (exit code != 0)" \
  '[ ! -f "/tmp/claude-codex-ran-$SESSION_ID" ]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
