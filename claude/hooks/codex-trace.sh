#!/usr/bin/env bash
# Codex Trace Hook
# 1. Creates codex-ran evidence marker when tmux-codex.sh --review-complete emits CODEX_REVIEW_RAN
# 2. Creates PR gate marker when tmux-codex.sh --approve emits CODEX APPROVED
#    (only if codex-ran evidence exists — prevents self-declared approval)
#
# Triggered: PostToolUse on Bash tool
# Fails open on errors

set -e

hook_input=$(cat)

# Validate JSON input — fail open on parse errors
if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

command=$(echo "$hook_input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Verify the command succeeded (exit code 0).
# Exit code may be at top level or nested in tool_response object.
# Use try-catch to avoid crashing on string tool_response.
exit_code=$(echo "$hook_input" | jq -r '(.tool_exit_code // .exit_code // (try .tool_response.exit_code catch null) // "0") | tostring' 2>/dev/null)
if [ "$exit_code" != "0" ]; then
  exit 0
fi

session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"' 2>/dev/null)
if [ -z "$session_id" ] || [ "$session_id" = "unknown" ]; then
  exit 0
fi

# Only trace tmux-codex.sh invocations
if ! echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)?tmux-codex\.sh'; then
  exit 0
fi

# Extract stdout from tool_response.
# Bash tool_response may be a string or an object {"stdout":"...","stderr":"...",...}.
response_type=$(echo "$hook_input" | jq -r '.tool_response | type' 2>/dev/null)
if [ "$response_type" = "object" ]; then
  response=$(echo "$hook_input" | jq -r '.tool_response.stdout // ""' 2>/dev/null)
elif [ "$response_type" = "string" ]; then
  response=$(echo "$hook_input" | jq -r '.tool_response // ""' 2>/dev/null)
else
  response=""
fi

# One-line evidence log for quick grep debugging
ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
log_evidence() { echo "$ts | codex-trace | $1 | $session_id" >> "$HOME/.claude/logs/evidence-trace.log"; }

# --- Evidence marker: codex review actually completed ---
# tmux-codex.sh --review-complete emits CODEX_REVIEW_RAN after verifying findings file exists
if echo "$response" | grep -qx "CODEX_REVIEW_RAN"; then
  touch "/tmp/claude-codex-ran-$session_id"
  log_evidence "CODEX_REVIEW_RAN"
  exit 0
fi

# --- Verdict marker: tmux-codex.sh --approve ---
if echo "$response" | grep -qx "CODEX APPROVED"; then
  # Gate: only create approval marker if codex was actually run
  if [ -f "/tmp/claude-codex-ran-$session_id" ]; then
    touch "/tmp/claude-codex-$session_id"
    log_evidence "CODEX_APPROVED"
  else
    echo "BLOCKED: tmux-codex.sh --approve called without evidence of codex review completion"
    log_evidence "CODEX_APPROVE_BLOCKED"
  fi
fi

exit 0
