#!/bin/bash
# Skill Marker & Trace Hook
# - Creates markers when critical skills complete (for PR gate)
# - Logs skill invocations to ~/.claude/logs/skill-trace.jsonl
#
# Triggered: PostToolUse on Skill tool

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // ""' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
PROJECT=$(basename "$CWD")

# Fail silently if we can't parse
if [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Only process Skill tool
if [ "$TOOL" != "Skill" ]; then
  echo '{}'
  exit 0
fi

# --- Skill Trace Logging ---
TRACE_FILE="$HOME/.claude/logs/skill-trace.jsonl"
mkdir -p "$(dirname "$TRACE_FILE")"

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

trace_entry=$(jq -n \
  --arg ts "$timestamp" \
  --arg session "$SESSION_ID" \
  --arg project "$PROJECT" \
  --arg skill "$SKILL" \
  --arg args "$ARGS" \
  '{
    timestamp: $ts,
    session: $session,
    project: $project,
    skill: $skill,
    args: $args
  }')

echo "$trace_entry" >> "$TRACE_FILE"

# --- Marker Creation for MUST-invoke skills ---
case "$SKILL" in
  pre-pr-verification)
    touch "/tmp/claude-pr-verified-$SESSION_ID"
    touch "/tmp/claude-skill-pre-pr-verification-$SESSION_ID"
    ;;
  write-tests)
    touch "/tmp/claude-skill-write-tests-$SESSION_ID"
    ;;
  code-review)
    touch "/tmp/claude-skill-code-review-$SESSION_ID"
    ;;
  architecture-review)
    touch "/tmp/claude-skill-architecture-review-$SESSION_ID"
    ;;
esac

echo '{}'
