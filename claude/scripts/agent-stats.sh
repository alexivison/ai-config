#!/bin/bash
# Agent Activity Analysis
# Summarizes sub-agent invocations from trace log
#
# Usage:
#   agent-stats.sh           # Summary for today
#   agent-stats.sh --week    # Summary for last 7 days
#   agent-stats.sh --all     # All time summary
#   agent-stats.sh --json    # Raw JSON output

set -e

TRACE_FILE="$HOME/.claude/logs/agent-trace.jsonl"

if [ ! -f "$TRACE_FILE" ]; then
  echo "No trace data found at $TRACE_FILE"
  echo "Agent tracing will begin after sub-agents are invoked."
  exit 0
fi

# Parse arguments
PERIOD="today"
FORMAT="text"

for arg in "$@"; do
  case $arg in
    --week) PERIOD="week" ;;
    --all) PERIOD="all" ;;
    --json) FORMAT="json" ;;
  esac
done

# Filter by time period
case $PERIOD in
  today)
    TODAY=$(date -u '+%Y-%m-%d')
    FILTER_CMD="jq -c 'select(.timestamp | startswith(\"$TODAY\"))'"
    PERIOD_LABEL="Today"
    ;;
  week)
    WEEK_AGO=$(date -u -v-7d '+%Y-%m-%d' 2>/dev/null || date -u -d '7 days ago' '+%Y-%m-%d')
    FILTER_CMD="jq -c 'select(.timestamp >= \"$WEEK_AGO\")'"
    PERIOD_LABEL="Last 7 days"
    ;;
  all)
    FILTER_CMD="cat"
    PERIOD_LABEL="All time"
    ;;
esac

# Get filtered data
FILTERED=$(eval "$FILTER_CMD" < "$TRACE_FILE" 2>/dev/null || cat "$TRACE_FILE")

if [ -z "$FILTERED" ]; then
  echo "No agent activity for $PERIOD_LABEL"
  exit 0
fi

# Count total invocations
TOTAL=$(echo "$FILTERED" | wc -l | tr -d ' ')

# JSON output mode
if [ "$FORMAT" = "json" ]; then
  echo "$FILTERED" | jq -s '{
    period: "'"$PERIOD_LABEL"'",
    total_invocations: length,
    by_agent: (group_by(.agent) | map({agent: .[0].agent, count: length})),
    by_verdict: (group_by(.verdict) | map({verdict: .[0].verdict, count: length})),
    by_project: (group_by(.project) | map({project: .[0].project, count: length})),
    recent: (sort_by(.timestamp) | reverse | .[0:5])
  }'
  exit 0
fi

# Text output
echo "═══════════════════════════════════════════════"
echo "  Agent Activity Summary ($PERIOD_LABEL)"
echo "═══════════════════════════════════════════════"
echo ""
echo "Total invocations: $TOTAL"
echo ""

# By agent type
echo "By Agent:"
echo "$FILTERED" | jq -r '.agent' | sort | uniq -c | sort -rn | while read count agent; do
  printf "  %-20s %s\n" "$agent" "$count"
done
echo ""

# By verdict
echo "By Verdict:"
echo "$FILTERED" | jq -r '.verdict' | sort | uniq -c | sort -rn | while read count verdict; do
  printf "  %-20s %s\n" "$verdict" "$count"
done
echo ""

# By project
echo "By Project:"
echo "$FILTERED" | jq -r '.project' | sort | uniq -c | sort -rn | head -5 | while read count project; do
  printf "  %-20s %s\n" "$project" "$count"
done
echo ""

# Recent activity
echo "Recent Activity:"
echo "$FILTERED" | jq -r 'select(.timestamp != null) | "\(.timestamp | .[11:16]) \(.agent) → \(.verdict) (\(.description))"' | tail -5 | while read line; do
  echo "  $line"
done
echo ""

# Code-critic loop stats (if any)
CRITIC_COUNT=$(echo "$FILTERED" | jq -r 'select(.agent == "code-critic")' | wc -l | tr -d ' ')
if [ "$CRITIC_COUNT" -gt 0 ]; then
  echo "Code-Critic Loop Stats:"
  APPROVED=$(echo "$FILTERED" | jq -r 'select(.agent == "code-critic" and .verdict == "APPROVED")' | wc -l | tr -d ' ')
  CHANGES=$(echo "$FILTERED" | jq -r 'select(.agent == "code-critic" and .verdict == "REQUEST_CHANGES")' | wc -l | tr -d ' ')
  printf "  Iterations: %s total, %s approved, %s requested changes\n" "$CRITIC_COUNT" "$APPROVED" "$CHANGES"
  if [ "$CRITIC_COUNT" -gt 0 ]; then
    APPROVAL_RATE=$((APPROVED * 100 / CRITIC_COUNT))
    printf "  First-pass approval rate: %s%%\n" "$APPROVAL_RATE"
  fi
  echo ""
fi

echo "═══════════════════════════════════════════════"
echo "Trace file: $TRACE_FILE"
echo "Run with --json for raw data, --week or --all for different periods"
