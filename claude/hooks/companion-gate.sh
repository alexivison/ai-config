#!/usr/bin/env bash
# Companion Review Gate Hook
# Hard-blocks companion transport --approve — workers cannot self-approve.
# Companion approval flows through --review-complete (verdict in findings file).
# All other companion transport commands pass through freely.
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (cannot determine session_id/command or no companion configured)

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/party-cli.sh"

transport_pattern() {
  local script_pattern='([^ ]*/)?tmux-companion\.sh'
  printf '(^|[;&|] *)(%s|party-cli([[:space:]]+[^;&|]+)*[[:space:]]+transport([[:space:]]|$))' "$script_pattern"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
QUERY_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ] || [ -z "$COMMAND" ]; then
  hook_log "companion-gate" "${SESSION_ID:-unknown}" "allow" "missing session_id or command — fail open"
  echo '{}'
  exit 0
fi

COMPANION_NAME=$(party_cli_query "$QUERY_ROOT" "companion-name" 2>/dev/null || true)
if [ -z "$COMPANION_NAME" ]; then
  hook_log "companion-gate" "$SESSION_ID" "allow" "no companion configured — no gating needed"
  echo '{}'
  exit 0
fi

TRANSPORT_PATTERN=$(transport_pattern)

# Only gate companion transport invocations
if ! echo "$COMMAND" | grep -qE "$TRANSPORT_PATTERN"; then
  echo '{}'
  exit 0
fi

# --approve is BLOCKED — only the companion verdict in the findings file can approve.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])--approve([[:space:]]|$)'; then
  hook_log "companion-gate" "$SESSION_ID" "deny" "--approve blocked"
  cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: --approve is forbidden. Companion approval flows through --review-complete, which reads the verdict from the findings file the companion wrote. Do not self-approve."
  }
}
EOF
  exit 0
fi

hook_log "companion-gate" "$SESSION_ID" "allow" "companion command allowed"
echo '{}'
