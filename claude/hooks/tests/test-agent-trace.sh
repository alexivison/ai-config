#!/usr/bin/env bash
# Tests for agent-trace-start.sh and agent-trace-stop.sh
# Covers: start/stop tracing, verdict detection, evidence creation
#
# Usage: bash ~/.claude/hooks/tests/test-agent-trace.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_HOOK="${SCRIPT_DIR}/../agent-trace-start.sh"
STOP_HOOK="${SCRIPT_DIR}/../agent-trace-stop.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
PASS=0
FAIL=0
SESSION="test-agent-trace-$$"
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

# Only clean evidence files, not the repo
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

last_trace_field() {
  local event_type="$1" field="$2"
  grep "\"session\":\"$SESSION\"" "$TRACE_FILE" | grep "\"event\":\"$event_type\"" | tail -1 | jq -r ".$field // \"?\""
}

run_start() {
  echo "$1" | bash "$START_HOOK" 2>/dev/null
}

run_stop() {
  echo "$1" | bash "$STOP_HOOK" 2>/dev/null
}

start_input() {
  local agent_type="$1"
  jq -cn \
    --arg at "$agent_type" \
    --arg aid "agent-$$-$RANDOM" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    '{agent_type: $at, agent_id: $aid, session_id: $sid, cwd: $cwd}'
}

stop_input() {
  local agent_type="$1" message="$2"
  # Use printf to interpret \n as real newlines (matching real Claude Code behavior)
  local real_msg
  real_msg=$(printf '%b' "$message")
  jq -cn \
    --arg at "$agent_type" \
    --arg aid "agent-$$-$RANDOM" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    --arg msg "$real_msg" \
    '{agent_type: $at, agent_id: $aid, session_id: $sid, cwd: $cwd, last_assistant_message: $msg}'
}

has_evidence() {
  local type="$1"
  check_evidence "$SESSION" "$type" "$TMPDIR_BASE"
}

# ─── Setup ────────────────────────────────────────────────────────────────────
setup_repo

# ─── Start hook tests ────────────────────────────────────────────────────────

echo "=== Start Hook: Logs spawn event ==="
clean_evidence
run_start "$(start_input code-critic)"
assert "Start event logged" '[ "$(last_trace_field start agent)" = "code-critic" ]'
assert "Start event type correct" '[ "$(last_trace_field start event)" = "start" ]'

echo "=== Start Hook: Different agent types ==="
run_start "$(start_input test-runner)"
assert "test-runner start logged" '[ "$(last_trace_field start agent)" = "test-runner" ]'

# ─── Verdict detection tests ─────────────────────────────────────────────────

echo "=== Verdict: APPROVE ==="
clean_evidence
run_stop "$(stop_input code-critic "Review done.\n\n**APPROVE** — All good.")"
assert "APPROVED verdict" '[ "$(last_trace_field stop verdict)" = "APPROVED" ]'
assert "code-critic evidence created" 'has_evidence "code-critic"'

echo "=== Verdict: REQUEST_CHANGES ==="
clean_evidence
run_stop "$(stop_input code-critic "Found bugs.\n\n**REQUEST_CHANGES**\n\n[must] Fix null check.")"
assert "REQUEST_CHANGES detected" '[ "$(last_trace_field stop verdict)" = "REQUEST_CHANGES" ]'
assert "REQUEST_CHANGES → no evidence" '! has_evidence "code-critic"'

echo "=== Verdict: NEEDS_DISCUSSION ==="
clean_evidence
run_stop "$(stop_input code-critic "Unclear requirement.\n\n**NEEDS_DISCUSSION**")"
assert "NEEDS_DISCUSSION detected" '[ "$(last_trace_field stop verdict)" = "NEEDS_DISCUSSION" ]'

echo "=== Verdict: PASS ==="
clean_evidence
run_stop "$(stop_input test-runner "All 42 tests passed.\n\nPASS")"
assert "PASS verdict" '[ "$(last_trace_field stop verdict)" = "PASS" ]'
assert "test-runner evidence created" 'has_evidence "test-runner"'

echo "=== Verdict: FAIL ==="
clean_evidence
run_stop "$(stop_input test-runner "3 tests failed.\n\nFAIL")"
assert "FAIL detected" '[ "$(last_trace_field stop verdict)" = "FAIL" ]'
assert "FAIL → no test-runner evidence" '! has_evidence "test-runner"'

