#!/usr/bin/env bash
# Codex Review Gate Hook
# Blocks call_codex.sh --review unless both critic APPROVE markers exist.
# Creates a hard gate: you cannot invoke codex review without first earning critic approval.
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (cannot determine session_id or command → allow)

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ] || [ -z "$COMMAND" ]; then
  echo '{}'
  exit 0
fi

# Only gate call_codex.sh --review (not --prompt for debugging/architecture)
if ! echo "$COMMAND" | grep -qE '(^|[;&|] *)([^ ]*/)call_codex\.sh +--review( |[;&|]|$)'; then
  echo '{}'
  exit 0
fi

# Check for both critic APPROVE markers
CODE_CRITIC_MARKER="/tmp/claude-code-critic-$SESSION_ID"
MINIMIZER_MARKER="/tmp/claude-minimizer-$SESSION_ID"

MISSING=""
[ ! -f "$CODE_CRITIC_MARKER" ] && MISSING="$MISSING code-critic"
[ ! -f "$MINIMIZER_MARKER" ] && MISSING="$MISSING minimizer"

if [ -n "$MISSING" ]; then
  cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Codex review gate — critic APPROVE markers missing:$MISSING. Re-run critics before codex review."
  }
}
EOF
  exit 0
fi

# Both markers present — allow
echo '{}'
