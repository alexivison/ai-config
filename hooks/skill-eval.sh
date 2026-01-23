#!/bin/bash

# Skill auto-invocation hook
# Detects skill triggers and suggests immediate invocation
# Silent when no match — only speaks up when a skill should be invoked
#
# NOTE: This is a reminder system, not enforcement. Claude can ignore suggestions.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Detect triggers and build suggestion
# Using word boundaries where possible to reduce false positives
SUGGESTION=""

# MUST invoke skills (highest priority)
if echo "$PROMPT_LOWER" | grep -qE '\bwrite tests?\b|\badd tests?\b|\bcreate tests?\b|\btest coverage\b|\badd coverage\b'; then
  SUGGESTION="INVOKE /write-tests before writing any tests."
elif echo "$PROMPT_LOWER" | grep -qE '\bcreate pr\b|\bmake pr\b|\bready for pr\b|\bopen pr\b|\bsubmit pr\b|push.*pr'; then
  SUGGESTION="INVOKE /pre-pr-verification before creating the PR."
elif echo "$PROMPT_LOWER" | grep -qE '\breview (this|my|the) code\b|\bcode review\b|\breview (this|my) pr\b|\bcheck this code\b|\bfeedback on.*code'; then
  SUGGESTION="INVOKE /code-review for systematic review."

# SHOULD invoke skills
elif echo "$PROMPT_LOWER" | grep -qE '\bplan (this|the|a) feature\b|\bbreak down\b|\bcreate spec\b|\bdesign (this|the)\b|/plan'; then
  SUGGESTION="INVOKE /plan-implementation for structured planning."
elif echo "$PROMPT_LOWER" | grep -qE '\bpr comment|\breview(er)? (comment|feedback|request)|\baddress (the |this |pr )?feedback|\bfix.*comment|\brespond to.*review'; then
  SUGGESTION="INVOKE /address-pr to systematically address comments."
elif echo "$PROMPT_LOWER" | grep -qE '\bbloat\b|\btoo (big|large|much)\b|\bminimize\b|\bsimplify\b|\bover.?engineer'; then
  SUGGESTION="INVOKE /minimize to identify unnecessary complexity."
elif echo "$PROMPT_LOWER" | grep -qE '\bunclear\b|\bmultiple (approach|option|way)|\bnot sure (how|which|what)\b|\bbest (approach|way)\b|\bbrainstorm\b|\bhow should (we|i)\b'; then
  SUGGESTION="INVOKE /brainstorm to capture context before planning."
elif echo "$PROMPT_LOWER" | grep -qE '\blearn from (this|session)\b|\bremember (this|that)\b|\bsave (this |that |)preference\b|\bextract pattern\b|/autoskill'; then
  SUGGESTION="INVOKE /autoskill to learn from this session."
fi

# Only output if there's a match
if [ -n "$SUGGESTION" ]; then
  cat << EOF
{
  "additionalContext": "<skill-trigger>\n$SUGGESTION\n</skill-trigger>"
}
EOF
else
  # Silent when no match
  echo '{}'
fi
