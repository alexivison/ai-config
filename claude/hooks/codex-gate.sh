#!/usr/bin/env bash
# Codex Review Gate Hook
# Blocks tmux-codex.sh --review unless both critic APPROVE evidence exists.
# Blocks tmux-codex.sh --approve unless codex-ran evidence exists.
# Uses JSONL evidence log with diff_hash matching.
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (cannot determine session_id or command → allow)

source "$(dirname "$0")/lib/evidence.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

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

# Gate 2: --approve requires codex-ran evidence (review actually ran)
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--approve'; then
  if ! check_evidence "$SESSION_ID" "codex-ran" "$CWD"; then
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Codex approve gate — codex-ran evidence missing. Run tmux-codex.sh --review-complete first."
  }
}
EOF
    exit 0
  fi
  echo '{}'
  exit 0
fi

# Gate 1: --review requires critic APPROVE evidence (not --prompt or verdict modes)
if ! echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--review( |[;&|]|$)'; then
  echo '{}'
  exit 0
fi

# Check for both critic APPROVE evidence
MISSING=$(check_all_evidence "$SESSION_ID" "code-critic minimizer" "$CWD" 2>&1 || true)

if [ -n "$MISSING" ]; then
  cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Codex review gate — critic APPROVE evidence missing:$MISSING. Re-run critics before codex review."
  }
}
EOF
  exit 0
fi

# Both evidence present — allow
echo '{}'
