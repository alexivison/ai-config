#!/usr/bin/env bash
# Tests for harness hardening fixes:
#   Fix 1: Hook trace logging
#   Fix 2: Stale evidence diagnostics
#   Fix 3: evidence.sh zsh incompatibility guard
#
# Usage: bash ~/.claude/hooks/tests/test-harness-hardening.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION="test-hardening-$$"
TMPDIR_BASE=""

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

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  git checkout -q -b feature
}

cleanup() {
  rm -f "$(evidence_file "$SESSION")"
  rm -f "/tmp/claude-evidence-${SESSION}.lock"
  rm -f "/tmp/claude-worktree-${SESSION}"
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# Fix 1: Hook trace logging
# ═══════════════════════════════════════════════════════════════════════════════

echo "=== Fix 1: hook_log function exists ==="
assert "hook_log function is defined" 'declare -f hook_log >/dev/null 2>&1'

echo "=== Fix 1: hook_log writes to isolated trace file ==="
# Override trace log to a temp file so tests don't pollute or race with production log
TEST_TRACE_LOG=$(mktemp)
_HOOK_TRACE_LOG="$TEST_TRACE_LOG"

hook_log "test-hook" "$SESSION" "allow" "" 2>/dev/null || true
LINES=$(wc -l < "$TEST_TRACE_LOG" | tr -d ' ')
assert "hook_log appends a line to trace log" '[ "$LINES" -eq 1 ]'

echo "=== Fix 1: hook_log entry contains required fields ==="
LAST_LINE=$(tail -1 "$TEST_TRACE_LOG")
assert "Entry contains hook name" 'echo "$LAST_LINE" | grep -q "test-hook"'
assert "Entry contains session ID" 'echo "$LAST_LINE" | grep -q "$SESSION"'
assert "Entry contains outcome" 'echo "$LAST_LINE" | grep -q "allow"'

echo "=== Fix 1: hook_log with error details ==="
hook_log "test-hook" "$SESSION" "error" "bad JSON input" 2>/dev/null || true
LAST_LINE=$(tail -1 "$TEST_TRACE_LOG")
assert "Error entry contains details" 'echo "$LAST_LINE" | grep -q "bad JSON input"'
rm -f "$TEST_TRACE_LOG"
# Restore default
_HOOK_TRACE_LOG="${HOME}/.claude/logs/hook-trace.log"

echo "=== Fix 1: pr-gate.sh calls hook_log ==="
GATE="$SCRIPT_DIR/../pr-gate.sh"
assert "pr-gate.sh contains hook_log call" 'grep -q "hook_log" "$GATE"'

echo "=== Fix 1: companion-gate.sh calls hook_log ==="
COMPANION_GATE="$SCRIPT_DIR/../companion-gate.sh"
assert "companion-gate.sh contains hook_log call" 'grep -q "hook_log" "$COMPANION_GATE"'

echo "=== Fix 1: agent-trace-stop.sh calls hook_log ==="
AGENT_TRACE="$SCRIPT_DIR/../agent-trace-stop.sh"
assert "agent-trace-stop.sh contains hook_log call" 'grep -q "hook_log" "$AGENT_TRACE"'

echo "=== Fix 1: worktree-track.sh calls hook_log ==="
WT_TRACK="$SCRIPT_DIR/../worktree-track.sh"
assert "worktree-track.sh contains hook_log call" 'grep -q "hook_log" "$WT_TRACK"'

echo "=== Fix 1: worktree-guard.sh calls hook_log ==="
WT_GUARD="$SCRIPT_DIR/../worktree-guard.sh"
assert "worktree-guard.sh contains hook_log call" 'grep -q "hook_log" "$WT_GUARD"'

# ═══════════════════════════════════════════════════════════════════════════════
# Fix 2: Stale evidence diagnostics
# ═══════════════════════════════════════════════════════════════════════════════

echo "=== Fix 2: stale evidence shows hash diagnostic ==="
cleanup
setup_repo
echo "impl" > impl.sh
git add impl.sh && git commit -q -m "add impl"
# Create evidence at current hash
append_evidence "$SESSION" "code-critic" "APPROVED" "$TMPDIR_BASE"
HASH_OLD=$(compute_diff_hash "$TMPDIR_BASE")
# Change the code → stale hash
echo "changed" >> impl.sh
git add impl.sh && git commit -q -m "change impl"
HASH_NEW=$(compute_diff_hash "$TMPDIR_BASE")
# check_all_evidence should mention the stale hash
OUTPUT=$(check_all_evidence "$SESSION" "code-critic" "$TMPDIR_BASE" 2>&1 || true)
assert "Stale diagnostic mentions existing hash" 'echo "$OUTPUT" | grep -q "stale\|exists at"'

echo "=== Fix 2: APPROVED@A then REQUEST_CHANGES@B suppresses stale hint ==="
cleanup
setup_repo
echo "impl_rc" > impl_rc.sh
git add impl_rc.sh && git commit -q -m "add impl_rc"
# Critic approves at hash A
append_evidence "$SESSION" "code-critic" "APPROVED" "$TMPDIR_BASE"
# Change code → hash B
echo "changed_rc" >> impl_rc.sh
git add impl_rc.sh && git commit -q -m "change impl_rc"
# Critic re-runs at hash B with REQUEST_CHANGES (via -run tracking)
append_evidence "$SESSION" "code-critic-run" "REQUEST_CHANGES" "$TMPDIR_BASE"
# check_all_evidence should NOT emit stale hint — critic already ran at current hash
OUTPUT=$(check_all_evidence "$SESSION" "code-critic" "$TMPDIR_BASE" 2>&1 || true)
assert "RC at current hash: no stale hint" '! echo "$OUTPUT" | grep -q "stale\|exists at"'

echo "=== Fix 2: missing evidence (never ran) shows no hash diagnostic ==="
cleanup
setup_repo
echo "impl2" > impl2.sh
git add impl2.sh && git commit -q -m "add impl2"
# No evidence at all for minimizer
OUTPUT=$(check_all_evidence "$SESSION" "minimizer" "$TMPDIR_BASE" 2>&1 || true)
assert "Never-ran evidence has no stale diagnostic" '! echo "$OUTPUT" | grep -q "stale\|exists at"'

echo "=== Fix 2: pr-gate deny message includes stale diagnostic ==="
cleanup
setup_repo
echo "impl3" > impl3.sh
git add impl3.sh && git commit -q -m "add impl3"
# Create all evidence at current hash
for type in pr-verified code-critic minimizer codex test-runner check-runner; do
  append_evidence "$SESSION" "$type" "PASS" "$TMPDIR_BASE"
done
# Change code → all evidence stale
echo "changed3" >> impl3.sh
git add impl3.sh && git commit -q -m "change impl3"
GATE_INPUT=$(jq -cn \
  --arg sid "$SESSION" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_input:{command:"gh pr create --title test"},session_id:$sid,cwd:$cwd}')
OUTPUT=$(echo "$GATE_INPUT" | bash "$SCRIPT_DIR/../pr-gate.sh")
assert "PR gate deny includes stale hash info" 'echo "$OUTPUT" | grep -q "stale\|exists at"'

# ═══════════════════════════════════════════════════════════════════════════════
# Fix 3: evidence.sh zsh incompatibility guard
# ═══════════════════════════════════════════════════════════════════════════════

echo "=== Fix 3: evidence.sh has bash guard ==="
EVIDENCE_SH="$SCRIPT_DIR/../lib/evidence.sh"
assert "evidence.sh checks BASH_VERSION" 'grep -q "BASH_VERSION" "$EVIDENCE_SH"'

echo "=== Fix 3: sourcing from non-bash emits clear error ==="
# Simulate non-bash by running evidence.sh with BASH_VERSION unset
OUTPUT=$(env -u BASH_VERSION bash -c '
  unset BASH_VERSION
  source "'"$EVIDENCE_SH"'" 2>&1
' 2>&1) || true
assert "Non-bash source produces error message" 'echo "$OUTPUT" | grep -qi "bash\|zsh\|incompatible\|must be sourced"'

echo "=== Fix 3: _atomic_append flock syntax is zsh-safe ==="
# The problematic pattern is: ) 200>"$file"  (bare fd redirect outside subshell)
# Check that this pattern does NOT exist
assert "No bare fd redirect pattern (200>)" '! grep -qE "\) *[0-9]+>" "$EVIDENCE_SH"'

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "harness-hardening: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
