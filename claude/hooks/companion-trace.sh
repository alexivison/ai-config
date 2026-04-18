#!/usr/bin/env bash
# Companion Trace Hook
# 1. Creates companion APPROVED evidence directly when --review-complete emits
#    COMPANION APPROVED (happens when findings file contains VERDICT: APPROVED
#    from the companion).
#    Requires COMPANION_REVIEW_RAN in the same response as proof of review completion.
# 2. Creates triage override evidence when --triage-override emits TRIAGE_OVERRIDE
#
# Triggered: PostToolUse on Bash tool
# Fails open on errors

set -e

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/party-cli.sh"
source "$(dirname "$0")/lib/review-metrics.sh"

transport_pattern() {
  local script_pattern='([^ ]*/)?tmux-companion\.sh'
  printf '(^|[;&|] *)(%s|party-cli([[:space:]]+[^;&|]+)*[[:space:]]+transport([[:space:]]|$))' "$script_pattern"
}

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

COMPANION_NAME=$(party_cli_query "$cwd" "companion-name" 2>/dev/null || true)
if [ -z "$COMPANION_NAME" ]; then
  COMPANION_NAME="codex"
fi
TRANSPORT_PATTERN=$(transport_pattern)
REVIEW_SOURCE="$COMPANION_NAME"

# Only trace companion transport invocations
if ! echo "$command" | grep -qE "$TRANSPORT_PATTERN"; then
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
log_evidence() { echo "$ts | companion-trace | $1 | $session_id" >> "$HOME/.claude/logs/evidence-trace.log"; }

# --- Evidence: companion approval (via verdict in findings file) ---
# --review-complete emits both COMPANION_REVIEW_RAN and COMPANION APPROVED when
# findings contain VERDICT: APPROVED. COMPANION_REVIEW_RAN proves the review
# actually completed (findings file exists). We require it before writing approval.
review_verdict=""
if echo "$response" | grep -qx "COMPANION APPROVED"; then
  review_verdict="APPROVED"
  if echo "$response" | grep -qx "COMPANION_REVIEW_RAN"; then
    append_evidence "$session_id" "$REVIEW_SOURCE" "APPROVED" "$cwd"
    log_evidence "COMPANION_APPROVED"
    # Resolve all prior unresolved companion findings as "fixed"
    metrics_f=$(metrics_file "$session_id")
    if [ -f "$metrics_f" ]; then
      review_dh=$(compute_diff_hash "$cwd")
      prior_fix_ids=$(jq -r --arg source "$REVIEW_SOURCE" 'select(.event == "triage" and .source == $source and .action == "fix") | .finding_id' "$metrics_f" 2>/dev/null | sort -u)
      resolved_ids=$(jq -r --arg source "$REVIEW_SOURCE" 'select(.event == "resolved" and .source == $source) | .finding_id' "$metrics_f" 2>/dev/null | sort -u)
      for fix_id in $prior_fix_ids; do
        if ! echo "$resolved_ids" | grep -qxF "$fix_id"; then
          record_resolution "$session_id" "$fix_id" "$REVIEW_SOURCE" "fixed" "$review_dh"
        fi
      done
    fi
  else
    echo "BLOCKED: COMPANION APPROVED without COMPANION_REVIEW_RAN — review may not have completed" >&2
    log_evidence "COMPANION_APPROVE_BLOCKED:no_review_ran"
  fi
elif echo "$response" | grep -qx "COMPANION REQUEST_CHANGES"; then
  review_verdict="REQUEST_CHANGES"
elif echo "$response" | grep -qx "COMPANION VERDICT_MISSING"; then
  review_verdict="VERDICT_MISSING"
fi

