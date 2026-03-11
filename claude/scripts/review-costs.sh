#!/usr/bin/env bash
# review-costs.sh — Review cascade summary from agent-trace.jsonl
# Usage: review-costs.sh [session_id]
#   session_id: filter to a specific session (default: latest session)
set -euo pipefail

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"

if [[ ! -f "$TRACE_FILE" ]]; then
  echo "No trace file found at $TRACE_FILE" >&2
  exit 1
fi

session_id="${1:-}"

# If no session specified, use the latest session in the trace
if [[ -z "$session_id" ]]; then
  session_id=$(grep '"event":"stop"' "$TRACE_FILE" | tail -1 | jq -r '.session // empty' 2>/dev/null || true)
  if [[ -z "$session_id" ]]; then
    echo "No sessions found in trace file." >&2
    exit 1
  fi
fi

echo "Review Cascade Summary (session: $session_id)"
echo "────────────────────────────────────────"
printf '%-24s %-6s %s\n' "Agent" "Runs" "Verdicts"
echo "─────                    ────── ────────"

# Aggregate stop events by agent type within the session
jq -sr --arg sid "$session_id" '
  [.[] | select(.session == $sid and .event == "stop")]
  | group_by(.agent)
  | map({
      agent: .[0].agent,
      count: length,
      verdicts: (map(.verdict) | group_by(.) | map({v: .[0], c: length}) | sort_by(-.c) | map("\(.v)(\(.c))") | join(", "))
    })
  | sort_by(.agent)
  | .[]
  | [.agent, (.count | tostring), .verdicts]
  | @tsv
' "$TRACE_FILE" 2>/dev/null | while IFS=$'\t' read -r agent count verdicts; do
  [[ -z "$agent" ]] && continue
  printf '%-24s %-6s %s\n' "$agent" "$count" "$verdicts"
done

echo "────────────────────────────────────────"
echo "Codex: tracked separately by Codex CLI"
