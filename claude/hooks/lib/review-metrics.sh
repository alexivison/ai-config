#!/usr/bin/env bash
# review-metrics.sh — Review effectiveness metrics for the PR gate system
#
# Tracks the full lifecycle of review findings:
#   finding_raised → triage → resolution
#
# Each event is a JSONL entry in ~/.claude/logs/review-metrics/{session_id}.jsonl.
# Persistent across reboots for long-term review effectiveness analysis.
#
# Usage: source "$(dirname "$0")/lib/review-metrics.sh"
#   (evidence.sh must be sourced first for compute_diff_hash, _resolve_cwd, _atomic_append)

# ── Shell guard ──
if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: review-metrics.sh must be sourced from bash" >&2
  return 1 2>/dev/null || exit 1
fi

# ── Storage directory ──

_METRICS_DIR="${HOME}/.claude/logs/review-metrics"
mkdir -p "$_METRICS_DIR" 2>/dev/null || true

# ── Path helper ──

metrics_file() {
  local session_id="$1"
  echo "${_METRICS_DIR}/${session_id}.jsonl"
}

# ── Internal: atomic append to metrics file ──

_metrics_append() {
  local session_id="$1" entry="$2"
  local file
  file=$(metrics_file "$session_id")
  _atomic_append "$file" "$entry" "$session_id"
}

# ── Event: finding raised ──
# Called when a reviewer (sub-agent or Codex) produces a finding.
#
# Args: session_id source finding_id severity category file line description diff_hash
#   source:      code-critic | minimizer | requirements-auditor | deep-reviewer | codex
#   finding_id:  unique within session (e.g., "cc-1", "codex-3")
#   severity:    blocking | non-blocking | advisory
#   category:    bug | security | style | bloat | scope | correctness | other
#   file:        file path (or "" if not file-specific)
#   line:        line number (or "" if not line-specific)
#   description: short finding description
#   diff_hash:   diff hash at time of finding

record_finding_raised() {
  local session_id="$1" source="$2" finding_id="$3" severity="$4" \
        category="$5" file="$6" line="$7" description="$8" diff_hash="$9"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg session "$session_id" \
    --arg event "finding_raised" \
    --arg source "$source" \
    --arg fid "$finding_id" \
    --arg severity "$severity" \
    --arg category "$category" \
    --arg file "$file" \
    --arg line "$line" \
    --arg desc "$description" \
    --arg hash "$diff_hash" \
    '{timestamp: $ts, session: $session, event: $event, source: $source,
      finding_id: $fid, severity: $severity, category: $category,
      file: $file, line: $line, description: $desc, diff_hash: $hash}')

  _metrics_append "$session_id" "$entry"
}

# ── Event: bulk findings raised ──
# Convenience for recording a batch summary when individual parsing isn't possible.
# Records one entry per source with counts instead of individual findings.
#
# Args: session_id source diff_hash verdict total_findings blocking_count
#       non_blocking_count [response_excerpt]

record_findings_summary() {
  local session_id="$1" source="$2" diff_hash="$3" verdict="$4" \
        total="$5" blocking="$6" non_blocking="$7" excerpt="${8:-}"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Auto-compute iteration number: count prior findings_summary events for this source
  local iteration=1
  local file
  file=$(metrics_file "$session_id")
  if [ -f "$file" ]; then
    local prior
    prior=$(jq -s --arg src "$source" \
      '[.[] | select(.event == "findings_summary" and .source == $src)] | length' "$file" 2>/dev/null || echo 0)
    iteration=$((prior + 1))
  fi

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg session "$session_id" \
    --arg event "findings_summary" \
    --arg source "$source" \
    --arg hash "$diff_hash" \
    --arg verdict "$verdict" \
    --argjson total "${total:-0}" \
    --argjson blocking "${blocking:-0}" \
    --argjson non_blocking "${non_blocking:-0}" \
    --argjson iteration "$iteration" \
    --arg excerpt "$excerpt" \
    '{timestamp: $ts, session: $session, event: $event, source: $source,
      diff_hash: $hash, verdict: $verdict, total_findings: $total,
      blocking: $blocking, non_blocking: $non_blocking, iteration: $iteration,
      excerpt: $excerpt}')

  _metrics_append "$session_id" "$entry"
}