# --- Review metrics: extract finding details from companion findings file ---
if echo "$response" | grep -qx "COMPANION_REVIEW_RAN" && [ -n "$review_verdict" ]; then
  # Extract findings file path from the --review-complete command
  findings_file=$(echo "$command" | grep -oE '[^ ]+\.(toon|findings)[^ ]*' | head -1)
  diff_hash=$(compute_diff_hash "$cwd")

  if [ -n "$findings_file" ] && [ -f "$findings_file" ]; then
    # Parse canonical TOON format: header "findings[N]{fields}:" + indented CSV rows
    # Extract field order from the header line
    header=$(grep -E '^findings\[[0-9]+\]' "$findings_file" 2>/dev/null | head -1 || true)
    # Count data rows (indented lines after header, before summary/stats)
    total_findings=$(sed -n '/^findings\[/,/^[^ ]/{ /^  /p; }' "$findings_file" 2>/dev/null | wc -l | tr -d ' ')
    total_findings=${total_findings:-0}

    # Parse field positions from header: findings[N]{id,file,line,severity,...}:
    field_list=""
    if [ -n "$header" ]; then
      field_list=$(echo "$header" | sed 's/^findings\[[0-9]*\]{\(.*\)}:$/\1/')
    fi

    # Find severity field position (1-indexed)
    sev_pos=0
    if [ -n "$field_list" ]; then
      idx=0
      IFS=',' read -ra hfields <<< "$field_list"
      for f in "${hfields[@]}"; do
        idx=$((idx + 1))
        if [ "$f" = "severity" ]; then sev_pos=$idx; break; fi
      done
    fi

    # Parse individual finding rows
    blocking_findings=0
    finding_idx=0
    while IFS= read -r row; do
      row=$(echo "$row" | sed 's/^  *//')  # strip leading indent
      [ -z "$row" ] && continue
      finding_idx=$((finding_idx + 1))
      fid="${REVIEW_SOURCE}-${finding_idx}"

      # Extract fields using Python for correct CSV parsing (handles quoted commas)
      f_file="" ; f_line="" ; f_severity="" ; f_category="" ; f_desc=""
      if [ -n "$field_list" ]; then
        parsed=$(python3 -c "
import csv, json, sys, io
fields = '$field_list'.split(',')
row = sys.stdin.read().strip()
reader = csv.reader(io.StringIO(row))
for parts in reader:
    result = {}
    for i, f in enumerate(fields):
        if i < len(parts):
            result[f] = parts[i]
    print(json.dumps(result))
    break
" <<< "$row" 2>/dev/null || echo "{}")
        f_file=$(echo "$parsed" | jq -r '.file // ""')
        f_line=$(echo "$parsed" | jq -r '.line // ""')
        f_severity=$(echo "$parsed" | jq -r '.severity // ""')
        f_category=$(echo "$parsed" | jq -r '.category // ""')
        f_desc=$(echo "$parsed" | jq -r '.description // ""')
      fi

      # Normalize severity
      case "$f_severity" in
        critical|high|blocking) f_severity="blocking"; blocking_findings=$((blocking_findings + 1)) ;;
        medium|low|"") f_severity="non-blocking" ;;
        *) f_severity="advisory" ;;
      esac
      record_finding_raised "$session_id" "$REVIEW_SOURCE" "$fid" "$f_severity" \
        "${f_category:-other}" "${f_file:-}" "${f_line:-}" "${f_desc:-}" "$diff_hash"

      # Record triage: blocking findings get "fix", others get "noted"
      f_action="noted"
      if [ "$f_severity" = "blocking" ]; then f_action="fix"; fi
      record_triage "$session_id" "$fid" "$REVIEW_SOURCE" "$f_severity" "$f_action"
    done < <(sed -n '/^findings\[/,/^[^ ]/{ /^  /p; }' "$findings_file" 2>/dev/null || true)

    non_blocking_findings=$((total_findings - blocking_findings))
    [ "$non_blocking_findings" -lt 0 ] && non_blocking_findings=0

    # Always record a summary even if individual parsing got nothing
    record_findings_summary "$session_id" "$REVIEW_SOURCE" "$diff_hash" "$review_verdict" \
      "$total_findings" "$blocking_findings" "$non_blocking_findings"
  else
    # No findings file accessible — record summary from verdict alone
    record_findings_summary "$session_id" "$REVIEW_SOURCE" "$diff_hash" "$review_verdict" "0" "0" "0"
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
      # Record as out-of-scope triage + overridden resolution
      record_triage "$session_id" "override-${override_type}" "$override_type" "out-of-scope" "dismissed" "$override_rationale"
      record_resolution "$session_id" "override-${override_type}" "$override_type" "overridden" "" "$override_rationale"
    else
      log_evidence "TRIAGE_OVERRIDE_REJECTED:$override_type"
    fi
  fi
fi

exit 0
