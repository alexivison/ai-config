#!/usr/bin/env bash
# Agent Observability Hook
# Logs sub-agent invocations to ~/.claude/logs/agent-trace.jsonl
#
# Triggered: PostToolUse on Task tool
# Input: JSON via stdin with tool_name, tool_input, tool_response

set -e

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
mkdir -p "$(dirname "$TRACE_FILE")"

# Read hook input from stdin
hook_input=$(cat)

# Validate JSON input
if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  echo '{"error": "Invalid JSON input"}' >> "$HOME/.claude/logs/hook-errors.log" 2>/dev/null
  exit 0
fi

# Extract fields with error handling
tool_name=$(echo "$hook_input" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$tool_name" ]; then
  exit 0
fi

# Only process Task tool (sub-agent invocations)
if [ "$tool_name" != "Task" ]; then
  exit 0
fi

# Extract agent details from tool_input
agent_type=$(echo "$hook_input" | jq -r '.tool_input.subagent_type // "unknown"')
description=$(echo "$hook_input" | jq -r '.tool_input.description // ""')
model=$(echo "$hook_input" | jq -r '.tool_input.model // "inherit"')

# Extract result summary from tool_response
response_text=$(echo "$hook_input" | jq -r '.tool_response // ""' | head -c 500)

# Detect verdict/status from common patterns (ordered by specificity)
verdict="unknown"
if echo "$response_text" | grep -qi "REQUEST_CHANGES\|CHANGES REQUESTED"; then
  verdict="REQUEST_CHANGES"
elif echo "$response_text" | grep -qi "NEEDS_DISCUSSION"; then
  verdict="NEEDS_DISCUSSION"
elif echo "$response_text" | grep -qi "APPROVE"; then
  verdict="APPROVED"
elif echo "$response_text" | grep -qi "SKIP"; then
  verdict="SKIP"
elif echo "$response_text" | grep -qi "CRITICAL\|HIGH"; then
  verdict="ISSUES_FOUND"
elif echo "$response_text" | grep -qi "FAIL"; then
  verdict="FAIL"
elif echo "$response_text" | grep -qi "PASS"; then
  verdict="PASS"
elif echo "$response_text" | grep -qi "CLEAN"; then
  verdict="CLEAN"
elif echo "$response_text" | grep -qi "complete\|done\|finished"; then
  verdict="COMPLETED"
fi

# Get session info
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')
project=$(basename "$cwd")

# Create trace entry
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

trace_entry=$(jq -n \
  --arg ts "$timestamp" \
  --arg session "$session_id" \
  --arg project "$project" \
  --arg agent "$agent_type" \
  --arg desc "$description" \
  --arg model "$model" \
  --arg verdict "$verdict" \
  '{
    timestamp: $ts,
    session: $session,
    project: $project,
    agent: $agent,
    description: $desc,
    model: $model,
    verdict: $verdict
  }')

# Append to trace file
echo "$trace_entry" >> "$TRACE_FILE"

# Create markers for PR gate enforcement
# Each marker proves a workflow step was completed

# security-scanner: any completion creates marker
if [ "$agent_type" = "security-scanner" ]; then
  touch "/tmp/claude-security-scanned-$session_id"
fi

# architecture-critic: any verdict creates marker (review happened)
if [ "$agent_type" = "architecture-critic" ]; then
  touch "/tmp/claude-architecture-reviewed-$session_id"
fi

# code-critic: only APPROVE creates marker (must pass before PR)
if [ "$agent_type" = "code-critic" ] && [ "$verdict" = "APPROVED" ]; then
  touch "/tmp/claude-code-critic-$session_id"
fi

# test-runner: only PASS creates marker
if [ "$agent_type" = "test-runner" ] && [ "$verdict" = "PASS" ]; then
  touch "/tmp/claude-tests-passed-$session_id"
fi

# check-runner: only PASS or CLEAN creates marker
if [ "$agent_type" = "check-runner" ]; then
  if [ "$verdict" = "PASS" ] || [ "$verdict" = "CLEAN" ]; then
    touch "/tmp/claude-checks-passed-$session_id"
  fi
fi

# plan-reviewer: only APPROVED creates marker
if [ "$agent_type" = "plan-reviewer" ] && [ "$verdict" = "APPROVED" ]; then
  touch "/tmp/claude-plan-reviewer-$session_id"
fi

exit 0
