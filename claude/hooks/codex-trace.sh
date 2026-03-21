#!/usr/bin/env bash
# Codex Trace Hook
# 1. Creates codex APPROVED evidence directly when --review-complete emits CODEX APPROVED
#    (happens when findings file contains VERDICT: APPROVED from Codex).
#    Requires CODEX_REVIEW_RAN sentinel in the same response as proof of review completion.
# 2. Creates triage override evidence when --triage-override emits TRIAGE_OVERRIDE
#
# Triggered: PostToolUse on Bash tool
# Fails open on errors

set -e

source "$(dirname "$0")/lib/evidence.sh"

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

cwd=$(echo "$hook_input" | jq -r '.cwd // ""' 2>/dev/null)
cwd=$(_resolve_cwd "$session_id" "$cwd")

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

# --- Evidence: Codex approval (via verdict in findings file) ---
# --review-complete emits both CODEX_REVIEW_RAN and CODEX APPROVED when findings
# contain VERDICT: APPROVED. The CODEX_REVIEW_RAN sentinel proves the review
# actually completed (findings file exists). We require it before writing approval.
if echo "$response" | grep -qx "CODEX APPROVED"; then
  if echo "$response" | grep -qx "CODEX_REVIEW_RAN"; then
    append_evidence "$session_id" "codex" "APPROVED" "$cwd"
    log_evidence "CODEX_APPROVED"
  else
    echo "BLOCKED: CODEX APPROVED without CODEX_REVIEW_RAN sentinel — review may not have completed" >&2
    log_evidence "CODEX_APPROVE_BLOCKED:no_review_ran"
  fi
fi

# --- Evidence: triage override (out-of-scope critic findings) ---
# --triage-override emits "TRIAGE_OVERRIDE <type> | <rationale>"
override_line=$(echo "$response" | grep "^TRIAGE_OVERRIDE .* | " | head -1)
if [ -n "$override_line" ]; then
  override_type=$(echo "$override_line" | awk '{print $2}')
  override_rationale=${override_line#*| }
  if [ -n "$override_type" ] && [ -n "$override_rationale" ]; then
    if append_triage_override "$session_id" "$override_type" "$override_rationale" "$cwd"; then
      log_evidence "TRIAGE_OVERRIDE:$override_type"
    else
      log_evidence "TRIAGE_OVERRIDE_REJECTED:$override_type"
    fi
  fi
fi

exit 0
