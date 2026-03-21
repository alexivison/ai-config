#!/usr/bin/env bash
# Tests for codex-trace.sh
# Single-phase model: codex evidence created directly from CODEX APPROVED + CODEX_REVIEW_RAN.
# No codex-ran intermediate evidence.
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

# ═══ --review-complete with APPROVED verdict ═════════════════════════════════

setup_repo

echo "=== review-complete: APPROVED creates codex evidence directly (object response) ==="
clean_evidence
COMBINED_STDOUT=$'CODEX_REVIEW_RAN\nCODEX APPROVED'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "APPROVED → codex evidence created" 'has_evidence "codex"'

echo "=== review-complete: APPROVED creates codex evidence (string response) ==="
clean_evidence
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "String APPROVED → codex evidence created" 'has_evidence "codex"'

echo "=== review-complete: APPROVED via full path ==="
clean_evidence
run_hook "$(bash_input_obj '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "Full path APPROVED → codex evidence created" 'has_evidence "codex"'

# ═══ --review-complete with REQUEST_CHANGES ═══════════════════════════════════

echo "=== review-complete: REQUEST_CHANGES → no codex evidence ==="
clean_evidence
RC_STDOUT=$'CODEX_REVIEW_RAN\nCODEX REQUEST_CHANGES'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$RC_STDOUT")"
assert "REQUEST_CHANGES → no codex evidence" '! has_evidence "codex"'

# ═══ --review-complete without CODEX_REVIEW_RAN sentinel ═════════════════════

echo "=== review-complete: CODEX APPROVED without CODEX_REVIEW_RAN → no evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX APPROVED')"
assert "APPROVED without review-ran sentinel → no codex evidence" '! has_evidence "codex"'

echo "=== review-complete: CODEX_REVIEW_RAN alone → no codex evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Review-ran alone → no codex evidence" '! has_evidence "codex"'

# ═══ --plan-review (advisory only) ════════════════════════════════════════════

echo "=== plan-review: does not create evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "Plan-review → no codex evidence" '! has_evidence "codex"'

# ═══ Exit code extraction ════════════════════════════════════════════════════

echo "=== Exit code: top-level tool_exit_code ==="
clean_evidence
INPUT=$(jq -cn \
  --arg sid "$SESSION" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN\nCODEX APPROVED",stderr:""},tool_exit_code:1,session_id:$sid,cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "tool_exit_code=1 → no evidence" '! has_evidence "codex"'

echo "=== Exit code: nested in tool_response ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'Error' 1)" || true
assert "tool_response.exit_code=1 → no evidence" '! has_evidence "codex"'

# ═══ Guard clauses ═══════════════════════════════════════════════════════════

echo "=== Guard: Non-tmux command ignored ==="
clean_evidence
run_hook "$(bash_input_obj 'echo CODEX_REVIEW_RAN' "$COMBINED_STDOUT")"
assert "Non-tmux → no evidence" '! has_evidence "codex"'

echo "=== Guard: Invalid JSON fails open ==="
clean_evidence
echo 'not json' | bash "$HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash" 'true'

echo "=== Guard: Missing session_id → no evidence ==="
clean_evidence
INPUT=$(jq -cn \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN\nCODEX APPROVED",stderr:""},cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "No session_id → no evidence" '! has_evidence "codex"'

# ═══ Full workflow simulation ════════════════════════════════════════════════

echo "=== Workflow: APPROVED verdict → codex evidence ==="
clean_evidence
APPROVED_STDOUT=$'CODEX_REVIEW_RAN\nCODEX APPROVED'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Workflow: codex evidence created" 'has_evidence "codex"'

echo "=== Workflow: stale evidence after code edit ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Step 1: codex evidence created" 'has_evidence "codex"'
# Simulate code edit — changes diff_hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "code edit"
assert "Step 2: codex stale after edit" '! has_evidence "codex"'
# Re-do review with approval
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Step 3: codex recreated" 'has_evidence "codex"'

# ═══ --triage-override ════════════════════════════════════════════════════════

echo "=== triage-override: valid type with prior critic run ==="
clean_evidence
# Critic must have run first
append_evidence "$SESSION" "code-critic" "REQUEST_CHANGES" "$TMPDIR_BASE"
OVERRIDE_STDOUT='TRIAGE_OVERRIDE code-critic | Out-of-scope: rebased auth files'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override code-critic "Out-of-scope: rebased auth files"' "$OVERRIDE_STDOUT")"
assert "Valid triage override → code-critic evidence" 'has_evidence "code-critic"'

echo "=== triage-override: rejected without prior critic run ==="
clean_evidence
OVERRIDE_STDOUT2='TRIAGE_OVERRIDE code-critic | No critic ran'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override code-critic "No critic ran"' "$OVERRIDE_STDOUT2")"
assert "No prior critic → no evidence" '! has_evidence "code-critic"'

echo "=== triage-override: invalid type rejected ==="
clean_evidence
OVERRIDE_BAD='TRIAGE_OVERRIDE codex | Trying to bypass'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override codex "Trying to bypass"' "$OVERRIDE_BAD")"
assert "Invalid type → no codex evidence" '! has_evidence "codex"'

echo "=== triage-override: combined with CODEX_REVIEW_RAN ==="
clean_evidence
# Critic must have run first
append_evidence "$SESSION" "minimizer" "REQUEST_CHANGES" "$TMPDIR_BASE"
COMBINED_OVERRIDE=$'CODEX_REVIEW_RAN\nTRIAGE_OVERRIDE minimizer | Rebased code from PR #65315'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_OVERRIDE")"
assert "Combined → minimizer override evidence" 'has_evidence "minimizer"'

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "codex-trace.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
