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

echo "Test Suite"
echo "==========================="
echo ""

run_suite "test-hooks.sh"
run_suite "test-weekly-report.sh"
run_suite "test-party-routing.sh"
run_suite "test-transport-role-routing.sh"
run_suite "test-party-multilaunch.sh"
run_suite "test-wrapper-delegation.sh"

echo "==========================="
echo "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
  echo "Failed suites:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
