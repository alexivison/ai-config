#!/usr/bin/env bash
# PR Gate Hook - Enforces workflow completion before PR creation
# Blocks `gh pr create` unless ALL required markers exist:
#   - /tmp/claude-pr-verified-{session_id} (from /pre-pr-verification)
#   - /tmp/claude-code-critic-{session_id} (from code-critic APPROVE)
#   - /tmp/claude-codex-{session_id} (from codex agent APPROVE)
#   - /tmp/claude-tests-passed-{session_id} (from test-runner PASS)
#   - /tmp/claude-checks-passed-{session_id} (from check-runner PASS)
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (allows operation if hook can't determine state)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Only check PR creation (not git push - allow pushing during development)
# Note: Don't anchor with ^ since command may be chained (e.g., "cd ... && gh pr create")
if echo "$COMMAND" | grep -qE 'gh pr create'; then
  # Detect plan PR by branch name (*-plan suffix)
  # Uses suffix to preserve Linear convention: ENG-123-feature-plan
  # Note: Can't use "only doc files" detection because task PRs also update PLAN.md checkboxes
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if echo "$BRANCH_NAME" | grep -qE '\-plan$'; then
    # Plan PR - only need plan-reviewer marker
    PLAN_REVIEWER_MARKER="/tmp/claude-plan-reviewer-$SESSION_ID"
    if [ ! -f "$PLAN_REVIEWER_MARKER" ]; then
      cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Plan PR requires plan-reviewer APPROVE. Run plan-reviewer agent first."
  }
}
EOF
      exit 0
    fi
    # Plan PR approved - allow
    echo '{}'
    exit 0
  fi

  # Code PR - require all verification markers
  VERIFY_MARKER="/tmp/claude-pr-verified-$SESSION_ID"
  # SECURITY_MARKER="/tmp/claude-security-scanned-$SESSION_ID"  # Codex covers basic security
  CODE_CRITIC_MARKER="/tmp/claude-code-critic-$SESSION_ID"
  CODEX_MARKER="/tmp/claude-codex-$SESSION_ID"
  TESTS_MARKER="/tmp/claude-tests-passed-$SESSION_ID"
  CHECKS_MARKER="/tmp/claude-checks-passed-$SESSION_ID"

  MISSING=""
  [ ! -f "$VERIFY_MARKER" ] && MISSING="$MISSING /pre-pr-verification"
  # [ ! -f "$SECURITY_MARKER" ] && MISSING="$MISSING security-scanner"  # Codex covers basic security
  [ ! -f "$CODE_CRITIC_MARKER" ] && MISSING="$MISSING code-critic"
  [ ! -f "$CODEX_MARKER" ] && MISSING="$MISSING codex"
  [ ! -f "$TESTS_MARKER" ] && MISSING="$MISSING test-runner"
  [ ! -f "$CHECKS_MARKER" ] && MISSING="$MISSING check-runner"

  if [ -n "$MISSING" ]; then
    cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: PR gate requirements not met. Missing:$MISSING. Complete all workflow steps before creating PR."
  }
}
EOF
    exit 0
  fi
fi

# Allow by default
echo '{}'
