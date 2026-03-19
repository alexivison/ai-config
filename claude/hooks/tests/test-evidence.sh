#!/usr/bin/env bash
# Tests for evidence.sh library
# Covers: compute_diff_hash, append_evidence, check_evidence, check_all_evidence, diff_stats
#
# Usage: bash ~/.claude/hooks/tests/test-evidence.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION="test-evidence-$$"
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

# Create a temp git repo for testing
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

cleanup() {
  rm -f "$(evidence_file "$SESSION")"
  rm -f "/tmp/claude-evidence-${SESSION}.lock"
  rm -f "/tmp/claude-worktree-${SESSION}"
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    # Remove any linked worktrees before deleting the repo
    git -C "$TMPDIR_BASE" worktree list --porcelain 2>/dev/null | grep '^worktree ' | while read -r _ wt; do
      [ "$wt" != "$TMPDIR_BASE" ] && git -C "$TMPDIR_BASE" worktree remove "$wt" 2>/dev/null || true
    done
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

# ═══ compute_diff_hash ═══════════════════════════════════════════════════════

echo "=== compute_diff_hash: clean state ==="
setup_repo
HASH=$(compute_diff_hash "$TMPDIR_BASE")
assert "Clean branch returns 'clean'" '[ "$HASH" = "clean" ]'

echo "=== compute_diff_hash: committed change ==="
echo "changed" > file.txt
git add file.txt && git commit -q -m "change"
HASH1=$(compute_diff_hash "$TMPDIR_BASE")
assert "Committed change returns a hash" '[ "$HASH1" != "clean" ] && [ "$HASH1" != "unknown" ]'
assert "Hash is 64 hex chars" '[ ${#HASH1} -eq 64 ]'

echo "=== compute_diff_hash: consistency ==="
HASH2=$(compute_diff_hash "$TMPDIR_BASE")
assert "Same state → same hash" '[ "$HASH1" = "$HASH2" ]'

echo "=== compute_diff_hash: change detection ==="
echo "more changes" >> file.txt
git add file.txt && git commit -q -m "more"
HASH3=$(compute_diff_hash "$TMPDIR_BASE")
assert "Different commit → different hash" '[ "$HASH3" != "$HASH1" ]'

echo "=== compute_diff_hash: .md exclusion ==="
HASH_BEFORE=$(compute_diff_hash "$TMPDIR_BASE")
echo "docs" > readme.md
git add readme.md && git commit -q -m "add docs"
HASH_AFTER=$(compute_diff_hash "$TMPDIR_BASE")
assert ".md file doesn't change hash" '[ "$HASH_BEFORE" = "$HASH_AFTER" ]'

echo "=== compute_diff_hash: unstaged edit changes hash ==="
HASH_BEFORE=$(compute_diff_hash "$TMPDIR_BASE")
echo "unstaged edit" >> file.txt
HASH_AFTER=$(compute_diff_hash "$TMPDIR_BASE")
assert "Unstaged edit changes hash" '[ "$HASH_BEFORE" != "$HASH_AFTER" ]'
git checkout -- file.txt  # restore

echo "=== compute_diff_hash: staged-only edit changes hash ==="
HASH_BEFORE=$(compute_diff_hash "$TMPDIR_BASE")
echo "staged edit" >> file.txt
git add file.txt
HASH_AFTER=$(compute_diff_hash "$TMPDIR_BASE")
assert "Staged edit changes hash" '[ "$HASH_BEFORE" != "$HASH_AFTER" ]'
git reset -q HEAD file.txt && git checkout -- file.txt  # restore

echo "=== compute_diff_hash: not a git repo ==="
NOT_GIT=$(mktemp -d)
HASH=$(compute_diff_hash "$NOT_GIT")
assert "Non-git dir returns 'unknown'" '[ "$HASH" = "unknown" ]'
rm -rf "$NOT_GIT"

echo "=== compute_diff_hash: missing dir ==="
HASH=$(compute_diff_hash "/nonexistent/path")
assert "Missing dir returns 'unknown'" '[ "$HASH" = "unknown" ]'

echo "=== compute_diff_hash: empty string ==="
HASH=$(compute_diff_hash "")
assert "Empty string returns 'unknown'" '[ "$HASH" = "unknown" ]'

echo "=== compute_diff_hash: dirty working tree on merge-base==HEAD ==="
# Go back to a state where merge-base == HEAD (clean branch) but working tree is dirty
cleanup
setup_repo
# feature branch at same point as main, no diff
HASH_CLEAN=$(compute_diff_hash "$TMPDIR_BASE")
assert "merge-base==HEAD, clean tree → 'clean'" '[ "$HASH_CLEAN" = "clean" ]'
echo "dirty" >> file.txt
HASH_DIRTY=$(compute_diff_hash "$TMPDIR_BASE")
assert "merge-base==HEAD, dirty tree → hash (not clean)" '[ "$HASH_DIRTY" != "clean" ] && [ "$HASH_DIRTY" != "unknown" ]'
git checkout -- file.txt

# ═══ append_evidence ═════════════════════════════════════════════════════════

echo "=== append_evidence: creates valid JSONL ==="
cleanup
setup_repo
echo "impl" > impl.sh
git add impl.sh && git commit -q -m "add impl"
append_evidence "$SESSION" "code-critic" "APPROVED" "$TMPDIR_BASE"
EFILE=$(evidence_file "$SESSION")
assert "Evidence file created" '[ -f "$EFILE" ]'
assert "Single line" '[ "$(wc -l < "$EFILE" | tr -d " ")" = "1" ]'
assert "Valid JSON" 'jq -e . "$EFILE" >/dev/null 2>&1'
assert "Type field correct" '[ "$(jq -r .type "$EFILE")" = "code-critic" ]'
assert "Result field correct" '[ "$(jq -r .result "$EFILE")" = "APPROVED" ]'
assert "Has diff_hash" '[ "$(jq -r .diff_hash "$EFILE")" != "null" ]'
assert "Has timestamp" '[ "$(jq -r .timestamp "$EFILE")" != "null" ]'

echo "=== append_evidence: concurrent writes ==="
cleanup
setup_repo
echo "concurrent" > conc.sh
git add conc.sh && git commit -q -m "concurrent test"
# Stress test: 20 parallel appends
for i in $(seq 1 20); do
  append_evidence "$SESSION" "stress-$i" "PASS" "$TMPDIR_BASE" &
done
wait
EFILE=$(evidence_file "$SESSION")
LINE_COUNT=$(wc -l < "$EFILE" | tr -d ' ')
assert "20 parallel appends → 20 lines" '[ "$LINE_COUNT" = "20" ]'
# Validate every line is valid JSON
VALID_COUNT=$(jq -c . "$EFILE" 2>/dev/null | wc -l | tr -d ' ')
assert "All 20 lines valid JSON" '[ "$VALID_COUNT" = "20" ]'

# ═══ check_evidence ══════════════════════════════════════════════════════════

echo "=== check_evidence: matches on type + diff_hash ==="
cleanup
setup_repo
echo "check" > check.sh
git add check.sh && git commit -q -m "check test"
append_evidence "$SESSION" "test-runner" "PASS" "$TMPDIR_BASE"
assert "Matching evidence found" 'check_evidence "$SESSION" "test-runner" "$TMPDIR_BASE"'

echo "=== check_evidence: rejects wrong type ==="
assert "Wrong type rejected" '! check_evidence "$SESSION" "code-critic" "$TMPDIR_BASE"'

echo "=== check_evidence: rejects stale diff_hash ==="
echo "stale edit" >> check.sh
git add check.sh && git commit -q -m "stale"
assert "Stale hash rejected" '! check_evidence "$SESSION" "test-runner" "$TMPDIR_BASE"'

echo "=== check_evidence: no evidence file ==="
rm -f "$(evidence_file "$SESSION")"
assert "Missing file returns 1" '! check_evidence "$SESSION" "test-runner" "$TMPDIR_BASE"'

# ═══ check_all_evidence ══════════════════════════════════════════════════════

echo "=== check_all_evidence: returns missing types ==="
cleanup
setup_repo
echo "all" > all.sh
git add all.sh && git commit -q -m "all test"
append_evidence "$SESSION" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION" "check-runner" "CLEAN" "$TMPDIR_BASE"
MISSING=$(check_all_evidence "$SESSION" "test-runner check-runner code-critic" "$TMPDIR_BASE" 2>&1 || true)
assert "Reports code-critic missing" 'echo "$MISSING" | grep -q "code-critic"'
assert "Does not report test-runner" '! echo "$MISSING" | grep -q "test-runner"'

echo "=== check_all_evidence: all present ==="
append_evidence "$SESSION" "code-critic" "APPROVED" "$TMPDIR_BASE"
assert "All present returns 0" 'check_all_evidence "$SESSION" "test-runner check-runner code-critic" "$TMPDIR_BASE"'

# ═══ diff_stats ══════════════════════════════════════════════════════════════

echo "=== diff_stats: correct counts ==="
cleanup
setup_repo
echo "line1" > new.sh
echo "line2" >> new.sh
git add new.sh && git commit -q -m "new file"
STATS=$(diff_stats "$TMPDIR_BASE")
LINES=$(echo "$STATS" | awk '{print $1}')
FILES=$(echo "$STATS" | awk '{print $2}')
NEW=$(echo "$STATS" | awk '{print $3}')
assert "Files count is 1" '[ "$FILES" = "1" ]'
assert "New files count is 1" '[ "$NEW" = "1" ]'
assert "Lines count > 0" '[ "$LINES" -gt 0 ]'

echo "=== diff_stats: no changes ==="
cleanup
setup_repo
STATS=$(diff_stats "$TMPDIR_BASE")
assert "Clean branch → 0 0 0" '[ "$STATS" = "0 0 0" ]'

echo "=== diff_stats: non-git dir ==="
NOT_GIT=$(mktemp -d)
STATS=$(diff_stats "$NOT_GIT")
assert "Non-git → 0 0 0" '[ "$STATS" = "0 0 0" ]'
rm -rf "$NOT_GIT"

# ═══ _resolve_cwd ════════════════════════════════════════════════════════════

echo "=== _resolve_cwd: no override file ==="
RESOLVED=$(_resolve_cwd "$SESSION" "/some/path")
assert "No override → returns hook_cwd" '[ "$RESOLVED" = "/some/path" ]'

echo "=== _resolve_cwd: valid override file ==="
cleanup
setup_repo
WORKTREE_DIR=$(mktemp -d)
cd "$TMPDIR_BASE" && git worktree add "$WORKTREE_DIR" main 2>/dev/null
echo "$WORKTREE_DIR" > "/tmp/claude-worktree-${SESSION}"
RESOLVED=$(_resolve_cwd "$SESSION" "/wrong/path")
assert "Valid override → returns worktree path" '[ "$RESOLVED" = "$WORKTREE_DIR" ]'
rm -f "/tmp/claude-worktree-${SESSION}"
git -C "$TMPDIR_BASE" worktree remove "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"

echo "=== _resolve_cwd: override points to nonexistent dir ==="
echo "/nonexistent/worktree" > "/tmp/claude-worktree-${SESSION}"
RESOLVED=$(_resolve_cwd "$SESSION" "/fallback/path")
assert "Bad override → returns hook_cwd" '[ "$RESOLVED" = "/fallback/path" ]'
rm -f "/tmp/claude-worktree-${SESSION}"

# ═══ Worktree scenario (integration) ════════════════════════════════════════

echo "=== compute_diff_hash: worktree divergence ==="
cleanup
setup_repo
# setup_repo leaves us on 'feature' branch with same commit as main
# Add a commit on feature so it diverges
echo "feature work" > feature.sh
git add feature.sh && git commit -q -m "feature commit"

MAIN_DIR="$TMPDIR_BASE"
cd "$MAIN_DIR" && git checkout -q main
WORKTREE_DIR=$(mktemp -d)
git worktree add "$WORKTREE_DIR" feature

# Worktree (on feature with diverged commit) should get a real hash
HASH_WT=$(compute_diff_hash "$WORKTREE_DIR")
assert "Worktree with diverged branch → real hash" '[ "$HASH_WT" != "clean" ] && [ "$HASH_WT" != "unknown" ]'

# Main repo cwd (on main) returns "clean" — this IS the bug
HASH_MAIN=$(compute_diff_hash "$MAIN_DIR")
assert "Main repo on main branch → 'clean'" '[ "$HASH_MAIN" = "clean" ]'

# With override file, append_evidence should use worktree hash
echo "$WORKTREE_DIR" > "/tmp/claude-worktree-${SESSION}"
append_evidence "$SESSION" "test-worktree" "PASS" "$MAIN_DIR"
EFILE=$(evidence_file "$SESSION")
STORED_HASH=$(jq -r '.diff_hash' "$EFILE" | tail -1)
assert "Evidence with override uses worktree hash (not 'clean')" '[ "$STORED_HASH" = "$HASH_WT" ]'

# check_evidence should also resolve to worktree hash
assert "check_evidence matches with override" 'check_evidence "$SESSION" "test-worktree" "$MAIN_DIR"'

# Clean up
rm -f "/tmp/claude-worktree-${SESSION}"
git -C "$MAIN_DIR" worktree remove "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "evidence.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
