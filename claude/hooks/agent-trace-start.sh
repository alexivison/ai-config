#!/usr/bin/env bash
# SubagentStart Hook — logs sub-agent spawn events
#
# Triggered: SubagentStart (replaces PostToolUse Agent matcher for start tracking)
# Input: JSON via stdin with agent_id, agent_type, session_id, cwd

set -e

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
mkdir -p "$(dirname "$TRACE_FILE")"

hook_input=$(cat)

if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

agent_type=$(echo "$hook_input" | jq -r '.agent_type // "unknown"')
agent_id=$(echo "$hook_input" | jq -r '.agent_id // "unknown"')
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')
project=$(basename "$cwd")

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

trace_entry=$(jq -cn \
  --arg ts "$timestamp" \
  --arg session "$session_id" \
  --arg project "$project" \
  --arg agent "$agent_type" \
  --arg agent_id "$agent_id" \
  --arg event "start" \
  '{
    timestamp: $ts,
    event: $event,
    session: $session,
    project: $project,
    agent: $agent,
    agent_id: $agent_id
  }')

echo "$trace_entry" >> "$TRACE_FILE"
echo "$timestamp | START | $agent_type | $agent_id | $session_id" >> "$HOME/.claude/logs/evidence-trace.log"

exit 0
