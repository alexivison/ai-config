#!/usr/bin/env bash
# Codex Trace Hook
# 1. Creates codex-ran evidence marker when tmux-codex.sh --review-complete emits CODEX_REVIEW_RAN
# 2. Creates PR gate marker when tmux-codex.sh --approve emits CODEX APPROVED
#    (only if codex-ran evidence exists — prevents self-declared approval)
#
# Triggered: PostToolUse on Bash tool
# Fails open on errors (mirrors agent-trace.sh pattern)

set -e

hook_input=$(cat)

# Validate JSON input — fail open on parse errors
if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

command=$(echo "$hook_input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Verify the command succeeded (exit code 0)
exit_code=$(echo "$hook_input" | jq -r '.tool_exit_code // .exit_code // "0"' 2>/dev/null)
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

response=$(echo "$hook_input" | jq -r '.tool_response // ""' 2>/dev/null)

# --- Evidence marker: codex review actually completed ---
# tmux-codex.sh --review-complete emits CODEX_REVIEW_RAN after verifying findings file exists
if echo "$response" | grep -qx "CODEX_REVIEW_RAN"; then
  touch "/tmp/claude-codex-ran-$session_id"
  exit 0
fi

# --- Re-review: delete codex-ran marker to force new review cycle ---
# Without this, --re-review leaves codex-ran alive, allowing --approve
# to bypass the gate without a second Codex pass.
# Prefix match (not -qx) because --re-review appends a reason string.
if echo "$response" | grep -q "^CODEX REQUEST_CHANGES"; then
  rm -f "/tmp/claude-codex-ran-$session_id"
  rm -f "/tmp/claude-codex-$session_id"
  exit 0
fi

# --- Verdict marker: tmux-codex.sh --approve ---
if echo "$response" | grep -qx "CODEX APPROVED"; then
  # Gate: only create approval marker if codex was actually run
  if [ -f "/tmp/claude-codex-ran-$session_id" ]; then
    touch "/tmp/claude-codex-$session_id"
  else
    echo "BLOCKED: tmux-codex.sh --approve called without evidence of codex review completion"
  fi
fi

exit 0