# ── Event: finding triaged ──
# Called when Claude classifies a finding.
#
# Args: session_id finding_id source classification action [rationale]
#   classification: blocking | non-blocking | out-of-scope
#   action:         fix | noted | dismissed | debate

record_triage() {
  local session_id="$1" finding_id="$2" source="$3" classification="$4" \
        action="$5" rationale="${6:-}"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg session "$session_id" \
    --arg event "triage" \
    --arg fid "$finding_id" \
    --arg source "$source" \
    --arg classification "$classification" \
    --arg action "$action" \
    --arg rationale "$rationale" \
    '{timestamp: $ts, session: $session, event: $event, finding_id: $fid,
      source: $source, classification: $classification, action: $action,
      rationale: $rationale}')

  _metrics_append "$session_id" "$entry"
}

# ── Event: finding resolved ──
# Called when a finding reaches its final state.
#
# Args: session_id finding_id source resolution [diff_hash] [detail]
#   resolution: fixed | dismissed | debated | overridden | accepted | escalated

record_resolution() {
  local session_id="$1" finding_id="$2" source="$3" resolution="$4" \
        diff_hash="${5:-}" detail="${6:-}"

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg session "$session_id" \
    --arg event "resolved" \
    --arg fid "$finding_id" \
    --arg source "$source" \
    --arg resolution "$resolution" \
    --arg hash "$diff_hash" \
    --arg detail "$detail" \
    '{timestamp: $ts, session: $session, event: $event, finding_id: $fid,
      source: $source, resolution: $resolution, diff_hash: $hash, detail: $detail}')

  _metrics_append "$session_id" "$entry"
}

# ── Event: review cycle complete ──
# Summary event at the end of a full review pass (critics + codex).
#
# Args: session_id cycle_number diff_hash

record_review_cycle() {
  local session_id="$1" cycle="$2" diff_hash="$3"

  local file
  file=$(metrics_file "$session_id")
  [ -f "$file" ] || return 0

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Compute stats from current metrics file
  local raised triaged fixed dismissed noted debated overridden
  raised=$(jq -s --arg hash "$diff_hash" \
    '[.[] | select(.event == "finding_raised" and .diff_hash == $hash)] | length' "$file" 2>/dev/null || echo 0)
  triaged=$(jq -s \
    '[.[] | select(.event == "triage")] | length' "$file" 2>/dev/null || echo 0)
  fixed=$(jq -s \
    '[.[] | select(.event == "resolved" and .resolution == "fixed")] | length' "$file" 2>/dev/null || echo 0)
  dismissed=$(jq -s \
    '[.[] | select(.event == "resolved" and .resolution == "dismissed")] | length' "$file" 2>/dev/null || echo 0)
  noted=$(jq -s \
    '[.[] | select(.event == "triage" and .action == "noted")] | length' "$file" 2>/dev/null || echo 0)
  debated=$(jq -s \
    '[.[] | select(.event == "resolved" and .resolution == "debated")] | length' "$file" 2>/dev/null || echo 0)
  overridden=$(jq -s \
    '[.[] | select(.event == "resolved" and .resolution == "overridden")] | length' "$file" 2>/dev/null || echo 0)

  local entry
  entry=$(jq -cn \
    --arg ts "$timestamp" \
    --arg session "$session_id" \
    --arg event "review_cycle" \
    --argjson cycle "$cycle" \
    --arg hash "$diff_hash" \
    --argjson raised "$raised" \
    --argjson triaged "$triaged" \
    --argjson fixed "$fixed" \
    --argjson dismissed "$dismissed" \
    --argjson noted "$noted" \
    --argjson debated "$debated" \
    --argjson overridden "$overridden" \
    '{timestamp: $ts, session: $session, event: $event, cycle: $cycle,
      diff_hash: $hash, findings_raised: $raised, triaged: $triaged,
      fixed: $fixed, dismissed: $dismissed, noted: $noted,
      debated: $debated, overridden: $overridden}')

  _metrics_append "$session_id" "$entry"
}

