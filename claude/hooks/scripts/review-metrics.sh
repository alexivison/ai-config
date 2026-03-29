#!/usr/bin/env bash
# review-metrics.sh — CLI for recording and querying review metrics
#
# Recording:
#   review-metrics.sh --finding   <session> <source> <id> <severity> <category> <file> <line> <description> [cwd]
#   review-metrics.sh --summary   <session> <source> <verdict> <total> <blocking> <non_blocking> [cwd]
#   review-metrics.sh --triage    <session> <finding_id> <source> <classification> <action> [rationale]
#   review-metrics.sh --resolved  <session> <finding_id> <source> <resolution> [cwd] [detail]
#   review-metrics.sh --cycle     <session> <cycle_number> [cwd]
#
# Querying:
#   review-metrics.sh --report    <session>
#   review-metrics.sh --export    <session>
#   review-metrics.sh --report-all              (all sessions)
#
# Usage: Called by Claude during triage, or by hooks during agent-stop/codex-trace.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/evidence.sh"
source "$SCRIPT_DIR/../lib/review-metrics.sh"

MODE="${1:?Usage: review-metrics.sh --finding|--summary|--triage|--resolved|--cycle|--report|--export|--report-all}"

case "$MODE" in

  --finding)
    SESSION="${2:?Missing session_id}"
    SOURCE="${3:?Missing source (code-critic|minimizer|scribe|sentinel|codex)}"
    FINDING_ID="${4:?Missing finding_id}"
    SEVERITY="${5:?Missing severity (blocking|non-blocking|advisory)}"
    CATEGORY="${6:?Missing category (bug|security|style|bloat|scope|correctness|other)}"
    FILE="${7:-}"
    LINE="${8:-}"
    DESC="${9:-}"
    CWD="${10:-$(pwd)}"
    CWD=$(_resolve_cwd "$SESSION" "$CWD")
    HASH=$(compute_diff_hash "$CWD")
    record_finding_raised "$SESSION" "$SOURCE" "$FINDING_ID" "$SEVERITY" "$CATEGORY" "$FILE" "$LINE" "$DESC" "$HASH"
    echo "METRIC_RECORDED: finding_raised $SOURCE $FINDING_ID"
    ;;

  --summary)
    SESSION="${2:?Missing session_id}"
    SOURCE="${3:?Missing source}"
    VERDICT="${4:?Missing verdict}"
    TOTAL="${5:?Missing total_findings}"
    BLOCKING="${6:?Missing blocking count}"
    NON_BLOCKING="${7:?Missing non_blocking count}"
    CWD="${8:-$(pwd)}"
    CWD=$(_resolve_cwd "$SESSION" "$CWD")
    HASH=$(compute_diff_hash "$CWD")
    record_findings_summary "$SESSION" "$SOURCE" "$HASH" "$VERDICT" "$TOTAL" "$BLOCKING" "$NON_BLOCKING"
    echo "METRIC_RECORDED: findings_summary $SOURCE verdict=$VERDICT total=$TOTAL"
    ;;

  --triage)
    SESSION="${2:?Missing session_id}"
    FINDING_ID="${3:?Missing finding_id}"
    SOURCE="${4:?Missing source}"
    CLASSIFICATION="${5:?Missing classification (blocking|non-blocking|out-of-scope)}"
    ACTION="${6:?Missing action (fix|noted|dismissed|debate)}"
    RATIONALE="${7:-}"
    record_triage "$SESSION" "$FINDING_ID" "$SOURCE" "$CLASSIFICATION" "$ACTION" "$RATIONALE"
    echo "METRIC_RECORDED: triage $FINDING_ID ${CLASSIFICATION}->${ACTION}"
    ;;

  --resolved)
    SESSION="${2:?Missing session_id}"
    FINDING_ID="${3:?Missing finding_id}"
    SOURCE="${4:?Missing source}"
    RESOLUTION="${5:?Missing resolution (fixed|dismissed|debated|overridden|accepted|escalated)}"
    CWD="${6:-$(pwd)}"
    DETAIL="${7:-}"
    CWD=$(_resolve_cwd "$SESSION" "$CWD")
    HASH=$(compute_diff_hash "$CWD")
    record_resolution "$SESSION" "$FINDING_ID" "$SOURCE" "$RESOLUTION" "$HASH" "$DETAIL"
    echo "METRIC_RECORDED: resolved $FINDING_ID $RESOLUTION"
    ;;

  --cycle)
    SESSION="${2:?Missing session_id}"
    CYCLE="${3:?Missing cycle_number}"
    CWD="${4:-$(pwd)}"
    CWD=$(_resolve_cwd "$SESSION" "$CWD")
    HASH=$(compute_diff_hash "$CWD")
    record_review_cycle "$SESSION" "$CYCLE" "$HASH"
    echo "METRIC_RECORDED: review_cycle $CYCLE"
    ;;

  --report)
    SESSION="${2:?Missing session_id}"
    generate_report "$SESSION"
    ;;

  --export)
    SESSION="${2:?Missing session_id}"
    export_metrics_json "$SESSION"
    ;;

  --report-all)
    # Find all metrics files in persistent storage and generate reports
    found=0
    for f in "$_METRICS_DIR"/*.jsonl; do
      [ -f "$f" ] || continue
      sid=$(basename "$f" .jsonl)
      [ -n "$sid" ] || continue
      found=1
      generate_report "$sid"
      echo ""
    done
    if [ "$found" -eq 0 ]; then
      echo "No review metrics files found in $_METRICS_DIR"
    fi
    ;;

  *)
    echo "Error: Unknown mode '$MODE'" >&2
    echo "Usage: review-metrics.sh --finding|--summary|--triage|--resolved|--cycle|--report|--export|--report-all" >&2
    exit 1
    ;;
esac
