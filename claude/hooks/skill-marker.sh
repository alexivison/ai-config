#!/usr/bin/env bash
# Skill Marker Hook
# Creates evidence when critical skills complete (for PR gate)
#
# Triggered: PostToolUse on Skill tool

source "$(dirname "$0")/lib/evidence.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

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

# --- Evidence creation for enforced skills ---
case "$SKILL" in
  pre-pr-verification)
    append_evidence "$SESSION_ID" "pr-verified" "PASS" "$CWD"
    ;;
esac

echo '{}'
