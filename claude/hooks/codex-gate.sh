#!/usr/bin/env bash
# Codex Review Gate Hook
# Blocks tmux-codex.sh --review unless both critic APPROVE markers exist.
# Blocks tmux-codex.sh --approve unless codex-ran marker exists.
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

# Only gate tmux-codex.sh invocations
if ! echo "$COMMAND" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh'; then
  echo '{}'
  exit 0
fi

# Gate 2: --approve requires codex-ran marker (evidence that review actually ran)
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--approve'; then
  CODEX_RAN_MARKER="/tmp/claude-codex-ran-$SESSION_ID"
  if [ ! -f "$CODEX_RAN_MARKER" ]; then
    cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Codex approve gate — codex-ran marker missing. Run tmux-codex.sh --review-complete first."
  }
}
EOF
    exit 0
  fi
  echo '{}'
  exit 0
fi

# Gate 1: --review requires critic APPROVE markers (not --prompt or verdict modes)
if ! echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--review( |[;&|]|$)'; then
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
