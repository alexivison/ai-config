#!/usr/bin/env bash
# Tests for codex-trace.sh
# Covers: evidence creation, response format handling, exit code extraction
#
# Usage: bash ~/.claude/hooks/tests/test-codex-trace.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../codex-trace.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION="test-codex-trace-$$"
TMPDIR_BASE=""

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
  rm -f "$(evidence_file "$SESSION")"
  rm -f "/tmp/claude-evidence-${SESSION}.lock"
  rmdir "/tmp/claude-evidence-${SESSION}.lock.d" 2>/dev/null || true
}

full_cleanup() {
  clean_evidence
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_cleanup EXIT

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

has_evidence() {
  local type="$1"
  check_evidence "$SESSION" "$type" "$TMPDIR_BASE"
}

# Helper to build Bash hook input
bash_input_obj() {
  local cmd="$1" stdout="$2" exit_code="${3:-0}"
  jq -cn \
    --arg cmd "$cmd" \
    --arg stdout "$stdout" \
    --argjson ec "$exit_code" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_name:"Bash",tool_input:{command:$cmd},tool_response:{stdout:$stdout,stderr:"",interrupted:false,exit_code:$ec},session_id:$sid,cwd:$cwd}'
}

bash_input_str() {
  local cmd="$1" stdout="$2"
  jq -cn \
    --arg cmd "$cmd" \
    --arg stdout "$stdout" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_name:"Bash",tool_input:{command:$cmd},tool_response:$stdout,session_id:$sid,cwd:$cwd}'
}

# ═══ --review-complete ════════════════════════════════════════════════════════

setup_repo

echo "=== review-complete: Object response format ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Object response → codex-ran evidence created" 'has_evidence "codex-ran"'

echo "=== review-complete: String response format ==="
clean_evidence
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "String response → codex-ran evidence created" 'has_evidence "codex-ran"'

echo "=== review-complete: Full path to tmux-codex.sh ==="
clean_evidence
run_hook "$(bash_input_obj '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Full path → codex-ran evidence created" 'has_evidence "codex-ran"'

echo "=== review-complete: Failed command (exit 1) → no evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete bad' 'Error: file not found' 1)" || true
assert "Exit 1 → no codex-ran evidence" '! has_evidence "codex-ran"'

# ═══ --approve ════════════════════════════════════════════════════════════════

echo "=== approve: With codex-ran present → creates codex evidence ==="
clean_evidence
append_evidence "$SESSION" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Approve with codex-ran → codex evidence created" 'has_evidence "codex"'

echo "=== approve: Without codex-ran → blocked ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Approve without codex-ran → no codex evidence" '! has_evidence "codex"'

echo "=== approve: String response format ==="
clean_evidence
append_evidence "$SESSION" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
run_hook "$(bash_input_str 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "String response → codex evidence created" 'has_evidence "codex"'

# ═══ --plan-review (advisory only) ════════════════════════════════════════════

echo "=== plan-review: Object response does not create evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "Object plan-review → no codex-ran evidence" '! has_evidence "codex-ran"'
assert "Object plan-review → no codex evidence" '! has_evidence "codex"'

echo "=== plan-review: String response does not create evidence ==="
clean_evidence
run_hook "$(bash_input_str 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "String plan-review → no codex-ran evidence" '! has_evidence "codex-ran"'
assert "String plan-review → no codex evidence" '! has_evidence "codex"'

# ═══ Exit code extraction ════════════════════════════════════════════════════

echo "=== Exit code: top-level tool_exit_code ==="
clean_evidence
INPUT=$(jq -cn \
  --arg sid "$SESSION" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN",stderr:""},tool_exit_code:1,session_id:$sid,cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "tool_exit_code=1 → no evidence" '! has_evidence "codex-ran"'

echo "=== Exit code: nested in tool_response ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'Error' 1)" || true
assert "tool_response.exit_code=1 → no evidence" '! has_evidence "codex-ran"'

echo "=== Exit code: string response (no exit_code field) defaults to 0 ==="
clean_evidence
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "String response defaults exit_code=0 → evidence created" 'has_evidence "codex-ran"'

# ═══ Guard clauses ═══════════════════════════════════════════════════════════

echo "=== Guard: Non-tmux command ignored ==="
clean_evidence
run_hook "$(bash_input_obj 'echo CODEX_REVIEW_RAN' 'CODEX_REVIEW_RAN')"
assert "Non-tmux → no evidence" '! has_evidence "codex-ran"'

echo "=== Guard: Invalid JSON fails open ==="
clean_evidence
echo 'not json' | bash "$HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash" 'true'

echo "=== Guard: Missing session_id → no evidence ==="
clean_evidence
INPUT=$(jq -cn \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN",stderr:""},cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "No session_id → no evidence" '! has_evidence "codex-ran"'

# ═══ Full workflow simulation ════════════════════════════════════════════════

echo "=== Workflow: review-complete → approve → success ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 1: codex-ran evidence created" 'has_evidence "codex-ran"'
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Step 2: codex evidence created" 'has_evidence "codex"'

echo "=== Workflow: stale evidence after code edit ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 1: codex-ran created" 'has_evidence "codex-ran"'
# Simulate code edit — changes diff_hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "code edit"
assert "Step 2: codex-ran stale after edit" '! has_evidence "codex-ran"'
# Re-do review
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Step 3: codex-ran recreated" 'has_evidence "codex-ran"'
run_hook "$(bash_input_obj 'tmux-codex.sh --approve /tmp/f.toon' 'CODEX APPROVED')"
assert "Step 4: codex evidence created" 'has_evidence "codex"'

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "codex-trace.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
