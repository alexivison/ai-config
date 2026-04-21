#!/usr/bin/env bash
# SubagentStop Hook — logs sub-agent completion with verdict detection + markers
#
# Triggered: SubagentStop (replaces PostToolUse Agent matcher)
# Input: JSON via stdin with agent_id, agent_type, last_assistant_message, session_id, cwd
#
# SubagentStop provides last_assistant_message directly — no need to parse
# content-block arrays or strip agentId/usage metadata from tool_response.

set -e

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"
mkdir -p "$(dirname "$TRACE_FILE")"

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/oscillation.sh"
source "$(dirname "$0")/lib/review-metrics.sh"

hook_input=$(cat)

if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  hook_log "agent-trace-stop" "unknown" "error" "invalid JSON input"
  exit 0
fi

agent_type=$(echo "$hook_input" | jq -r '.agent_type // "unknown"')
agent_id=$(echo "$hook_input" | jq -r '.agent_id // "unknown"')
session_id=$(echo "$hook_input" | jq -r '.session_id // "unknown"')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')
cwd=$(_resolve_cwd "$session_id" "$cwd")
project=$(basename "$cwd")

# last_assistant_message is a clean string — no content-block parsing needed
response=$(echo "$hook_input" | jq -r '.last_assistant_message // ""')

# ── Verdict detection ──
# Scan only the tail to avoid false positives from "APPROVE" in prose
verdict_region=$(echo "$response" | tail -c 1000)
verdict="unknown"

if echo "$verdict_region" | grep -qE '\*\*REQUEST_CHANGES\*\*|^REQUEST_CHANGES'; then
  verdict="REQUEST_CHANGES"
elif echo "$verdict_region" | grep -qE '\*\*NEEDS_DISCUSSION\*\*|^NEEDS_DISCUSSION'; then
  verdict="NEEDS_DISCUSSION"
elif echo "$verdict_region" | grep -qE '\*\*APPROVE\*\*|^APPROVE'; then
  verdict="APPROVED"
elif echo "$verdict_region" | grep -qi "SKIP"; then
  verdict="SKIP"
elif echo "$verdict_region" | grep -qiE '\bCRITICAL\b|\bHIGH\b'; then
  verdict="ISSUES_FOUND"
elif echo "$verdict_region" | grep -qiE '\bFAIL\b'; then
  verdict="FAIL"
elif echo "$verdict_region" | grep -qiE '\bPASS\b'; then
  verdict="PASS"
elif echo "$verdict_region" | grep -qiE '\bCLEAN\b'; then
  verdict="CLEAN"
elif echo "$verdict_region" | grep -qi "complete\|done\|finished"; then
  verdict="PASS"
fi

# Fallback: scan full response for short agent outputs (e.g. minimizer APPROVE)
if [ "$verdict" = "unknown" ] && [ -n "$response" ]; then
  if echo "$response" | grep -qE '\*\*REQUEST_CHANGES\*\*|^REQUEST_CHANGES'; then
    verdict="REQUEST_CHANGES"
  elif echo "$response" | grep -qE '\*\*NEEDS_DISCUSSION\*\*|^NEEDS_DISCUSSION'; then
    verdict="NEEDS_DISCUSSION"
  elif echo "$response" | grep -qE '\*\*APPROVE\*\*|^APPROVE'; then
    verdict="APPROVED"
  elif echo "$response" | grep -qiE '\bFAIL\b'; then
    verdict="FAIL"
  elif echo "$response" | grep -qiE '\bPASS\b'; then
    verdict="PASS"
  fi
fi

# ── Trace entry ──
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

trace_entry=$(jq -cn \
  --arg ts "$timestamp" \
  --arg session "$session_id" \
  --arg project "$project" \
  --arg agent "$agent_type" \
  --arg agent_id "$agent_id" \
  --arg verdict "$verdict" \
  --arg event "stop" \
  '{
    timestamp: $ts,
    event: $event,
    session: $session,
    project: $project,
    agent: $agent,
    agent_id: $agent_id,
    verdict: $verdict
  }')

