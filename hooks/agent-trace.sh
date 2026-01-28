#!/bin/bash
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

# Try to extract skills from agent definition file
skills=""
agent_file="$HOME/.claude/agents/${agent_type}.md"
if [ -f "$agent_file" ]; then
  # Extract skills from YAML frontmatter (between --- markers)
  # Look for "skills:" followed by list items "  - skillname"
  skills=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep -A 20 '^skills:' | grep '^ *- ' | sed 's/^ *- //' | tr '\n' ',' | sed 's/,$//')
fi

# Extract result summary from tool_response
# The response structure varies, try to get meaningful summary
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
  --arg skills "$skills" \
  --arg verdict "$verdict" \
  '{
    timestamp: $ts,
    session: $session,
    project: $project,
    agent: $agent,
    description: $desc,
    model: $model,
    skills: $skills,
    verdict: $verdict
  }')

# Append to trace file
echo "$trace_entry" >> "$TRACE_FILE"

# Create marker when security-scanner completes (for PR gate)
if [ "$agent_type" = "security-scanner" ]; then
  touch "/tmp/claude-security-scanned-$session_id"
fi

# Create marker when architecture-critic completes
if [ "$agent_type" = "architecture-critic" ]; then
  touch "/tmp/claude-architecture-reviewed-$session_id"
fi

exit 0
