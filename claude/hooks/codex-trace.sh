#!/usr/bin/env bash
# Wizard Trace Hook
# 1. Creates codex APPROVED evidence directly when --review-complete emits CODEX APPROVED
#    (happens when findings file contains VERDICT: APPROVED from The Wizard).
#    Requires CODEX_REVIEW_RAN sentinel in the same response as proof of review completion.
# 2. Creates triage override evidence when --triage-override emits TRIAGE_OVERRIDE
#
# Triggered: PostToolUse on Bash tool
# Fails open on errors

set -e

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/review-metrics.sh"

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

# --- Evidence: Wizard approval (via verdict in findings file) ---
# --review-complete emits both CODEX_REVIEW_RAN and CODEX APPROVED when findings
# contain VERDICT: APPROVED. The CODEX_REVIEW_RAN sentinel proves the review
# actually completed (findings file exists). We require it before writing approval.
codex_verdict=""
if echo "$response" | grep -qx "CODEX APPROVED"; then
  codex_verdict="APPROVED"
  if echo "$response" | grep -qx "CODEX_REVIEW_RAN"; then
    append_evidence "$session_id" "codex" "APPROVED" "$cwd"
    log_evidence "CODEX_APPROVED"
  else
    echo "BLOCKED: CODEX APPROVED without CODEX_REVIEW_RAN sentinel — review may not have completed" >&2
    log_evidence "CODEX_APPROVE_BLOCKED:no_review_ran"
  fi
elif echo "$response" | grep -qx "CODEX REQUEST_CHANGES"; then
  codex_verdict="REQUEST_CHANGES"
elif echo "$response" | grep -qx "CODEX VERDICT_MISSING"; then
  codex_verdict="VERDICT_MISSING"
fi

# --- Review metrics: extract finding details from Codex findings file ---
if echo "$response" | grep -qx "CODEX_REVIEW_RAN" && [ -n "$codex_verdict" ]; then
  # Extract findings file path from the --review-complete command
  findings_file=$(echo "$command" | grep -oE '[^ ]+\.(toon|findings)[^ ]*' | head -1)
  diff_hash=$(compute_diff_hash "$cwd")

  if [ -n "$findings_file" ] && [ -f "$findings_file" ]; then
    # Parse TOON findings format: findings[N]{...}: lines
    total_findings=$(grep -cE '^findings\[[0-9]+\]' "$findings_file" 2>/dev/null || echo 0)
    blocking_findings=$(grep -ciE 'severity:\s*(blocking|critical|high)' "$findings_file" 2>/dev/null || echo 0)
    non_blocking_findings=$((total_findings - blocking_findings))
    [ "$non_blocking_findings" -lt 0 ] && non_blocking_findings=0

    # Record individual findings if parseable
    finding_idx=0
    while IFS= read -r line; do
      finding_idx=$((finding_idx + 1))
      fid="codex-${finding_idx}"
      # Extract fields from TOON format: findings[N]{id:X,file:Y,line:Z,severity:S,category:C,description:D}:
      f_severity=$(echo "$line" | grep -oE 'severity:[^,}]+' | head -1 | sed 's/severity://')
      f_category=$(echo "$line" | grep -oE 'category:[^,}]+' | head -1 | sed 's/category://')
      f_file=$(echo "$line" | grep -oE 'file:[^,}]+' | head -1 | sed 's/file://')
      f_line=$(echo "$line" | grep -oE 'line:[^,}]+' | head -1 | sed 's/line://')
      f_desc=$(echo "$line" | grep -oE 'description:[^}]+' | head -1 | sed 's/description://')
      # Normalize severity
      case "$f_severity" in
        critical|high|blocking) f_severity="blocking" ;;
        medium|low|"") f_severity="non-blocking" ;;
        *) f_severity="advisory" ;;
      esac
      record_finding_raised "$session_id" "codex" "$fid" "$f_severity" \
        "${f_category:-other}" "${f_file:-}" "${f_line:-}" "${f_desc:-}" "$diff_hash"
    done < <(grep -E '^findings\[[0-9]+\]' "$findings_file" 2>/dev/null || true)

    # Always record a summary even if individual parsing got nothing
    record_findings_summary "$session_id" "codex" "$diff_hash" "$codex_verdict" \
      "$total_findings" "$blocking_findings" "$non_blocking_findings"
  else
    # No findings file accessible — record summary from verdict alone
    record_findings_summary "$session_id" "codex" "$diff_hash" "$codex_verdict" "0" "0" "0"
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
