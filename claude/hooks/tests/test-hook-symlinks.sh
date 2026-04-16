#!/usr/bin/env bash
# Verify legacy hook paths remain symlinked to the generalized entrypoints.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$SCRIPT_DIR/.."

PASS=0
FAIL=0

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

check_link() {
  local legacy="$1"
  local target="$2"
  local path="$HOOK_DIR/$legacy"
  assert "$legacy is a symlink" '[[ -L "$path" ]]'
  assert "$legacy points to $target" '[[ "$(readlink "$path")" == "'"$target"'" ]]'
}

echo "--- test-hook-symlinks.sh ---"

check_link "codex-gate.sh" "companion-gate.sh"
check_link "codex-trace.sh" "companion-trace.sh"
check_link "wizard-guard.sh" "companion-guard.sh"
check_link "claude-state.sh" "primary-state.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
