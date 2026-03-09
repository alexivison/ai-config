#!/usr/bin/env bash
# Tests for marker-invalidate.sh
# Covers: marker invalidation behavior with code vs non-code edits
#
# Usage: bash ~/.claude/hooks/tests/test-marker-invalidate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVALIDATE_HOOK="$SCRIPT_DIR/../marker-invalidate.sh"
PASS=0
FAIL=0
SESSION="test-marker-invalidate-$$"

cleanup() {
  rm -f /tmp/claude-code-critic-"$SESSION"
  rm -f /tmp/claude-minimizer-"$SESSION"
  rm -f /tmp/claude-tests-passed-"$SESSION"
  rm -f /tmp/claude-checks-passed-"$SESSION"
  rm -f /tmp/claude-pr-verified-"$SESSION"
}

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

# ─── marker-invalidate.sh: code edits invalidate review markers ───────────

echo "=== Marker Invalidation: code edit clears all review markers ==="

cleanup
touch /tmp/claude-code-critic-"$SESSION"
touch /tmp/claude-minimizer-"$SESSION"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/home/user/project/src/app.ts\",\"old_string\":\"a\",\"new_string\":\"b\"},\"session_id\":\"$SESSION\",\"cwd\":\"/home/user/project\"}" \
  | bash "$INVALIDATE_HOOK" 2>/dev/null

assert "Code edit invalidates code-critic marker" \
  '[ ! -f /tmp/claude-code-critic-$SESSION ]'
assert "Code edit invalidates minimizer marker" \
  '[ ! -f /tmp/claude-minimizer-$SESSION ]'

# ─── marker-invalidate.sh: .md edits preserve markers ─────────────────────

echo "=== Marker Invalidation: .md edits preserve markers ==="

cleanup
touch /tmp/claude-code-critic-"$SESSION"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/home/user/project/PLAN.md\",\"old_string\":\"a\",\"new_string\":\"b\"},\"session_id\":\"$SESSION\",\"cwd\":\"/home/user/project\"}" \
  | bash "$INVALIDATE_HOOK" 2>/dev/null

assert ".md edit preserves code-critic marker" \
  '[ -f /tmp/claude-code-critic-$SESSION ]'

# ─── Summary ────────────────────────────────────────────────────────────────

cleanup
echo ""
echo "═══════════════════════════════════════"
echo "marker-invalidate: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
