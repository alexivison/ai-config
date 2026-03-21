#!/usr/bin/env bash
# Codex Review Gate Hook
# Hard-blocks tmux-codex.sh --approve — workers cannot self-approve.
# Codex approval flows through --review-complete (verdict in findings file).
# All other Codex commands (--review, --prompt, --plan-review, --review-complete)
# pass through freely. Workflow skills enforce critic-to-Codex sequencing;
# this hook only enforces the self-approval block.
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (cannot determine session_id or command → allow)

source "$(dirname "$0")/lib/evidence.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ] || [ -z "$COMMAND" ]; then
  hook_log "codex-gate" "${SESSION_ID:-unknown}" "allow" "missing session_id or command — fail open"
  echo '{}'
  exit 0
fi

# Only gate tmux-codex.sh invocations
if ! echo "$COMMAND" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh'; then
  echo '{}'
  exit 0
fi

# --approve is BLOCKED — only Codex can approve (via verdict in findings file)
# Workers must use --review-complete <findings_file>, which reads the verdict Codex wrote.
if echo "$COMMAND" | grep -qE 'tmux-codex\.sh +--approve'; then
  hook_log "codex-gate" "$SESSION_ID" "deny" "--approve blocked"
  cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: --approve is forbidden. Codex approval flows through --review-complete, which reads the verdict from the findings file Codex wrote. Do not self-approve."
  }
}
EOF
  exit 0
fi

# All other tmux-codex.sh commands pass through
hook_log "codex-gate" "$SESSION_ID" "allow" "codex command allowed"
echo '{}'
