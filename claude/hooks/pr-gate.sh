#!/usr/bin/env bash
# PR Gate Hook - Enforces workflow completion before PR creation
# Blocks `gh pr create` unless ALL required markers exist:
#   - /tmp/claude-pr-verified-{session_id} (from /pre-pr-verification)
#   - /tmp/claude-code-critic-{session_id} (from code-critic APPROVE)
#   - /tmp/claude-minimizer-{session_id} (from minimizer APPROVE)
#   - /tmp/claude-codex-{session_id} (from codex CLI APPROVE via codex-verdict.sh)
#   - /tmp/claude-tests-passed-{session_id} (from test-runner PASS)
#   - /tmp/claude-checks-passed-{session_id} (from check-runner PASS)
#   - /tmp/claude-security-scanned-{session_id} (from security-scanner via /pre-pr-verification)
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
  # Code PR - require all verification markers
  VERIFY_MARKER="/tmp/claude-pr-verified-$SESSION_ID"
  SECURITY_MARKER="/tmp/claude-security-scanned-$SESSION_ID"
  CODE_CRITIC_MARKER="/tmp/claude-code-critic-$SESSION_ID"
  CODEX_MARKER="/tmp/claude-codex-$SESSION_ID"
  TESTS_MARKER="/tmp/claude-tests-passed-$SESSION_ID"
  CHECKS_MARKER="/tmp/claude-checks-passed-$SESSION_ID"
  MINIMIZE_MARKER="/tmp/claude-minimizer-$SESSION_ID"

  MISSING=""
  [ ! -f "$VERIFY_MARKER" ] && MISSING="$MISSING /pre-pr-verification"
  [ ! -f "$SECURITY_MARKER" ] && MISSING="$MISSING security-scanner"
  [ ! -f "$CODE_CRITIC_MARKER" ] && MISSING="$MISSING code-critic"
  [ ! -f "$CODEX_MARKER" ] && MISSING="$MISSING codex"
  [ ! -f "$TESTS_MARKER" ] && MISSING="$MISSING test-runner"
  [ ! -f "$CHECKS_MARKER" ] && MISSING="$MISSING check-runner"
  [ ! -f "$MINIMIZE_MARKER" ] && MISSING="$MISSING minimizer"

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
