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
  SUGGESTION="MANDATORY: Invoke bugfix-workflow skill FIRST, before fetching tickets, reading code, or any investigation. The workflow itself handles investigation steps."
  PRIORITY="must"

# plan-workflow: Explicit task-breakdown triggers (check BEFORE general feature keywords)
# Keyword-only heuristic — actual DESIGN.md validation is in the skill entry gate.
elif echo "$PROMPT_LOWER" | grep -qE '\btask breakdown\b|\bbreak.*(design|plan) into tasks\b|\bcreate tasks from\b|\bplan from design\b|\bplan-workflow\b'; then
  SUGGESTION="MANDATORY: Invoke plan-workflow skill. Create task breakdown (PLAN.md + TASKs) from the approved DESIGN.md."
  PRIORITY="must"

# design-workflow: New feature keywords (default entry point for two-phase planning)
# The skill entry gate redirects to plan-workflow if DESIGN.md already exists.
# No filesystem or prompt-content detection here — skills own the routing contract.
elif echo "$PROMPT_LOWER" | grep -qE '\bnew feature\b|\bimplement\b|\bbuild\b|\bcreate\b|\badd (a |the |new )?[a-z]+\b|\bplan\b'; then
  SUGGESTION="MANDATORY: Invoke design-workflow skill (Phase 1). Create SPEC.md + DESIGN.md. If DESIGN.md already exists, the skill redirects to plan-workflow."
  PRIORITY="must"

# Other MUST skills
elif echo "$PROMPT_LOWER" | grep -qE '\bcreate pr\b|\bmake pr\b|\bready for pr\b|\bopen pr\b|\bsubmit pr\b'; then
  SUGGESTION="MANDATORY: Run code-critic + minimizer + wizard + /pre-pr-verification BEFORE creating PR. PR gate will block without these."
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
elif echo "$PROMPT_LOWER" | grep -qE '\bpr comment|\breview(er)? (comment|feedback|request)|\baddress (the |this |pr )?feedback|\bfix.*comment|\brespond to.*review'; then
  SUGGESTION="RECOMMENDED: Invoke /address-pr to systematically address comments."
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
