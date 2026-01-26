#!/bin/bash

# Skill auto-invocation hook (UPGRADED)
# Detects skill triggers and injects MANDATORY or SHOULD suggestions
# MANDATORY = blocking requirement per CLAUDE.md
# SHOULD = recommended but not required
#
# NOTE: This is a reminder system. Hard enforcement is in pr-gate.sh.

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

SUGGESTION=""
PRIORITY=""  # "must" or "should"

# MUST invoke skills (highest priority, blocking language)
if echo "$PROMPT_LOWER" | grep -qE '\bwrite tests?\b|\badd tests?\b|\bcreate tests?\b|\btest coverage\b|\badd coverage\b'; then
  SUGGESTION="MANDATORY: Invoke /write-tests skill BEFORE writing any tests."
  PRIORITY="must"
elif echo "$PROMPT_LOWER" | grep -qE '\bcreate pr\b|\bmake pr\b|\bready for pr\b|\bopen pr\b|\bsubmit pr\b'; then
  SUGGESTION="MANDATORY: Run /pre-pr-verification + security-scanner BEFORE creating PR. PR gate will block without these."
  PRIORITY="must"
elif echo "$PROMPT_LOWER" | grep -qE '\breview (this|my|the) code\b|\bcode review\b|\breview (this|my) pr\b|\bcheck this code\b|\bfeedback on.*code'; then
  SUGGESTION="MANDATORY: Invoke /code-review skill for systematic review."
  PRIORITY="must"

# SHOULD invoke skills (recommended)
elif echo "$PROMPT_LOWER" | grep -qE '\bquality.?critical\b|\bimportant.*code\b|\bproduction.*ready\b'; then
  SUGGESTION="RECOMMENDED: Use code-critic agent for iterative quality refinement."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bsecurity\b|\bvulnerab\b|\baudit\b|\bsecret\b'; then
  SUGGESTION="RECOMMENDED: Run security-scanner agent for security analysis."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bplan (this|the|a) feature\b|\bbreak down\b|\bcreate spec\b|\bdesign (this|the)\b|/plan'; then
  SUGGESTION="RECOMMENDED: Invoke /plan-implementation for structured planning."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bpr comment|\breview(er)? (comment|feedback|request)|\baddress (the |this |pr )?feedback|\bfix.*comment|\brespond to.*review'; then
  SUGGESTION="RECOMMENDED: Invoke /address-pr to systematically address comments."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bbloat\b|\btoo (big|large|much)\b|\bminimize\b|\bsimplify\b|\bover.?engineer'; then
  SUGGESTION="RECOMMENDED: Invoke /minimize to identify unnecessary complexity."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bunclear\b|\bmultiple (approach|option|way)|\bnot sure (how|which|what)\b|\bbest (approach|way)\b|\bbrainstorm\b|\bhow should (we|i)\b'; then
  SUGGESTION="RECOMMENDED: Invoke /brainstorm to capture context before planning."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\blearn from (this|session)\b|\bremember (this|that)\b|\bsave (this |that |)preference\b|\bextract pattern\b|/autoskill'; then
  SUGGESTION="RECOMMENDED: Invoke /autoskill to learn from this session."
  PRIORITY="should"
fi

# Output with priority level
if [ -n "$SUGGESTION" ]; then
  if [ "$PRIORITY" = "must" ]; then
    cat << EOF
{
  "additionalContext": "<skill-trigger priority=\"MUST\">\n$SUGGESTION\nThis is a BLOCKING REQUIREMENT per CLAUDE.md.\n</skill-trigger>"
}
EOF
  else
    cat << EOF
{
  "additionalContext": "<skill-trigger priority=\"SHOULD\">\n$SUGGESTION\n</skill-trigger>"
}
EOF
  fi
else
  # Silent when no match
  echo '{}'
fi