echo "$trace_entry" >> "$TRACE_FILE"
echo "$timestamp | STOP  | $agent_type | $verdict | $agent_id | $session_id" >> "$HOME/.claude/logs/evidence-trace.log"
hook_log "agent-trace-stop" "$session_id" "allow" "agent=$agent_type verdict=$verdict"

# ── Evidence for PR gate enforcement ──

if [ "$agent_type" = "code-critic" ] && [ "$verdict" = "APPROVED" ]; then
  append_evidence "$session_id" "code-critic" "APPROVED" "$cwd"
fi

if [ "$agent_type" = "minimizer" ] && [ "$verdict" = "APPROVED" ]; then
  append_evidence "$session_id" "minimizer" "APPROVED" "$cwd"
fi

if [ "$agent_type" = "requirements-auditor" ] && [ "$verdict" = "APPROVED" ]; then
  append_evidence "$session_id" "requirements-auditor" "APPROVED" "$cwd"
fi

if [ "$agent_type" = "test-runner" ] && [ "$verdict" = "PASS" ]; then
  append_evidence "$session_id" "test-runner" "PASS" "$cwd"
fi

if [ "$agent_type" = "check-runner" ]; then
  if [ "$verdict" = "PASS" ] || [ "$verdict" = "CLEAN" ]; then
    append_evidence "$session_id" "check-runner" "$verdict" "$cwd"
  fi
fi

# ── Oscillation detection for critics (delegated to lib/oscillation.sh) ──
if [ "$agent_type" = "code-critic" ] || [ "$agent_type" = "minimizer" ] || [ "$agent_type" = "requirements-auditor" ]; then
  detect_oscillation "$session_id" "$agent_type" "$verdict" "$response" "$cwd"
fi

