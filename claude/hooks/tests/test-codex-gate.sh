#!/usr/bin/env bash
# Tests for codex-gate.sh
# Uses JSONL evidence instead of marker files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../codex-gate.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION_ID="test-codex-gate-$$"
TMPDIR_BASE=""

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

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  git checkout -q -b feature
  echo "impl" > impl.sh
  git add impl.sh
  git commit -q -m "add impl"
}

clean_evidence() {
  rm -f "$(evidence_file "$SESSION_ID")"
  rm -f "/tmp/claude-evidence-${SESSION_ID}.lock"
  rmdir "/tmp/claude-evidence-${SESSION_ID}.lock.d" 2>/dev/null || true
}

full_cleanup() {
  clean_evidence
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_cleanup EXIT

gate_input() {
  local cmd="$1"
  jq -cn \
    --arg cmd "$cmd" \
    --arg sid "$SESSION_ID" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_input:{command:$cmd},session_id:$sid,cwd:$cwd}'
}

setup_repo

echo "--- test-codex-gate.sh ---"

# Test: gate allows non-tmux-codex commands
OUTPUT=$(echo "$(gate_input 'ls -la')" | bash "$GATE")
assert "gate allows non-tmux-codex commands" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --review without critic evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "gate blocks --review without critic evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --review with both critic evidence
clean_evidence
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "gate allows --review with both critic evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --approve without codex-ran evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --approve')" | bash "$GATE")
assert "gate blocks --approve without codex-ran evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --approve with codex-ran evidence
clean_evidence
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --approve')" | bash "$GATE")
assert "gate allows --approve with codex-ran evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --prompt without evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --prompt "debug this"')" | bash "$GATE")
assert "gate allows --prompt without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --plan-review without evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --plan-review PLAN.md /tmp/work')" | bash "$GATE")
assert "gate allows --plan-review without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: stale evidence rejected after code edit
clean_evidence
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
# Change the diff hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "stale test"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "stale evidence rejected after code edit" \
  'echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
