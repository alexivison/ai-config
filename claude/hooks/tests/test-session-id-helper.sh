#!/usr/bin/env bash
# Tests for session-id-helper.sh
# Covers: Strategy 2 (worktree override + repo root match), fallback behavior, CLI mode
#
# Usage: bash ~/.claude/hooks/tests/test-session-id-helper.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/../lib/session-id-helper.sh"
source "$HELPER"

PASS=0
FAIL=0
TEST_SID="test-session-helper-$$"
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

cleanup() {
  rm -f "/tmp/claude-worktree-${TEST_SID}"
  rm -f "/tmp/claude-evidence-${TEST_SID}.jsonl"
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

echo "--- test-session-id-helper.sh ---"

# ═══ Strategy 2: Worktree override discovery ════════════════════════════════

echo "=== Strategy 2: discovers session from worktree override ==="
TMPDIR_BASE=$(mktemp -d)
cd "$TMPDIR_BASE"
git init -q
git checkout -q -b main
echo "init" > file.sh
git add file.sh && git commit -q -m "init"

# Write a worktree override pointing to this temp repo
echo "$TMPDIR_BASE" > "/tmp/claude-worktree-${TEST_SID}"

FOUND_SID=$(discover_session_id "$TMPDIR_BASE")
assert "Discovers session ID from worktree override" \
  '[ "$FOUND_SID" = "$TEST_SID" ]'

echo "=== Strategy 2: discovers session from subdirectory ==="
SUBDIR="$TMPDIR_BASE/subdir/nested"
mkdir -p "$SUBDIR"
echo "$TMPDIR_BASE" > "/tmp/claude-worktree-${TEST_SID}"
FOUND_SID=$(discover_session_id "$SUBDIR")
assert "Discovers session ID from subdirectory of repo" \
  '[ "$FOUND_SID" = "$TEST_SID" ]'

echo "=== Strategy 2: ignores empty override files ==="
echo "" > "/tmp/claude-worktree-${TEST_SID}"
FOUND_SID=$(discover_session_id "$TMPDIR_BASE" 2>/dev/null || echo "")
assert "Empty override file returns no match" \
  '[ "$FOUND_SID" != "$TEST_SID" ]'

# ═══ Strategy 3: Evidence file discovery ════════════════════════════════════

echo "=== Fallback: evidence file without worktree override returns nothing ==="
TMPDIR_BASE=$(mktemp -d)
cd "$TMPDIR_BASE"
git init -q && git checkout -q -b main
echo "init" > file.sh && git add file.sh && git commit -q -m "init"

# Evidence exists but no worktree override — both Strategy 2 and 3 need overrides
rm -f "/tmp/claude-worktree-${TEST_SID}"
echo '{"type":"test-runner","result":"PASS","diff_hash":"abc123"}' > "/tmp/claude-evidence-${TEST_SID}.jsonl"
FOUND_SID=$(discover_session_id "$TMPDIR_BASE" 2>/dev/null || echo "none")
assert "No discovery when evidence exists but no worktree override" \
  '[ "$FOUND_SID" = "none" ]'

# ═══ CLI mode ═══════════════════════════════════════════════════════════════

echo "=== CLI mode: returns session ID ==="
echo "$TMPDIR_BASE" > "/tmp/claude-worktree-${TEST_SID}"
CLI_OUTPUT=$(bash "$HELPER" "$TMPDIR_BASE")
assert "CLI mode outputs session ID" \
  '[ "$CLI_OUTPUT" = "$TEST_SID" ]'

echo "=== CLI mode: exits 1 when no session found ==="
rm -f "/tmp/claude-worktree-${TEST_SID}"
EMPTY_DIR=$(mktemp -d)
cd "$EMPTY_DIR"
git init -q && echo "x" > f && git add f && git commit -q -m "init"
CLI_EXIT=0
bash "$HELPER" "$EMPTY_DIR" >/dev/null 2>&1 || CLI_EXIT=$?
assert "CLI mode exits 1 when session not found" \
  '[ "$CLI_EXIT" -eq 1 ]'
rm -rf "$EMPTY_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
