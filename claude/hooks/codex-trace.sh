#!/usr/bin/env bash
# Codex Trace Hook
# 1. Creates codex-ran evidence marker when call_codex.sh is invoked
# 2. Creates PR gate marker when codex-verdict.sh emits CODEX APPROVED
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

# --- Evidence marker: codex review actually completed ---
# Requires BOTH: (1) anchored command match (call_codex.sh at command position, --review as first arg)
#                (2) output contains sentinel emitted only by the script on review success
# Neither alone suffices: echo forgery fails (1), prompt-with-sentinel fails (1), sentinel-only fails (1).
response=$(echo "$hook_input" | jq -r '.tool_response // ""' 2>/dev/null)
if echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)call_codex\.sh +--review( |[;&|]|$)' && echo "$response" | grep -qx "CODEX_REVIEW_RAN"; then
  touch "/tmp/claude-codex-ran-$session_id"
  exit 0
fi

# --- Verdict marker: codex-verdict.sh approve ---
# Only match actual codex-verdict.sh invocations (not cat/grep/read/echo)
# Require path-prefixed execution at command position (start of line or after shell operator)
if ! echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)codex-verdict\.sh '; then
  exit 0
fi

# Exact token match — response from codex-verdict.sh is a single line
# (response already parsed above for evidence check)
if echo "$response" | grep -qx "CODEX APPROVED"; then
  # Gate: only create approval marker if codex was actually run
  if [ -f "/tmp/claude-codex-ran-$session_id" ]; then
    touch "/tmp/claude-codex-$session_id"
  else
    echo "BLOCKED: codex-verdict.sh approve called without evidence of call_codex.sh invocation"
  fi
fi

exit 0