# ── Query: generate session report ──
# Outputs a human-readable summary of review effectiveness for a session.
# Args: session_id

generate_report() {
  local session_id="$1"
  local file
  file=$(metrics_file "$session_id")

  if [ ! -f "$file" ]; then
    echo "No metrics found for session: $session_id"
    return 1
  fi

  echo "═══════════════════════════════════════════════════════════════"
  echo " Review Metrics Report — Session: $session_id"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # ── Per-source breakdown ──
  echo "── Findings by Source ──"
  echo ""
  local sources
  sources=$(jq -r 'select(.event == "finding_raised") | .source' "$file" 2>/dev/null | sort -u)

  if [ -z "$sources" ]; then
    echo "  (no individual findings recorded — check summaries below)"
    echo ""
  else
    for src in $sources; do
      local count
      count=$(jq -s --arg src "$src" \
        '[.[] | select(.event == "finding_raised" and .source == $src)] | length' "$file" 2>/dev/null)
      echo "  $src: $count"
    done
    echo ""
  fi

  # ── Summary events ──
  local summary_count
  summary_count=$(jq -s '[.[] | select(.event == "findings_summary")] | length' "$file" 2>/dev/null || echo 0)
  if [ "$summary_count" -gt 0 ]; then
    echo "── Review Pass Log ──"
    echo ""
    jq -r 'select(.event == "findings_summary") |
      "  \(.source) pass \(.iteration // "?") | verdict: \(.verdict) | total: \(.total_findings) | blocking: \(.blocking) | non-blocking: \(.non_blocking)"' "$file" 2>/dev/null
    echo ""

    # ── Iterations to approval ──
    echo "── Iterations to Approval ──"
    echo ""
    local summary_sources
    summary_sources=$(jq -r 'select(.event == "findings_summary") | .source' "$file" 2>/dev/null | sort -u)
    for src in $summary_sources; do
      local passes final_verdict approved_at
      passes=$(jq -s --arg src "$src" \
        '[.[] | select(.event == "findings_summary" and .source == $src)] | length' "$file" 2>/dev/null || echo 0)
      final_verdict=$(jq -s --arg src "$src" \
        '[.[] | select(.event == "findings_summary" and .source == $src)] | last | .verdict' "$file" 2>/dev/null | tr -d '"')
      # Find the iteration number where first APPROVED (or equivalent) occurred
      approved_at=$(jq -s --arg src "$src" \
        '[.[] | select(.event == "findings_summary" and .source == $src and (.verdict == "APPROVED" or .verdict == "PASS" or .verdict == "CLEAN" or .verdict == "SKIP"))] | first | .iteration // empty' "$file" 2>/dev/null || true)
      if [ -n "$approved_at" ]; then
        echo "  $src: $approved_at pass(es) to approve ($passes total)"
      else
        echo "  $src: NOT approved after $passes pass(es) (last: $final_verdict)"
      fi
    done
    echo ""
  fi

  # ── Triage breakdown ──
  local triage_count
  triage_count=$(jq -s '[.[] | select(.event == "triage")] | length' "$file" 2>/dev/null || echo 0)
  if [ "$triage_count" -gt 0 ]; then
    echo "── Triage Decisions ──"
    echo ""
    for cls in blocking non-blocking out-of-scope; do
      local cnt
      cnt=$(jq -s --arg c "$cls" \
        '[.[] | select(.event == "triage" and .classification == $c)] | length' "$file" 2>/dev/null)
      [ "$cnt" -gt 0 ] && echo "  $cls: $cnt"
    done
    echo ""
    echo "  Actions:"
    for act in fix noted dismissed debate; do
      local cnt
      cnt=$(jq -s --arg a "$act" \
        '[.[] | select(.event == "triage" and .action == $a)] | length' "$file" 2>/dev/null)
      [ "$cnt" -gt 0 ] && echo "    $act: $cnt"
    done
    echo ""
  fi

  # ── Resolution breakdown ──
  local resolved_count
  resolved_count=$(jq -s '[.[] | select(.event == "resolved")] | length' "$file" 2>/dev/null || echo 0)
  if [ "$resolved_count" -gt 0 ]; then
    echo "── Resolutions ──"
    echo ""
    for res in fixed dismissed debated overridden accepted escalated; do
      local cnt
      cnt=$(jq -s --arg r "$res" \
        '[.[] | select(.event == "resolved" and .resolution == $r)] | length' "$file" 2>/dev/null)
      [ "$cnt" -gt 0 ] && echo "  $res: $cnt"
    done
    echo ""
  fi

  # ── Effectiveness ratios ──
  echo "── Effectiveness ──"
  echo ""

  local total_raised total_fixed total_dismissed total_overridden total_debated
  total_raised=$(jq -s '[.[] | select(.event == "finding_raised")] | length' "$file" 2>/dev/null || echo 0)
  total_fixed=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "fixed")] | length' "$file" 2>/dev/null || echo 0)
  total_dismissed=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "dismissed")] | length' "$file" 2>/dev/null || echo 0)
  total_overridden=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "overridden")] | length' "$file" 2>/dev/null || echo 0)
  total_debated=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "debated")] | length' "$file" 2>/dev/null || echo 0)

  # Also count from summaries if no individual findings
  if [ "$total_raised" -eq 0 ]; then
    total_raised=$(jq -s '[.[] | select(.event == "findings_summary")] | map(.total_findings) | add // 0' "$file" 2>/dev/null || echo 0)
  fi

  echo "  Total findings raised:  $total_raised"
  echo "  Fixed:                  $total_fixed"
  echo "  Dismissed:              $total_dismissed"
  echo "  Overridden:             $total_overridden"
  echo "  Debated:                $total_debated"

  if [ "$total_raised" -gt 0 ]; then
    # Use awk for float division
    local fix_rate dismiss_rate override_rate
    fix_rate=$(awk "BEGIN {printf \"%.0f\", ($total_fixed / $total_raised) * 100}")
    dismiss_rate=$(awk "BEGIN {printf \"%.0f\", ($total_dismissed / $total_raised) * 100}")
    override_rate=$(awk "BEGIN {printf \"%.0f\", ($total_overridden / $total_raised) * 100}")
    echo ""
    echo "  Fix rate:               ${fix_rate}%"
    echo "  Dismiss rate:           ${dismiss_rate}%"
    echo "  Override rate:          ${override_rate}%"
  fi

  # ── Review cycles ──
  local cycle_count
  cycle_count=$(jq -s '[.[] | select(.event == "review_cycle")] | length' "$file" 2>/dev/null || echo 0)
  if [ "$cycle_count" -gt 0 ]; then
    echo ""
    echo "── Review Cycles ──"
    echo ""
    jq -r 'select(.event == "review_cycle") |
      "  Cycle \(.cycle): raised=\(.findings_raised) fixed=\(.fixed) dismissed=\(.dismissed) overridden=\(.overridden)"' "$file" 2>/dev/null
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
}

# ── Query: JSON export for programmatic analysis ──
# Args: session_id

export_metrics_json() {
  local session_id="$1"
  local file
  file=$(metrics_file "$session_id")

  if [ ! -f "$file" ]; then
    echo "[]"
    return 1
  fi

  jq -s '.' "$file" 2>/dev/null || echo "[]"
}
