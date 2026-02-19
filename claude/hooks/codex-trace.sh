#!/usr/bin/env bash
# Codex Verdict Trace Hook
# Creates PR gate marker when codex-verdict.sh emits CODEX APPROVED
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

# Only match actual codex-verdict.sh invocations (not cat/grep/read/echo)
# Require path-prefixed execution at command position (start of line or after shell operator)
if ! echo "$command" | grep -qE '(^|[;&|] *)([^ ]*/)codex-verdict\.sh '; then
  exit 0
fi

# Verify the command succeeded (exit code 0)
exit_code=$(echo "$hook_input" | jq -r '.tool_exit_code // .exit_code // "0"' 2>/dev/null)
if [ "$exit_code" != "0" ]; then
  exit 0
fi

response=$(echo "$hook_input" | jq -r '.tool_response // ""' 2>/dev/null)
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"' 2>/dev/null)

if [ -z "$session_id" ] || [ "$session_id" = "unknown" ]; then
  exit 0
fi

# Exact token match — response from codex-verdict.sh is a single line
if echo "$response" | grep -qx "CODEX APPROVED"; then
  touch "/tmp/claude-codex-$session_id"
fi

exit 0