# ── Review metrics: extract findings and record triage from reviewer responses ──
case "$agent_type" in
  code-critic|minimizer|requirements-auditor|deep-reviewer)
    if [ -n "$response" ]; then
      diff_hash=$(compute_diff_hash "$cwd")

      # --- Count findings by severity ---
      blocking_count=$(echo "$response" | grep -ciE '\[must\]|\*\*blocking\*\*|\bblocking:' || true)
      blocking_count=${blocking_count:-0}
      non_blocking_count=$(echo "$response" | grep -ciE '\[should\]|\[nit\]|\[q\]|\*\*non-blocking\*\*|\bnon-blocking:' || true)
      non_blocking_count=${non_blocking_count:-0}
      total_count=$((blocking_count + non_blocking_count))

      # Fallback: estimate from numbered list items in REQUEST_CHANGES
      if [ "$total_count" -eq 0 ] && [ "$verdict" = "REQUEST_CHANGES" ]; then
        total_count=$(echo "$response" | grep -cE '^\s*[0-9]+\.\s' || true)
        total_count=${total_count:-0}
        blocking_count="$total_count"
      fi

      excerpt=$(echo "$response" | tail -c 500 | head -c 200 | tr '\n' ' ')
      record_findings_summary "$session_id" "$agent_type" "$diff_hash" "$verdict" \
        "$total_count" "$blocking_count" "$non_blocking_count" "$excerpt"

      # --- Extract individual findings and record triage ---
      # Parse structured findings: "- **file:line** - [tag] description"
      # Also matches "- **`file:line`** -" and bold headers like "**file:line** —"
      finding_idx=0
      current_section=""

      while IFS= read -r line; do
        # Track section headers (### Must Fix, ### Questions, ### Nits, etc.)
        if echo "$line" | grep -qE '^#{1,3}\s'; then
          section_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
          case "$section_lower" in
            *"must fix"*|*"must"*)   current_section="must" ;;
            *"question"*)            current_section="question" ;;
            *"nit"*)                 current_section="nit" ;;
            *)                       current_section="" ;;
          esac
          continue
        fi

        # Match finding lines: "- **file:line** - description" or "- **`file:line`** — description"
        if ! echo "$line" | grep -qE '^\s*-\s+\*\*'; then
          continue
        fi

        finding_idx=$((finding_idx + 1))
        fid="${agent_type:0:2}-${finding_idx}"

        # Extract file path and line from **file:line** or **`file:line`**
        f_file="" ; f_line="" ; f_desc=""
        if [[ "$line" =~ \*\*\`?([^\`]+)\`?\*\* ]]; then
          f_file="${BASH_REMATCH[1]}"
          f_file="${f_file%"${f_file##*[![:space:]]}"}" # trim trailing whitespace
          if [[ "$f_file" =~ :([0-9][-0-9]*) ]]; then
            f_line="${BASH_REMATCH[1]}"
            f_file="${f_file%%:${f_line}*}"
          fi
        fi

        # Extract description (everything after the second - or —)
        if [[ "$line" =~ \*\*.*\*\*[[:space:]]*[-—][[:space:]]*(.*) ]]; then
          f_desc="${BASH_REMATCH[1]}"
        fi

        # Determine severity from section or inline tags
        f_severity="non-blocking"
        f_action="noted"
        if [ "$current_section" = "must" ] || echo "$line" | grep -qiE '\[must\]|\*\*blocking\*\*'; then
          f_severity="blocking"
          f_action="fix"
        elif echo "$line" | grep -qiE '\[q\]|\[should\]'; then
          f_severity="non-blocking"
          f_action="noted"
        elif echo "$line" | grep -qiE '\[nit\]'; then
          f_severity="non-blocking"
          f_action="noted"
        elif [ "$current_section" = "nit" ] || [ "$current_section" = "question" ]; then
          f_severity="non-blocking"
          f_action="noted"
        fi

        # Detect category from inline tags
        f_category="other"
        case "$line" in
          *"[SRP]"*)          f_category="srp" ;;
          *"[DRY]"*)          f_category="dry" ;;
          *"[YAGNI]"*)        f_category="bloat" ;;
          *"[KISS]"*)         f_category="complexity" ;;
          *"[LoB]"*)          f_category="locality" ;;
          *orrectness*)       f_category="correctness" ;;
          *ecurity*)          f_category="security" ;;
          *"[Tests]"*|*"test "*|*"Test "*) f_category="testing" ;;
          *ead*code*|*nused*) f_category="bloat" ;;
        esac

        # Record individual finding
        record_finding_raised "$session_id" "$agent_type" "$fid" "$f_severity" \
          "$f_category" "${f_file:-}" "${f_line:-}" "${f_desc:0:200}" "$diff_hash"

        # Record triage decision
        record_triage "$session_id" "$fid" "$agent_type" "$f_severity" "$f_action"

      done <<< "$response"

      # --- Record resolutions for prior findings when reviewer approves ---
      # If this pass APPROVED, resolve all prior unresolved findings from this source as "fixed"
      if [ "$verdict" = "APPROVED" ]; then
        metrics_f=$(metrics_file "$session_id")
        if [ -f "$metrics_f" ]; then
          # Find finding_ids from prior passes of this source that were triaged as "fix"
          # but have no "resolved" event yet
          prior_fix_ids=$(jq -r --arg src "$agent_type" '
            select(.event == "triage" and .source == $src and .action == "fix") | .finding_id
          ' "$metrics_f" 2>/dev/null | sort -u)

          resolved_ids=$(jq -r --arg src "$agent_type" '
            select(.event == "resolved" and .source == $src) | .finding_id
          ' "$metrics_f" 2>/dev/null | sort -u)

          for fix_id in $prior_fix_ids; do
            if ! echo "$resolved_ids" | grep -qxF "$fix_id"; then
              record_resolution "$session_id" "$fix_id" "$agent_type" "fixed" "$diff_hash"
            fi
          done
        fi
      fi
    fi
    ;;
esac

exit 0
