#!/usr/bin/env bash
# Tests for pr-gate.sh
# Covers: full gate, tiered gate, docs-only bypass, stale evidence
#
# Usage: bash ~/.claude/hooks/tests/test-pr-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../pr-gate.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION_ID="test-pr-gate-$$"
TMPDIR_BASE=""

assert() {
  local desc="$1"
  if eval "$2"; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $desc"
  fi
}

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  git checkout -q -b feature
}

clean_evidence() {
  rm -f "$(evidence_file "$SESSION_ID")"
  rm -f "/tmp/claude-evidence-${SESSION_ID}.lock"
  rmdir "/tmp/claude-evidence-${SESSION_ID}.lock.d" 2>/dev/null || true
}

full_clean_evidence() {
  clean_evidence
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_clean_evidence EXIT

gate_input() {
  jq -cn \
    --arg sid "$SESSION_ID" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_input:{command:"gh pr create --title test"},session_id:$sid,cwd:$cwd}'
}

add_all_full_evidence() {
  for type in pr-verified code-critic minimizer codex test-runner check-runner; do
    append_evidence "$SESSION_ID" "$type" "PASS" "$TMPDIR_BASE"
  done
}

add_quick_evidence() {
  append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
  append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
}

echo "--- test-pr-gate.sh ---"

# ═══ Docs-only bypass ═══════════════════════════════════════════════════════

echo "=== Docs-only bypass ==="
setup_repo
clean_evidence
echo "docs" > readme.md
git add readme.md && git commit -q -m "add docs"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Docs-only PR allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# ═══ Full gate tests ════════════════════════════════════════════════════════

echo "=== Full gate: blocks when evidence missing ==="
setup_repo
clean_evidence
# Large diff (>30 lines) to trigger full gate
for i in $(seq 1 40); do echo "line $i" >> big.sh; done
git add big.sh && git commit -q -m "big change"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate blocks without evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: allows when all evidence present ==="
clean_evidence
add_all_full_evidence
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate allows with all evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: blocks on stale diff_hash ==="
clean_evidence
add_all_full_evidence
cd "$TMPDIR_BASE"
echo "stale" >> big.sh
git add big.sh && git commit -q -m "stale edit"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate blocks stale evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Tiered gate tests ══════════════════════════════════════════════════════

echo "=== Tiered gate: small diff needs only test-runner + check-runner ==="
setup_repo
clean_evidence
echo "small edit" >> file.txt
git add file.txt && git commit -q -m "small edit"
add_quick_evidence
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Tiered gate: small diff with quick evidence passes" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Tiered gate: large diff (>30 lines) requires full evidence ==="
setup_repo
clean_evidence
for i in $(seq 1 40); do echo "line $i" >> file.txt; done
git add file.txt && git commit -q -m "big edit"
add_quick_evidence
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Tiered gate: large diff with only quick evidence blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Tiered gate: new files require full evidence ==="
setup_repo
clean_evidence
echo "new" > new.sh
git add new.sh && git commit -q -m "new file"
add_quick_evidence
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Tiered gate: new file with only quick evidence blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Non-PR commands pass through ═══════════════════════════════════════════

echo "=== Non-PR commands allowed ==="
setup_repo
clean_evidence
NON_PR_INPUT=$(jq -cn \
  --arg sid "$SESSION_ID" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_input:{command:"git push"},session_id:$sid,cwd:$cwd}')
OUTPUT=$(echo "$NON_PR_INPUT" | bash "$GATE")
assert "git push allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
