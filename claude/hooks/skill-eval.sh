#!/usr/bin/env bash

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

# MUST skills - check most specific patterns first

# task-workflow: TASK file references (highest priority - most specific)
if echo "$PROMPT_LOWER" | grep -qE '\btask[_-]?[0-9]|\btask[_-]?file|\bpick up task|\bfrom (the )?plan\b|\bexecute task\b|\bimplement task\b'; then
  SUGGESTION="MANDATORY: Invoke task-workflow skill for planned task execution."
  PRIORITY="must"

# write-tests: Test-related keywords (high specificity - check before feature-workflow)
elif echo "$PROMPT_LOWER" | grep -qE '\bwrite (a |the )?tests?\b|\badd (a |the )?tests?\b|\bcreate (a |the )?tests?\b|\btest coverage\b|\badd coverage\b'; then
  SUGGESTION="MANDATORY: Invoke /write-tests skill BEFORE writing any tests."
  PRIORITY="must"

# bugfix-workflow: Bug/error keywords (medium specificity)
# Note: "fix" alone is too broad (catches "fix typo"). Require bug-related context.
elif echo "$PROMPT_LOWER" | grep -qE '\bbug\b|\bbroken\b|\berror\b|\bnot work|\bdebug\b|\bcrash|\bfail(s|ed|ing|ure)?\b|\bfix(es|ed|ing)?\b.*(bug|error|issue|broken|crash|fail)|\b(bug|error|issue|broken|crash).*(fix|fixes|fixed|fixing)\b'; then
  SUGGESTION="MANDATORY: Invoke bugfix-workflow skill for debugging workflow."
  PRIORITY="must"

# plan-workflow: Build/create keywords (fallback - most general)
# Note: task-workflow triggers first on TASK file references, so this catches new feature requests
elif echo "$PROMPT_LOWER" | grep -qE '\bnew feature\b|\bimplement\b|\bbuild\b|\bcreate\b|\badd (a |the |new )?[a-z]+\b'; then
  SUGGESTION="MANDATORY: Invoke plan-workflow skill for planning workflow."
  PRIORITY="must"

# Other MUST skills
elif echo "$PROMPT_LOWER" | grep -qE '\bcreate pr\b|\bmake pr\b|\bready for pr\b|\bopen pr\b|\bsubmit pr\b'; then
  SUGGESTION="MANDATORY: Run /pre-pr-verification + security-scanner BEFORE creating PR. PR gate will block without these."
  PRIORITY="must"
elif echo "$PROMPT_LOWER" | grep -qE '\breview (this|my|the) code\b|\bcode review\b|\breview (this|my) pr\b|\bcheck this code\b|\bfeedback on.*code'; then
  SUGGESTION="MANDATORY: Invoke /code-review skill for systematic review."
  PRIORITY="must"

# SHOULD invoke skills (recommended)
elif echo "$PROMPT_LOWER" | grep -qE '\bquality.?critical\b|\bimportant.*code\b|\bproduction.*ready\b'; then
  SUGGESTION="RECOMMENDED: Use cli-orchestrator agent for iterative quality refinement via Codex."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bsecurity\b|\bvulnerab\b|\baudit\b|\bsecret\b'; then
  SUGGESTION="RECOMMENDED: Run security-scanner agent for security analysis."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bpr comment|\breview(er)? (comment|feedback|request)|\baddress (the |this |pr )?feedback|\bfix.*comment|\brespond to.*review'; then
  SUGGESTION="RECOMMENDED: Invoke /address-pr to systematically address comments."
  PRIORITY="should"
elif echo "$PROMPT_LOWER" | grep -qE '\bbloat\b|\btoo (big|large|much)\b|\bminimize\b|\bsimplify\b|\bover.?engineer'; then
  SUGGESTION="RECOMMENDED: Invoke /minimize to identify unnecessary complexity."
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