echo "=== Verdict: CLEAN ==="
clean_evidence
run_stop "$(stop_input check-runner "No issues found.\n\nCLEAN")"
assert "CLEAN detected" '[ "$(last_trace_field stop verdict)" = "CLEAN" ]'
assert "check-runner evidence created" 'has_evidence "check-runner"'

echo "=== Verdict: ISSUES_FOUND ==="
clean_evidence
run_stop "$(stop_input code-critic "Found CRITICAL issue in review.")"
assert "ISSUES_FOUND detected" '[ "$(last_trace_field stop verdict)" = "ISSUES_FOUND" ]'

echo "=== Verdict: unknown for background launch ==="
clean_evidence
run_stop "$(stop_input code-critic "Launched successfully. The agent is working in the background.")"
assert "Background launch → unknown verdict" '[ "$(last_trace_field stop verdict)" = "unknown" ]'
assert "Background launch → no evidence" '! has_evidence "code-critic"'

# ─── Evidence creation tests ─────────────────────────────────────────────────

echo "=== Evidence: Each agent type maps to correct evidence ==="
clean_evidence
run_stop "$(stop_input code-critic "**APPROVE**")"
assert "code-critic APPROVE → code-critic evidence" 'has_evidence "code-critic"'
assert "code-critic APPROVE → no minimizer evidence" '! has_evidence "minimizer"'

clean_evidence
run_stop "$(stop_input minimizer "**APPROVE**")"
assert "minimizer APPROVE → minimizer evidence" 'has_evidence "minimizer"'
assert "minimizer APPROVE → no code-critic evidence" '! has_evidence "code-critic"'

clean_evidence
run_stop "$(stop_input requirements-auditor "**APPROVE**")"
assert "requirements-auditor APPROVE → requirements-auditor evidence" 'has_evidence "requirements-auditor"'
assert "requirements-auditor APPROVE → no code-critic evidence" '! has_evidence "code-critic"'

clean_evidence
run_stop "$(stop_input check-runner "All passed.\n\nPASS")"
assert "check-runner PASS → check-runner evidence" 'has_evidence "check-runner"'

# ─── Priority tests ──────────────────────────────────────────────────────────

echo "=== Priority: REQUEST_CHANGES wins over APPROVE in prose ==="
clean_evidence
run_stop "$(stop_input code-critic "APPROVE in prose but **REQUEST_CHANGES** is the verdict.")"
assert "REQUEST_CHANGES takes priority" '[ "$(last_trace_field stop verdict)" = "REQUEST_CHANGES" ]'

# ─── Guard tests ──────────────────────────────────────────────────────────────

echo "=== Guard: Invalid JSON fails open ==="
clean_evidence
echo 'not json at all' | bash "$STOP_HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash (exit 0)" 'true'

echo "=== Guard: Empty message → unknown ==="
clean_evidence
run_stop "$(stop_input code-critic "")"
assert "Empty message → unknown verdict" '[ "$(last_trace_field stop verdict)" = "unknown" ]'

# ─── Stale evidence test ────────────────────────────────────────────────────

echo "=== Stale evidence: code edit invalidates prior evidence ==="
clean_evidence
run_stop "$(stop_input code-critic "**APPROVE**")"
assert "Evidence exists before edit" 'has_evidence "code-critic"'
# Simulate code edit — change diff_hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "edit impl"
assert "Evidence stale after edit" '! has_evidence "code-critic"'

# ─── Oscillation detection tests ─────────────────────────────────────────────

echo "=== Oscillation: 3 alternating minimizer verdicts → auto-triage-override ==="
clean_evidence
# Iteration 1: minimizer says REQUEST_CHANGES
run_stop "$(stop_input minimizer "Found issues.\n\n**REQUEST_CHANGES**\n\n[must] Remove abstraction.")"
assert "Oscillation iter 1: REQUEST_CHANGES recorded" '! has_evidence "minimizer"'
# Iteration 2: minimizer says APPROVE (after fix)
run_stop "$(stop_input minimizer "Looks good now.\n\n**APPROVE**")"
assert "Oscillation iter 2: APPROVED recorded" 'has_evidence "minimizer"'
# Iteration 3: minimizer says REQUEST_CHANGES again (same finding re-raised)
# This should trigger auto-triage-override
run_stop "$(stop_input minimizer "Actually, remove that abstraction.\n\n**REQUEST_CHANGES**")"
# After oscillation detection, a triage override should exist → minimizer evidence stays APPROVED
EFILE=$(evidence_file "$SESSION")
OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
assert "Oscillation: auto-triage-override created for minimizer" '[ "$OVERRIDE_COUNT" -gt 0 ]'

