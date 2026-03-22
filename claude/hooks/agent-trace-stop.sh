#!/usr/bin/env bash
# SubagentStop Hook — logs sub-agent completion with verdict detection + markers
#
# Triggered: SubagentStop (replaces PostToolUse Agent matcher)
# Input: JSON via stdin with agent_id, agent_type, last_assistant_message, session_id, cwd
#
# SubagentStop provides last_assistant_message directly — no need to parse
# content-block arrays or strip agentId/usage metadata from tool_response.

set -e

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
mkdir -p "$(dirname "$TRACE_FILE")"

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/oscillation.sh"

hook_input=$(cat)

if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  hook_log "agent-trace-stop" "unknown" "error" "invalid JSON input"
  exit 0
fi

agent_type=$(echo "$hook_input" | jq -r '.agent_type // "unknown"')
agent_id=$(echo "$hook_input" | jq -r '.agent_id // "unknown"')
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')
cwd=$(_resolve_cwd "$session_id" "$cwd")
project=$(basename "$cwd")

# last_assistant_message is a clean string — no content-block parsing needed
response=$(echo "$hook_input" | jq -r '.last_assistant_message // ""')

# ── Verdict detection ──
# Scan only the tail to avoid false positives from "APPROVE" in prose
verdict_region=$(echo "$response" | tail -c 1000)
verdict="unknown"

if echo "$verdict_region" | grep -qE '\*\*REQUEST_CHANGES\*\*|^REQUEST_CHANGES'; then
  verdict="REQUEST_CHANGES"
elif echo "$verdict_region" | grep -qE '\*\*NEEDS_DISCUSSION\*\*|^NEEDS_DISCUSSION'; then
  verdict="NEEDS_DISCUSSION"
elif echo "$verdict_region" | grep -qE '\*\*APPROVE\*\*|^APPROVE'; then
  verdict="APPROVED"
elif echo "$verdict_region" | grep -qi "SKIP"; then
  verdict="SKIP"
elif echo "$verdict_region" | grep -qiE '\bCRITICAL\b|\bHIGH\b'; then
  verdict="ISSUES_FOUND"
elif echo "$verdict_region" | grep -qiE '\bFAIL\b'; then
  verdict="FAIL"
elif echo "$verdict_region" | grep -qiE '\bPASS\b'; then
  verdict="PASS"
elif echo "$verdict_region" | grep -qiE '\bCLEAN\b'; then
  verdict="CLEAN"
elif echo "$verdict_region" | grep -qi "complete\|done\|finished"; then
  verdict="COMPLETED"
fi

# Fallback: scan full response for short agent outputs (e.g. minimizer APPROVE)
if [ "$verdict" = "unknown" ] && [ -n "$response" ]; then
  if echo "$response" | grep -qE '\*\*REQUEST_CHANGES\*\*|^REQUEST_CHANGES'; then
    verdict="REQUEST_CHANGES"
  elif echo "$response" | grep -qE '\*\*NEEDS_DISCUSSION\*\*|^NEEDS_DISCUSSION'; then
    verdict="NEEDS_DISCUSSION"
  elif echo "$response" | grep -qE '\*\*APPROVE\*\*|^APPROVE'; then
    verdict="APPROVED"
  elif echo "$response" | grep -qiE '\bFAIL\b'; then
    verdict="FAIL"
  elif echo "$response" | grep -qiE '\bPASS\b'; then
    verdict="PASS"
  fi
fi

# ── Trace entry ──
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

trace_entry=$(jq -cn \
  --arg ts "$timestamp" \
  --arg session "$session_id" \
  --arg project "$project" \
  --arg agent "$agent_type" \
  --arg agent_id "$agent_id" \
  --arg verdict "$verdict" \
  --arg event "stop" \
  '{
    timestamp: $ts,
    event: $event,
    session: $session,
    project: $project,
    agent: $agent,
    agent_id: $agent_id,
    verdict: $verdict
  }')

echo "$trace_entry" >> "$TRACE_FILE"
echo "$timestamp | STOP  | $agent_type | $verdict | $agent_id | $session_id" >> "$HOME/.claude/logs/evidence-trace.log"
hook_log "agent-trace-stop" "$session_id" "allow" "agent=$agent_type verdict=$verdict"

# ── Evidence for PR gate enforcement ──

if [ "$agent_type" = "code-critic" ] && [ "$verdict" = "APPROVED" ]; then
  append_evidence "$session_id" "code-critic" "APPROVED" "$cwd"
fi

if [ "$agent_type" = "minimizer" ] && [ "$verdict" = "APPROVED" ]; then
  append_evidence "$session_id" "minimizer" "APPROVED" "$cwd"
fi

if [ "$agent_type" = "test-runner" ] && [ "$verdict" = "PASS" ]; then
  append_evidence "$session_id" "test-runner" "PASS" "$cwd"
fi

if [ "$agent_type" = "check-runner" ]; then
  if [ "$verdict" = "PASS" ] || [ "$verdict" = "CLEAN" ]; then
    append_evidence "$session_id" "check-runner" "$verdict" "$cwd"
  fi
fi

# ── Oscillation detection for critics (delegated to lib/oscillation.sh) ──
if [ "$agent_type" = "code-critic" ] || [ "$agent_type" = "minimizer" ]; then
  detect_oscillation "$session_id" "$agent_type" "$verdict" "$response" "$cwd"
fi

exit 0
