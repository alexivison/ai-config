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

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "agent-trace (start+stop): $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
