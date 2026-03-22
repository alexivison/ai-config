#!/usr/bin/env bash
# oscillation.sh — Oscillation detection for critic verdict streams
#
# Extracted from agent-trace-stop.sh to isolate reusable detection logic.
# Depends on evidence.sh for append_evidence, append_triage_override,
# evidence_file, and compute_diff_hash.
#
# Usage: source "$(dirname "$0")/lib/oscillation.sh"
#   (evidence.sh must be sourced first)

# ── Fingerprint: normalize a critic response for cross-hash comparison ──
# Strips markdown emphasis, verdict banners, collapses whitespace, lowercases,
# then SHA-256 hashes the result. Only meaningful for minimizer REQUEST_CHANGES.
# Args: response_text
# Outputs: hex SHA-256 fingerprint (or empty string on empty input)

compute_finding_fingerprint() {
  local response="$1"
  [ -z "$response" ] && return
  echo "$response" \
    | sed -E 's/\*\*[A-Z_]+\*\*//g' \
    | sed -E 's/^(REQUEST_CHANGES|APPROVE|NEEDS_DISCUSSION)$//g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed 's/^ //;s/ $//' \
    | shasum -a 256 | cut -d' ' -f1
}

# ── Main oscillation detection entry point ──
# Call after recording a critic verdict. Checks for:
#   1. Same-hash alternation (both critics): A→RC→A at same hash = flip-flopping
#   2. Cross-hash repeated findings (minimizer only): same normalized RC body
#      across 3+ distinct hashes = persistent cosmetic complaint. Code-critic
#      is exempt — correctness bugs legitimately persist across fix attempts.
#
# Args: session_id agent_type verdict response cwd
#   - agent_type: "code-critic" or "minimizer"
#   - verdict: "APPROVED" or "REQUEST_CHANGES"
#   - response: full agent response text (used for fingerprinting)
#   - cwd: working directory for diff hash computation

detect_oscillation() {
  local session_id="$1" agent_type="$2" verdict="$3" response="$4" cwd="$5"

  # Only applies to critic APPROVED/REQUEST_CHANGES verdicts
  case "$verdict" in
    APPROVED|REQUEST_CHANGES) ;;
    *) return 0 ;;
  esac

  # Compute fingerprint for cross-hash detection (minimizer REQUEST_CHANGES only)
  local finding_fp=""
  if [ "$agent_type" = "minimizer" ] && [ "$verdict" = "REQUEST_CHANGES" ] && [ -n "$response" ]; then
    finding_fp=$(compute_finding_fingerprint "$response")
  fi

  # Record every critic verdict via append_evidence (single write path)
  append_evidence "$session_id" "${agent_type}-run" "$verdict" "$cwd"

  # When a fingerprint was computed, record it as a separate entry for
  # cross-hash lookup. Uses append_evidence's schema with a distinct type
  # so the fingerprint→hash mapping is queryable without modifying evidence.sh.
  if [ -n "$finding_fp" ]; then
    append_evidence "$session_id" "${agent_type}-fp" "$finding_fp" "$cwd"
  fi

  local evidence_path
  evidence_path=$(evidence_file "$session_id")
  [ -f "$evidence_path" ] || return 0

  local local_hash
  local_hash=$(compute_diff_hash "$cwd")

  # ── Same-hash alternation detection (both critic types) ──
  local verdicts_json count
  verdicts_json=$(jq -r --arg type "${agent_type}-run" --arg hash "$local_hash" \
    'select(.type == $type and .diff_hash == $hash) | .result' "$evidence_path" 2>/dev/null || true)

  if [ -n "$verdicts_json" ]; then
    readarray -t verdicts <<< "$verdicts_json"
    count=${#verdicts[@]}
    if [ "$count" -ge 3 ]; then
      local v1="${verdicts[$((count - 3))]}"
      local v2="${verdicts[$((count - 2))]}"
      local v3="${verdicts[$((count - 1))]}"
      # Alternating pattern at same hash: critic is flip-flopping on unchanged code
      if [ "$v1" != "$v2" ] && [ "$v2" != "$v3" ] && [ "$v1" = "$v3" ]; then
        append_triage_override "$session_id" "$agent_type" \
          "Auto-detected oscillation: verdicts alternated ($v1 → $v2 → $v3) at same diff_hash" "$cwd" 2>/dev/null || true
      fi
    fi
  fi

  # ── Cross-hash repeated finding detection (minimizer only) ──
  if [ -n "$finding_fp" ]; then
    local distinct_hashes
    distinct_hashes=$(jq -r --arg type "${agent_type}-fp" --arg fp "$finding_fp" \
      'select(.type == $type and .result == $fp) | .diff_hash' "$evidence_path" 2>/dev/null \
      | sort -u | wc -l | tr -d ' ')
    if [ "$distinct_hashes" -ge 3 ]; then
      append_triage_override "$session_id" "$agent_type" \
        "Auto-detected cross-hash oscillation: same finding fingerprint (${finding_fp:0:12}…) across $distinct_hashes distinct hashes" "$cwd" 2>/dev/null || true
    fi
  fi
}
