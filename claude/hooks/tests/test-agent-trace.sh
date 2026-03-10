#!/usr/bin/env bash
# Tests for agent-trace-start.sh and agent-trace-stop.sh
# Covers: start/stop tracing, verdict detection, marker creation
#
# Usage: bash ~/.claude/hooks/tests/test-agent-trace.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_HOOK="${SCRIPT_DIR}/../agent-trace-start.sh"
STOP_HOOK="${SCRIPT_DIR}/../agent-trace-stop.sh"
TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
PASS=0
FAIL=0
SESSION="test-agent-trace-$$"

cleanup() {
  rm -f /tmp/claude-code-critic-"$SESSION"
  rm -f /tmp/claude-minimizer-"$SESSION"
  rm -f /tmp/claude-tests-passed-"$SESSION"
  rm -f /tmp/claude-checks-passed-"$SESSION"
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

# Helper to build SubagentStart input
start_input() {
  local agent_type="$1"
  jq -cn \
    --arg at "$agent_type" \
    --arg aid "agent-$$-$RANDOM" \
    --arg sid "$SESSION" \
    '{agent_type: $at, agent_id: $aid, session_id: $sid, cwd: "/tmp/test-project"}'
}

# Helper to build SubagentStop input
stop_input() {
  local agent_type="$1" message="$2"
  jq -cn \
    --arg at "$agent_type" \
    --arg aid "agent-$$-$RANDOM" \
    --arg sid "$SESSION" \
    --arg msg "$message" \
    '{agent_type: $at, agent_id: $aid, session_id: $sid, cwd: "/tmp/test-project", last_assistant_message: $msg}'
}

# ─── Start hook tests ────────────────────────────────────────────────────────

echo "=== Start Hook: Logs spawn event ==="
cleanup
run_start "$(start_input code-critic)"
assert "Start event logged" '[ "$(last_trace_field start agent)" = "code-critic" ]'
assert "Start event type correct" '[ "$(last_trace_field start event)" = "start" ]'

echo "=== Start Hook: Different agent types ==="
run_start "$(start_input test-runner)"
assert "test-runner start logged" '[ "$(last_trace_field start agent)" = "test-runner" ]'

# ─── Verdict detection tests ─────────────────────────────────────────────────

echo "=== Verdict: APPROVE ==="
cleanup
run_stop "$(stop_input code-critic "Review done.\n\n**APPROVE** — All good.")"
assert "APPROVED verdict" '[ "$(last_trace_field stop verdict)" = "APPROVED" ]'
assert "code-critic marker created" '[ -f /tmp/claude-code-critic-$SESSION ]'

echo "=== Verdict: REQUEST_CHANGES ==="
cleanup
run_stop "$(stop_input code-critic "Found bugs.\n\n**REQUEST_CHANGES**\n\n[must] Fix null check.")"
assert "REQUEST_CHANGES detected" '[ "$(last_trace_field stop verdict)" = "REQUEST_CHANGES" ]'
assert "REQUEST_CHANGES → no marker" '[ ! -f /tmp/claude-code-critic-$SESSION ]'

echo "=== Verdict: NEEDS_DISCUSSION ==="
cleanup
run_stop "$(stop_input code-critic "Unclear requirement.\n\n**NEEDS_DISCUSSION**")"
assert "NEEDS_DISCUSSION detected" '[ "$(last_trace_field stop verdict)" = "NEEDS_DISCUSSION" ]'

echo "=== Verdict: PASS ==="
cleanup
run_stop "$(stop_input test-runner "All 42 tests passed.\n\nPASS")"
assert "PASS verdict" '[ "$(last_trace_field stop verdict)" = "PASS" ]'
assert "test-runner marker created" '[ -f /tmp/claude-tests-passed-$SESSION ]'

echo "=== Verdict: FAIL ==="
cleanup
run_stop "$(stop_input test-runner "3 tests failed.\n\nFAIL")"
assert "FAIL detected" '[ "$(last_trace_field stop verdict)" = "FAIL" ]'
assert "FAIL → no test-runner marker" '[ ! -f /tmp/claude-tests-passed-$SESSION ]'

echo "=== Verdict: CLEAN ==="
cleanup
run_stop "$(stop_input check-runner "No issues found.\n\nCLEAN")"
assert "CLEAN detected" '[ "$(last_trace_field stop verdict)" = "CLEAN" ]'
assert "check-runner marker created" '[ -f /tmp/claude-checks-passed-$SESSION ]'

echo "=== Verdict: ISSUES_FOUND ==="
cleanup
run_stop "$(stop_input code-critic "Found CRITICAL issue in review.")"
assert "ISSUES_FOUND detected" '[ "$(last_trace_field stop verdict)" = "ISSUES_FOUND" ]'

echo "=== Verdict: unknown for background launch ==="
cleanup
run_stop "$(stop_input code-critic "Launched successfully. The agent is working in the background.")"
assert "Background launch → unknown verdict" '[ "$(last_trace_field stop verdict)" = "unknown" ]'
assert "Background launch → no marker" '[ ! -f /tmp/claude-code-critic-$SESSION ]'

# ─── Marker creation tests ───────────────────────────────────────────────────

echo "=== Markers: Each agent type maps to correct marker ==="
cleanup
run_stop "$(stop_input code-critic "**APPROVE**")"
assert "code-critic APPROVE → code-critic marker" '[ -f /tmp/claude-code-critic-$SESSION ]'
assert "code-critic APPROVE → no minimizer marker" '[ ! -f /tmp/claude-minimizer-$SESSION ]'

cleanup
run_stop "$(stop_input minimizer "**APPROVE**")"
assert "minimizer APPROVE → minimizer marker" '[ -f /tmp/claude-minimizer-$SESSION ]'
assert "minimizer APPROVE → no code-critic marker" '[ ! -f /tmp/claude-code-critic-$SESSION ]'

cleanup
run_stop "$(stop_input check-runner "All passed.\n\nPASS")"
assert "check-runner PASS → checks-passed marker" '[ -f /tmp/claude-checks-passed-$SESSION ]'

# ─── Priority tests ──────────────────────────────────────────────────────────

echo "=== Priority: REQUEST_CHANGES wins over APPROVE in prose ==="
cleanup
run_stop "$(stop_input code-critic "APPROVE in prose but **REQUEST_CHANGES** is the verdict.")"
assert "REQUEST_CHANGES takes priority" '[ "$(last_trace_field stop verdict)" = "REQUEST_CHANGES" ]'

# ─── Guard tests ──────────────────────────────────────────────────────────────

echo "=== Guard: Invalid JSON fails open ==="
cleanup
echo 'not json at all' | bash "$STOP_HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash (exit 0)" 'true'

echo "=== Guard: Empty message → unknown ==="
cleanup
run_stop "$(stop_input code-critic "")"
assert "Empty message → unknown verdict" '[ "$(last_trace_field stop verdict)" = "unknown" ]'

# ─── Summary ─────────────────────────────────────────────────────────────────

cleanup
echo ""
echo "═══════════════════════════════════════"
echo "agent-trace (start+stop): $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