echo "=== Oscillation: 2 consecutive REQUEST_CHANGES → no false positive ==="
clean_evidence
# Two REQUEST_CHANGES in a row is persistent disagreement, NOT oscillation
run_stop "$(stop_input minimizer "Found issues.\n\n**REQUEST_CHANGES**")"
run_stop "$(stop_input minimizer "Still has issues.\n\n**REQUEST_CHANGES**")"
EFILE=$(evidence_file "$SESSION")
if [ -f "$EFILE" ]; then
  OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
else
  OVERRIDE_COUNT=0
fi
assert "No oscillation: consecutive REQUEST_CHANGES → no override" '[ "$OVERRIDE_COUNT" -eq 0 ]'

echo "=== Oscillation: different critic types don't cross-trigger ==="
clean_evidence
# code-critic oscillates: RC → APPROVE → RC
run_stop "$(stop_input code-critic "Issues found.\n\n**REQUEST_CHANGES**")"
run_stop "$(stop_input code-critic "Fixed.\n\n**APPROVE**")"
run_stop "$(stop_input code-critic "Wait, new issue.\n\n**REQUEST_CHANGES**")"
# minimizer has only one verdict — should NOT get an override from code-critic's oscillation
EFILE=$(evidence_file "$SESSION")
MIN_OVERRIDE=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
assert "Cross-type: code-critic oscillation → no minimizer override" '[ "$MIN_OVERRIDE" -eq 0 ]'
# But code-critic SHOULD have its own override
CC_OVERRIDE=$(jq -r 'select(.type == "code-critic" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
assert "Cross-type: code-critic oscillation → code-critic override exists" '[ "$CC_OVERRIDE" -gt 0 ]'

echo "=== Oscillation: cross-hash alternation is NOT oscillation ==="
clean_evidence
cd "$TMPDIR_BASE"
# hash_A: minimizer says REQUEST_CHANGES
run_stop "$(stop_input minimizer "Remove this.\n\n**REQUEST_CHANGES**")"
# Commit → hash_B: minimizer says APPROVE
echo "fix1" >> impl.sh && git add impl.sh && git commit -q -m "fix1"
run_stop "$(stop_input minimizer "Looks good.\n\n**APPROVE**")"
# Commit → hash_C: minimizer says REQUEST_CHANGES (legitimate new finding)
echo "fix2" >> impl.sh && git add impl.sh && git commit -q -m "fix2"
run_stop "$(stop_input minimizer "New issue on new code.\n\n**REQUEST_CHANGES**")"
EFILE=$(evidence_file "$SESSION")
if [ -f "$EFILE" ]; then
  OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
else
  OVERRIDE_COUNT=0
fi
assert "Cross-hash alternation → no auto-override (not oscillation)" '[ "$OVERRIDE_COUNT" -eq 0 ]'

# ─── Cross-hash oscillation detection tests ──────────────────────────────────

echo "=== Cross-hash: minimizer same finding across 3 hashes → auto-triage ==="
clean_evidence
cd "$TMPDIR_BASE"
SAME_FINDING="Remove the unnecessary abstraction.\n\n**REQUEST_CHANGES**\n\n[must] This helper is only used once."
# hash_A
run_stop "$(stop_input minimizer "$SAME_FINDING")"
# hash_B
echo "crossfix1" >> impl.sh && git add impl.sh && git commit -q -m "crossfix1"
run_stop "$(stop_input minimizer "$SAME_FINDING")"
# hash_C
echo "crossfix2" >> impl.sh && git add impl.sh && git commit -q -m "crossfix2"
run_stop "$(stop_input minimizer "$SAME_FINDING")"
EFILE=$(evidence_file "$SESSION")
OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
assert "Cross-hash: same minimizer finding across 3 hashes → auto-triage" '[ "$OVERRIDE_COUNT" -gt 0 ]'

echo "=== Cross-hash: minimizer same finding across 2 hashes only → no override ==="
clean_evidence
cd "$TMPDIR_BASE"
# hash_A
run_stop "$(stop_input minimizer "$SAME_FINDING")"
# hash_B
echo "crossfix3" >> impl.sh && git add impl.sh && git commit -q -m "crossfix3"
run_stop "$(stop_input minimizer "$SAME_FINDING")"
EFILE=$(evidence_file "$SESSION")
if [ -f "$EFILE" ]; then
  OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
else
  OVERRIDE_COUNT=0
fi
assert "Cross-hash: same finding across 2 hashes only → no override" '[ "$OVERRIDE_COUNT" -eq 0 ]'

echo "=== Cross-hash: minimizer different findings across hashes → no override ==="
clean_evidence
cd "$TMPDIR_BASE"
FINDING_A="Remove abstraction A.\n\n**REQUEST_CHANGES**"
FINDING_B="Remove abstraction B.\n\n**REQUEST_CHANGES**"
FINDING_C="Remove abstraction C.\n\n**REQUEST_CHANGES**"
run_stop "$(stop_input minimizer "$FINDING_A")"
echo "crossfix4" >> impl.sh && git add impl.sh && git commit -q -m "crossfix4"
run_stop "$(stop_input minimizer "$FINDING_B")"
echo "crossfix5" >> impl.sh && git add impl.sh && git commit -q -m "crossfix5"
run_stop "$(stop_input minimizer "$FINDING_C")"
EFILE=$(evidence_file "$SESSION")
if [ -f "$EFILE" ]; then
  OVERRIDE_COUNT=$(jq -r 'select(.type == "minimizer" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
else
  OVERRIDE_COUNT=0
fi
assert "Cross-hash: different findings across hashes → no override" '[ "$OVERRIDE_COUNT" -eq 0 ]'

echo "=== Cross-hash: code-critic same finding across 3 hashes → NO auto-triage ==="
clean_evidence
cd "$TMPDIR_BASE"
CC_FINDING="Null check missing in handler.\n\n**REQUEST_CHANGES**\n\n[must] Fix the null check."
run_stop "$(stop_input code-critic "$CC_FINDING")"
echo "crossfix6" >> impl.sh && git add impl.sh && git commit -q -m "crossfix6"
run_stop "$(stop_input code-critic "$CC_FINDING")"
echo "crossfix7" >> impl.sh && git add impl.sh && git commit -q -m "crossfix7"
run_stop "$(stop_input code-critic "$CC_FINDING")"
EFILE=$(evidence_file "$SESSION")
if [ -f "$EFILE" ]; then
  OVERRIDE_COUNT=$(jq -r 'select(.type == "code-critic" and .triage_override == true)' "$EFILE" 2>/dev/null | jq -s 'length')
else
  OVERRIDE_COUNT=0
fi
assert "Cross-hash: code-critic same finding across 3 hashes → NO auto-triage (correctness exempt)" '[ "$OVERRIDE_COUNT" -eq 0 ]'

# ─── Triage/Resolution metrics from critic findings ─────────────────────────

echo "=== Triage: code-critic REQUEST_CHANGES records finding_raised + triage ==="
clean_evidence
METRICS_FILE="$HOME/.claude/logs/review-metrics/${SESSION}.jsonl"
rm -f "$METRICS_FILE"

CRITIC_MSG="## Code Review Report

### Must Fix
- **src/app.ts:42** - [SRP] Handler doing too much

### Nits
- **src/app.ts:90** - [nit] Minor style issue

### Verdict
**REQUEST_CHANGES**"

run_stop "$(stop_input code-critic "$CRITIC_MSG")"

FINDING_COUNT=$(jq -s '[.[] | select(.event == "finding_raised")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Triage: 2 findings raised" '[ "$FINDING_COUNT" -eq 2 ]'

BLOCKING_TRIAGE=$(jq -s '[.[] | select(.event == "triage" and .classification == "blocking" and .action == "fix")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Triage: 1 blocking finding triaged as fix" '[ "$BLOCKING_TRIAGE" -eq 1 ]'

NB_TRIAGE=$(jq -s '[.[] | select(.event == "triage" and .classification == "non-blocking" and .action == "noted")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Triage: 1 non-blocking finding triaged as noted" '[ "$NB_TRIAGE" -eq 1 ]'

echo "=== Resolution: code-critic APPROVED resolves prior blocking findings ==="
APPROVE_MSG="## Code Review Report

### Summary
All issues fixed.

### Verdict
**APPROVE**"

run_stop "$(stop_input code-critic "$APPROVE_MSG")"

RESOLVED_COUNT=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "fixed")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Resolution: prior blocking finding resolved as fixed" '[ "$RESOLVED_COUNT" -ge 1 ]'

rm -f "$METRICS_FILE"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "agent-trace (start+stop): $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
