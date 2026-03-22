#!/usr/bin/env bash
# Tests for worktree-guard.sh (PreToolUse Bash guard hook)
# Covers: file-edit blocking, branch-switch blocking, worktree allowances,
#         main/master allowances, file checkout allowances, suggestion generation.
#
# Usage: bash ~/.claude/hooks/tests/test-worktree-guard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../worktree-guard.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
}

cleanup() {
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    # Clean up any worktrees before removing
    cd "$TMPDIR_BASE"
    git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | while read -r wt; do
      [ "$wt" = "$TMPDIR_BASE" ] && continue
      git worktree remove --force "$wt" 2>/dev/null || true
    done
    cd /
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

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

# Build hook input JSON for a Bash command
hook_input() {
  local command="$1" cwd="${2:-$TMPDIR_BASE}"
  jq -cn \
    --arg cmd "$command" \
    --arg cwd "$cwd" \
    --arg sid "test-wg-$$" \
    '{tool_input: {command: $cmd}, cwd: $cwd, session_id: $sid}'
}

# Run the hook and capture output
run_hook() {
  echo "$1" | bash "$HOOK" 2>/dev/null
}

# Check if hook output is a deny decision
is_denied() {
  local output="$1"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

# Check if hook output is a pass-through (empty JSON or no deny)
is_allowed() {
  local output="$1"
  ! is_denied "$output"
}

# ─── Setup ────────────────────────────────────────────────────────────────────
setup_repo

# ─── File-edit guard tests ────────────────────────────────────────────────────

echo "=== Guard: Block sed -i ==="
output=$(run_hook "$(hook_input 'sed -i "" "s/foo/bar/" file.txt')")
assert "sed -i is blocked" 'is_denied "$output"'

echo "=== Guard: Block sed -i (GNU style) ==="
output=$(run_hook "$(hook_input "sed -i 's/foo/bar/' file.txt")")
assert "sed -i (GNU) is blocked" 'is_denied "$output"'

echo "=== Guard: Allow sed without -i ==="
output=$(run_hook "$(hook_input "sed 's/foo/bar/' file.txt")")
assert "sed without -i is allowed" 'is_allowed "$output"'

echo "=== Guard: Block awk inplace ==="
output=$(run_hook "$(hook_input "awk -i inplace '{print}' file.txt")")
assert "awk inplace is blocked" 'is_denied "$output"'

echo "=== Guard: Allow awk without inplace ==="
output=$(run_hook "$(hook_input "awk '{print}' file.txt")")
assert "awk without inplace is allowed" 'is_allowed "$output"'

# ─── Non-git commands pass through ───────────────────────────────────────────

echo "=== Guard: Non-git commands pass through ==="
output=$(run_hook "$(hook_input 'ls -la')")
assert "ls passes through" 'is_allowed "$output"'

output=$(run_hook "$(hook_input 'echo hello')")
assert "echo passes through" 'is_allowed "$output"'

output=$(run_hook "$(hook_input 'npm test')")
assert "npm test passes through" 'is_allowed "$output"'

# ─── Branch switch blocking in main worktree ─────────────────────────────────

echo "=== Guard: Block git checkout <branch> in main worktree ==="
output=$(run_hook "$(hook_input 'git checkout feature')")
assert "git checkout feature is blocked in main worktree" 'is_denied "$output"'

echo "=== Guard: Block git switch <branch> in main worktree ==="
output=$(run_hook "$(hook_input 'git switch feature')")
assert "git switch feature is blocked in main worktree" 'is_denied "$output"'

echo "=== Guard: Block git checkout -b <branch> in main worktree ==="
output=$(run_hook "$(hook_input 'git checkout -b new-feature')")
assert "git checkout -b is blocked in main worktree" 'is_denied "$output"'

echo "=== Guard: Suggest worktree in deny message ==="
output=$(run_hook "$(hook_input 'git checkout feature')")
assert "Deny message suggests worktree" 'echo "$output" | jq -r ".hookSpecificOutput.permissionDecisionReason" | grep -q "worktree"'

echo "=== Guard: Deny message includes branch name ==="
output=$(run_hook "$(hook_input 'git checkout -b my-feature')")
assert "Deny message includes branch" 'echo "$output" | jq -r ".hookSpecificOutput.permissionDecisionReason" | grep -q "my-feature"'

# ─── Allowed branch operations ───────────────────────────────────────────────

echo "=== Guard: Allow git checkout main ==="
output=$(run_hook "$(hook_input 'git checkout main')")
assert "git checkout main is allowed" 'is_allowed "$output"'

echo "=== Guard: Allow git switch main ==="
output=$(run_hook "$(hook_input 'git switch main')")
assert "git switch main is allowed" 'is_allowed "$output"'

echo "=== Guard: Allow git checkout master ==="
output=$(run_hook "$(hook_input 'git checkout master')")
assert "git checkout master is allowed" 'is_allowed "$output"'

echo "=== Guard: Allow git checkout -- <file> ==="
output=$(run_hook "$(hook_input 'git checkout -- file.txt')")
assert "git checkout -- file is allowed" 'is_allowed "$output"'

echo "=== Guard: Allow git checkout HEAD <file> ==="
output=$(run_hook "$(hook_input 'git checkout HEAD file.txt')")
assert "git checkout HEAD file is allowed" 'is_allowed "$output"'

# ─── Worktree context tests ─────────────────────────────────────────────────

echo "=== Guard: Allow branch switch in secondary worktree ==="
cd "$TMPDIR_BASE"
git worktree add "$TMPDIR_BASE/wt-feature" -b wt-test-branch 2>/dev/null
output=$(run_hook "$(hook_input 'git checkout another-branch' "$TMPDIR_BASE/wt-feature")")
assert "git checkout in secondary worktree is allowed" 'is_allowed "$output"'

# ─── Non-git-repo context ───────────────────────────────────────────────────

echo "=== Guard: Allow in non-git directory ==="
NON_GIT_DIR=$(mktemp -d)
output=$(run_hook "$(hook_input 'git checkout feature' "$NON_GIT_DIR")")
assert "git checkout in non-git dir is allowed" 'is_allowed "$output"'
rm -rf "$NON_GIT_DIR"

# ─── Edge cases ─────────────────────────────────────────────────────────────

echo "=== Guard: Empty command passes through ==="
output=$(run_hook "$(jq -cn --arg sid "test-wg-$$" '{tool_input: {}, session_id: $sid}')")
assert "Empty command passes through" 'is_allowed "$output"'

echo "=== Guard: git status (non-switch) passes through ==="
output=$(run_hook "$(hook_input 'git status')")
assert "git status passes through" 'is_allowed "$output"'

echo "=== Guard: git log passes through ==="
output=$(run_hook "$(hook_input 'git log --oneline -5')")
assert "git log passes through" 'is_allowed "$output"'

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "worktree-guard: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
