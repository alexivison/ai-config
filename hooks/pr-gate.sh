#!/bin/bash
# PR Gate Hook - Enforces verification before PR creation
# Blocks `gh pr create` unless both markers exist:
#   - /tmp/claude-pr-verified-{session_id} (from /pre-pr-verification)
#   - /tmp/claude-security-scanned-{session_id} (from security-scanner)
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
  VERIFY_MARKER="/tmp/claude-pr-verified-$SESSION_ID"
  SECURITY_MARKER="/tmp/claude-security-scanned-$SESSION_ID"

  MISSING=""
  [ ! -f "$VERIFY_MARKER" ] && MISSING="$MISSING /pre-pr-verification"
  [ ! -f "$SECURITY_MARKER" ] && MISSING="$MISSING security-scanner"

  if [ -n "$MISSING" ]; then
    cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: PR gate requirements not met. Missing:$MISSING. Run these before creating PR."
  }
}
EOF
    exit 0
  fi
fi

# Allow by default
echo '{}'
