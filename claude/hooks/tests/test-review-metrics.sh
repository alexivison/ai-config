#!/usr/bin/env bash
# Tests for review-metrics.sh library
# Covers: record_finding_raised, record_findings_summary, record_triage,
#         record_resolution, record_review_cycle, generate_report, export_metrics_json
#
# Usage: bash ~/.claude/hooks/tests/test-review-metrics.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/evidence.sh"
source "$SCRIPT_DIR/../lib/review-metrics.sh"

PASS=0
FAIL=0
SESSION="test-metrics-$$"
TMPDIR_BASE=""

assert() {
  local name="$1" condition="$2"
  if eval "$condition"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  cd "$TMPDIR_BASE"
  git init -q
  git config commit.gpgsign false
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  git checkout -q -b feature
  echo "impl" > impl.sh
  git add impl.sh
  git commit -q -m "add impl"
}

cleanup() {
  rm -f "$(metrics_file "$SESSION")"
  rm -f "$(evidence_file "$SESSION")"
  rm -f "/tmp/claude-evidence-${SESSION}.lock"
  rm -f "/tmp/claude-worktree-${SESSION}"
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

# ═══ metrics_file ════════════════════════════════════════════════════════════

echo "=== metrics_file: correct path ==="
MFILE=$(metrics_file "$SESSION")
assert "Correct path format" '[[ "$MFILE" == "/tmp/claude-review-metrics-test-metrics-"*".jsonl" ]]'

# ═══ record_finding_raised ═══════════════════════════════════════════════════

echo "=== record_finding_raised: creates valid JSONL entry ==="
cleanup
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
record_finding_raised "$SESSION" "code-critic" "cc-1" "blocking" "bug" "src/foo.ts" "42" "Null pointer dereference" "$HASH"
MFILE=$(metrics_file "$SESSION")
assert "Metrics file created" '[ -f "$MFILE" ]'
assert "Single line" '[ "$(wc -l < "$MFILE" | tr -d " ")" = "1" ]'
assert "Valid JSON" 'jq -e . "$MFILE" >/dev/null 2>&1'
assert "Event is finding_raised" '[ "$(jq -r .event "$MFILE")" = "finding_raised" ]'
assert "Source is code-critic" '[ "$(jq -r .source "$MFILE")" = "code-critic" ]'
assert "Finding ID is cc-1" '[ "$(jq -r .finding_id "$MFILE")" = "cc-1" ]'
assert "Severity is blocking" '[ "$(jq -r .severity "$MFILE")" = "blocking" ]'
assert "Category is bug" '[ "$(jq -r .category "$MFILE")" = "bug" ]'
assert "File field set" '[ "$(jq -r .file "$MFILE")" = "src/foo.ts" ]'
assert "Line field set" '[ "$(jq -r .line "$MFILE")" = "42" ]'
assert "Description set" '[ "$(jq -r .description "$MFILE")" = "Null pointer dereference" ]'
assert "Has diff_hash" '[ "$(jq -r .diff_hash "$MFILE")" = "$HASH" ]'
assert "Has timestamp" '[ "$(jq -r .timestamp "$MFILE")" != "null" ]'

echo "=== record_finding_raised: multiple findings ==="
record_finding_raised "$SESSION" "minimizer" "min-1" "non-blocking" "bloat" "src/bar.ts" "10" "Unnecessary abstraction" "$HASH"
record_finding_raised "$SESSION" "codex" "codex-1" "blocking" "security" "src/auth.ts" "5" "SQL injection" "$HASH"
assert "Three lines total" '[ "$(wc -l < "$MFILE" | tr -d " ")" = "3" ]'
assert "All valid JSON" '[ "$(jq -c . "$MFILE" 2>/dev/null | wc -l | tr -d " ")" = "3" ]'

# ═══ record_findings_summary ═════════════════════════════════════════════════

echo "=== record_findings_summary: creates summary entry ==="
cleanup
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
record_findings_summary "$SESSION" "code-critic" "$HASH" "REQUEST_CHANGES" "5" "2" "3" "Found issues..."
MFILE=$(metrics_file "$SESSION")
assert "Summary entry created" '[ -f "$MFILE" ]'
assert "Event is findings_summary" '[ "$(jq -r .event "$MFILE")" = "findings_summary" ]'
assert "Source correct" '[ "$(jq -r .source "$MFILE")" = "code-critic" ]'
assert "Verdict correct" '[ "$(jq -r .verdict "$MFILE")" = "REQUEST_CHANGES" ]'
assert "Total findings is 5" '[ "$(jq -r .total_findings "$MFILE")" = "5" ]'
assert "Blocking is 2" '[ "$(jq -r .blocking "$MFILE")" = "2" ]'
assert "Non-blocking is 3" '[ "$(jq -r .non_blocking "$MFILE")" = "3" ]'
assert "Excerpt recorded" '[ "$(jq -r .excerpt "$MFILE")" = "Found issues..." ]'

# ═══ record_triage ═══════════════════════════════════════════════════════════

echo "=== record_triage: creates triage entry ==="
cleanup
setup_repo
record_triage "$SESSION" "cc-1" "code-critic" "blocking" "fix"
MFILE=$(metrics_file "$SESSION")
assert "Triage entry created" '[ -f "$MFILE" ]'
assert "Event is triage" '[ "$(jq -r .event "$MFILE")" = "triage" ]'
assert "Finding ID correct" '[ "$(jq -r .finding_id "$MFILE")" = "cc-1" ]'
assert "Classification is blocking" '[ "$(jq -r .classification "$MFILE")" = "blocking" ]'
assert "Action is fix" '[ "$(jq -r .action "$MFILE")" = "fix" ]'

echo "=== record_triage: with rationale ==="
record_triage "$SESSION" "cc-2" "code-critic" "out-of-scope" "dismissed" "Pre-existing code not touched"
ENTRY=$(jq -s 'last' "$MFILE")
assert "Rationale recorded" '[ "$(echo "$ENTRY" | jq -r .rationale)" = "Pre-existing code not touched" ]'
assert "Classification is out-of-scope" '[ "$(echo "$ENTRY" | jq -r .classification)" = "out-of-scope" ]'
assert "Action is dismissed" '[ "$(echo "$ENTRY" | jq -r .action)" = "dismissed" ]'

# ═══ record_resolution ═══════════════════════════════════════════════════════

echo "=== record_resolution: creates resolved entry ==="
cleanup
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
record_resolution "$SESSION" "cc-1" "code-critic" "fixed" "$HASH" "Fixed null check"
MFILE=$(metrics_file "$SESSION")
assert "Resolution entry created" '[ -f "$MFILE" ]'
assert "Event is resolved" '[ "$(jq -r .event "$MFILE")" = "resolved" ]'
assert "Resolution is fixed" '[ "$(jq -r .resolution "$MFILE")" = "fixed" ]'
assert "Detail recorded" '[ "$(jq -r .detail "$MFILE")" = "Fixed null check" ]'

echo "=== record_resolution: all resolution types ==="
for res in dismissed debated overridden accepted escalated; do
  record_resolution "$SESSION" "f-$res" "minimizer" "$res" "$HASH"
done
LINE_COUNT=$(wc -l < "$MFILE" | tr -d ' ')
assert "All resolution types recorded (6 total)" '[ "$LINE_COUNT" = "6" ]'

# ═══ record_review_cycle ═════════════════════════════════════════════════════

echo "=== record_review_cycle: creates cycle summary ==="
cleanup
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
# Populate some metrics first
record_finding_raised "$SESSION" "code-critic" "cc-1" "blocking" "bug" "f.ts" "1" "Bug" "$HASH"
record_finding_raised "$SESSION" "minimizer" "min-1" "non-blocking" "bloat" "g.ts" "2" "Bloat" "$HASH"
record_triage "$SESSION" "cc-1" "code-critic" "blocking" "fix"
record_triage "$SESSION" "min-1" "minimizer" "non-blocking" "noted"
record_resolution "$SESSION" "cc-1" "code-critic" "fixed" "$HASH"
# Now record cycle
record_review_cycle "$SESSION" "1" "$HASH"
MFILE=$(metrics_file "$SESSION")
CYCLE_ENTRY=$(jq -s '[.[] | select(.event == "review_cycle")] | last' "$MFILE")
assert "Cycle event recorded" '[ "$(echo "$CYCLE_ENTRY" | jq -r .event)" = "review_cycle" ]'
assert "Cycle number is 1" '[ "$(echo "$CYCLE_ENTRY" | jq -r .cycle)" = "1" ]'
assert "Findings raised count is 2" '[ "$(echo "$CYCLE_ENTRY" | jq -r .findings_raised)" = "2" ]'
assert "Fixed count is 1" '[ "$(echo "$CYCLE_ENTRY" | jq -r .fixed)" = "1" ]'
assert "Noted count is 1" '[ "$(echo "$CYCLE_ENTRY" | jq -r .noted)" = "1" ]'

# ═══ generate_report ═════════════════════════════════════════════════════════

echo "=== generate_report: produces readable output ==="
# Uses the data from previous test
REPORT=$(generate_report "$SESSION")
assert "Report contains session ID" 'echo "$REPORT" | grep -q "$SESSION"'
assert "Report contains Findings by Source" 'echo "$REPORT" | grep -q "Findings by Source"'
assert "Report contains Effectiveness" 'echo "$REPORT" | grep -q "Effectiveness"'
assert "Report contains Review Cycles" 'echo "$REPORT" | grep -q "Review Cycles"'
assert "Report contains Triage Decisions" 'echo "$REPORT" | grep -q "Triage Decisions"'
assert "Report contains Resolutions" 'echo "$REPORT" | grep -q "Resolutions"'

echo "=== generate_report: missing session ==="
OUTPUT=$(generate_report "nonexistent-session-$$" 2>&1 || true)
assert "Missing session shows message" 'echo "$OUTPUT" | grep -q "No metrics found"'

# ═══ export_metrics_json ═════════════════════════════════════════════════════

echo "=== export_metrics_json: returns valid JSON array ==="
EXPORTED=$(export_metrics_json "$SESSION")
assert "Export is valid JSON" 'echo "$EXPORTED" | jq -e . >/dev/null 2>&1'
assert "Export is an array" '[ "$(echo "$EXPORTED" | jq -r type)" = "array" ]'
EXPORT_COUNT=$(echo "$EXPORTED" | jq 'length')
assert "Export contains all entries" '[ "$EXPORT_COUNT" -gt 0 ]'

echo "=== export_metrics_json: missing session ==="
EXPORTED=$(export_metrics_json "nonexistent-session-$$" 2>&1 || true)
assert "Missing session returns empty array" '[ "$EXPORTED" = "[]" ]'

# ═══ Concurrent writes ═══════════════════════════════════════════════════════

echo "=== concurrent writes: no data corruption ==="
cleanup
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
for i in $(seq 1 15); do
  record_finding_raised "$SESSION" "stress-$i" "s-$i" "blocking" "bug" "f.ts" "$i" "Stress test $i" "$HASH" &
done
wait
MFILE=$(metrics_file "$SESSION")
LINE_COUNT=$(wc -l < "$MFILE" | tr -d ' ')
assert "15 parallel writes → 15 lines" '[ "$LINE_COUNT" = "15" ]'
VALID_COUNT=$(jq -c . "$MFILE" 2>/dev/null | wc -l | tr -d ' ')
assert "All 15 lines valid JSON" '[ "$VALID_COUNT" = "15" ]'

# ═══ CLI script ══════════════════════════════════════════════════════════════

echo "=== CLI: --finding records via script ==="
cleanup
setup_repo
CLI="$SCRIPT_DIR/../scripts/review-metrics.sh"
OUTPUT=$("$CLI" --finding "$SESSION" "code-critic" "cli-1" "blocking" "bug" "x.ts" "1" "CLI test" "$TMPDIR_BASE")
assert "CLI --finding outputs confirmation" 'echo "$OUTPUT" | grep -q "METRIC_RECORDED"'
MFILE=$(metrics_file "$SESSION")
assert "CLI --finding creates entry" '[ -f "$MFILE" ]'
assert "CLI --finding valid JSON" 'jq -e . "$MFILE" >/dev/null 2>&1'

echo "=== CLI: --summary records via script ==="
OUTPUT=$("$CLI" --summary "$SESSION" "minimizer" "APPROVED" "0" "0" "0" "$TMPDIR_BASE")
assert "CLI --summary outputs confirmation" 'echo "$OUTPUT" | grep -q "METRIC_RECORDED"'

echo "=== CLI: --triage records via script ==="
OUTPUT=$("$CLI" --triage "$SESSION" "cli-1" "code-critic" "blocking" "fix")
assert "CLI --triage outputs confirmation" 'echo "$OUTPUT" | grep -q "METRIC_RECORDED"'

echo "=== CLI: --resolved records via script ==="
OUTPUT=$("$CLI" --resolved "$SESSION" "cli-1" "code-critic" "fixed" "$TMPDIR_BASE")
assert "CLI --resolved outputs confirmation" 'echo "$OUTPUT" | grep -q "METRIC_RECORDED"'

echo "=== CLI: --cycle records via script ==="
OUTPUT=$("$CLI" --cycle "$SESSION" "1" "$TMPDIR_BASE")
assert "CLI --cycle outputs confirmation" 'echo "$OUTPUT" | grep -q "METRIC_RECORDED"'

echo "=== CLI: --report generates output ==="
OUTPUT=$("$CLI" --report "$SESSION")
assert "CLI --report shows session" 'echo "$OUTPUT" | grep -q "$SESSION"'

echo "=== CLI: --export generates JSON ==="
OUTPUT=$("$CLI" --export "$SESSION")
assert "CLI --export is valid JSON array" 'echo "$OUTPUT" | jq -e "type == \"array\"" >/dev/null 2>&1'

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "review-metrics.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
