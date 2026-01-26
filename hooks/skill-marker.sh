#!/bin/bash
# Skill Marker Hook - Creates markers when critical skills complete
# Used by PR gate to verify skills were invoked
#
# Triggered: PostToolUse on Skill tool
# Creates: /tmp/claude-pr-verified-{session_id} when /pre-pr-verification completes

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail silently if we can't parse
if [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Create marker when pre-pr-verification completes
if [ "$TOOL" = "Skill" ] && [ "$SKILL" = "pre-pr-verification" ]; then
  touch "/tmp/claude-pr-verified-$SESSION_ID"
fi

echo '{}'
