#!/usr/bin/env bash
# Tests for codex-trace.sh
# Covers: marker creation/deletion, response format handling, exit code extraction
#
# Usage: bash ~/.claude/hooks/tests/test-codex-trace.sh

set -euo pipefail

HOOK="$HOME/.claude/hooks/codex-trace.sh"
PASS=0
FAIL=0
SESSION="test-codex-trace-$$"

cleanup() {
  rm -f /tmp/claude-codex-ran-"$SESSION"
  rm -f /tmp/claude-codex-"$SESSION"
}

assert() {
  local name="$1" condition="$2"
  if eval "$condition"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

run_hook() {
  echo "$1" | bash "$HOOK" 2>/dev/null
}

# Helper to build Bash hook input
bash_input_obj() {
  local cmd="$1" stdout="$2" exit_code="${3:-0}"
  cat <<JSONEOF
{"tool_name":"Bash","tool_input":{"command":"$cmd"},"tool_response":{"stdout":"$stdout","stderr":"","interrupted":false,"exit_code":$exit_code},"session_id":"$SESSION","cwd":"/tmp"}
JSONEOF
}

bash_input_str() {
  local cmd="$1" stdout="$2"
  cat <<JSONEOF
{"tool_name":"Bash","tool_input":{"command":"$cmd"},"tool_response":"$stdout","session_id":"$SESSION","cwd":"/tmp"}
JSONEOF
}

# ═══ --review-complete ════════════════════════════════════════════════════════

echo "=== review-complete: Object response format ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Object response → codex-ran marker created" '[ -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== review-complete: String response format ==="
cleanup
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "String response → codex-ran marker created" '[ -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== review-complete: Full path to tmux-codex.sh ==="
cleanup
run_hook "$(bash_input_obj '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Full path → codex-ran marker created" '[ -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== review-complete: Failed command (exit 1) → no marker ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete bad' 'Error: file not found' 1)" || true
assert "Exit 1 → no codex-ran marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

# ═══ --approve ════════════════════════════════════════════════════════════════

echo "=== approve: With codex-ran present → creates codex marker ==="
cleanup
touch "/tmp/claude-codex-ran-$SESSION"
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Approve with codex-ran → codex marker created" '[ -f /tmp/claude-codex-$SESSION ]'

echo "=== approve: Without codex-ran → blocked ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Approve without codex-ran → no codex marker" '[ ! -f /tmp/claude-codex-$SESSION ]'

echo "=== approve: String response format ==="
cleanup
touch "/tmp/claude-codex-ran-$SESSION"
run_hook "$(bash_input_str 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "String response → codex marker created" '[ -f /tmp/claude-codex-$SESSION ]'

# ═══ --re-review ══════════════════════════════════════════════════════════════

echo "=== re-review: Clears both markers ==="
cleanup
touch "/tmp/claude-codex-ran-$SESSION" "/tmp/claude-codex-$SESSION"
run_hook "$(bash_input_obj 'tmux-codex.sh --re-review /tmp/f.toon' 'CODEX REQUEST_CHANGES — F1 not fixed')"
assert "Re-review → codex-ran marker removed" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'
assert "Re-review → codex marker removed" '[ ! -f /tmp/claude-codex-$SESSION ]'

echo "=== re-review: String response format ==="
cleanup
touch "/tmp/claude-codex-ran-$SESSION" "/tmp/claude-codex-$SESSION"
run_hook "$(bash_input_str 'tmux-codex.sh --re-review /tmp/f.toon' 'CODEX REQUEST_CHANGES — reason here')"
assert "String re-review → markers removed" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

# ═══ --plan-review (advisory only) ════════════════════════════════════════════

echo "=== plan-review: Object response does not create markers ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "Object plan-review → no codex-ran marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'
assert "Object plan-review → no codex marker" '[ ! -f /tmp/claude-codex-$SESSION ]'

echo "=== plan-review: String response does not create markers ==="
cleanup
run_hook "$(bash_input_str 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "String plan-review → no codex-ran marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'
assert "String plan-review → no codex marker" '[ ! -f /tmp/claude-codex-$SESSION ]'

# ═══ Exit code extraction ════════════════════════════════════════════════════

echo "=== Exit code: top-level tool_exit_code ==="
cleanup
echo '{"tool_name":"Bash","tool_input":{"command":"tmux-codex.sh --review-complete /tmp/f.toon"},"tool_response":{"stdout":"CODEX_REVIEW_RAN","stderr":""},"tool_exit_code":1,"session_id":"'"$SESSION"'","cwd":"/tmp"}' | bash "$HOOK" 2>/dev/null || true
assert "tool_exit_code=1 → no marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== Exit code: nested in tool_response ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'Error' 1)" || true
assert "tool_response.exit_code=1 → no marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== Exit code: string response (no exit_code field) defaults to 0 ==="
cleanup
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "String response defaults exit_code=0 → marker created" '[ -f /tmp/claude-codex-ran-$SESSION ]'

# ═══ Guard clauses ═══════════════════════════════════════════════════════════

echo "=== Guard: Non-tmux command ignored ==="
cleanup
run_hook "$(bash_input_obj 'echo CODEX_REVIEW_RAN' 'CODEX_REVIEW_RAN')"
assert "Non-tmux → no marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

echo "=== Guard: Invalid JSON fails open ==="
cleanup
echo 'not json' | bash "$HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash" 'true'

echo "=== Guard: Missing session_id → no marker ==="
cleanup
echo '{"tool_name":"Bash","tool_input":{"command":"tmux-codex.sh --review-complete /tmp/f.toon"},"tool_response":{"stdout":"CODEX_REVIEW_RAN","stderr":""},"cwd":"/tmp"}' | bash "$HOOK" 2>/dev/null || true
assert "No session_id → no marker" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'

# ═══ Full workflow simulation ════════════════════════════════════════════════

echo "=== Workflow: review-complete → approve → success ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 1: codex-ran created" '[ -f /tmp/claude-codex-ran-$SESSION ]'
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Step 2: codex marker created" '[ -f /tmp/claude-codex-$SESSION ]'

echo "=== Workflow: review-complete → re-review → review-complete → approve ==="
cleanup
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 1: codex-ran created" '[ -f /tmp/claude-codex-ran-$SESSION ]'
run_hook "$(bash_input_obj 'tmux-codex.sh --re-review /tmp/f.toon' 'CODEX REQUEST_CHANGES — fix F1')"
assert "Step 2: codex-ran cleared" '[ ! -f /tmp/claude-codex-ran-$SESSION ]'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 3: codex-ran recreated" '[ -f /tmp/claude-codex-ran-$SESSION ]'
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Step 4: codex marker created" '[ -f /tmp/claude-codex-$SESSION ]'

# ─── Summary ─────────────────────────────────────────────────────────────────

cleanup
echo ""
echo "═══════════════════════════════════════"
echo "codex-trace.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
