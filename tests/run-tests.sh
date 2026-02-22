#!/usr/bin/env bash
# Test runner for tmux integration tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
ERRORS=()

run_suite() {
  local suite="$1"
  echo "=== $suite ==="
  if bash "$SCRIPT_DIR/$suite"; then
    PASS=$((PASS + 1))
    echo "  PASS"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$suite")
    echo "  FAIL"
  fi
  echo ""
}

echo "tmux Integration Test Suite"
echo "==========================="
echo ""

run_suite "test-party.sh"
run_suite "test-tmux-codex.sh"
run_suite "test-tmux-claude.sh"
run_suite "test-hooks.sh"

echo "==========================="
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  echo "Failed suites:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
