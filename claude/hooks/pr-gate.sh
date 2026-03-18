#!/usr/bin/env bash
# PR Gate Hook - Enforces workflow completion before PR creation
# Uses JSONL evidence log with diff_hash matching (stale evidence auto-ignored).
#
# Tiered gate:
#   - Small changes (≤30 changed lines adds+dels, ≤3 files, 0 new files) → test-runner + check-runner
#   - Full gate → pr-verified, code-critic, minimizer, codex, test-runner, check-runner
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (allows operation if hook can't determine state)

source "$(dirname "$0")/lib/evidence.sh"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Only check PR creation (not git push - allow pushing during development)
# Note: Don't anchor with ^ since command may be chained (e.g., "cd ... && gh pr create")
if echo "$COMMAND" | grep -qE 'gh pr create'; then
  # Check if this is a docs/config-only PR (no implementation files in full branch diff)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  # Fail closed: assume code PR unless we can prove docs-only
  # Use working-tree diff (no ..HEAD) to match evidence.sh scope
  IMPL_FILES="unknown"
  if [ -n "$CWD" ]; then
    DEFAULT_BRANCH=$(cd "$CWD" 2>/dev/null && git rev-parse --verify refs/heads/main >/dev/null 2>&1 && echo main || echo master)
    MERGE_BASE=$(cd "$CWD" 2>/dev/null && git merge-base "$DEFAULT_BRANCH" HEAD 2>/dev/null || echo "")
    if [ -n "$MERGE_BASE" ]; then
      IMPL_FILES=$(cd "$CWD" 2>/dev/null && git diff --name-only "$MERGE_BASE" 2>/dev/null \
        | grep -vE '\.(md|json|toml|yaml|yml)$' || true)
    fi
  fi

  # Docs/config-only PRs skip the gate entirely (empty = no impl files found)
  if [ -z "$IMPL_FILES" ]; then
    echo '{}'
    exit 0
  fi

  # Determine gate tier based on diff stats
  STATS=$(diff_stats "$CWD")
  LINES=$(echo "$STATS" | awk '{print $1}')
  FILES=$(echo "$STATS" | awk '{print $2}')
  NEW_FILES=$(echo "$STATS" | awk '{print $3}')

  if [ "$LINES" -le 30 ] && [ "$FILES" -le 3 ] && [ "$NEW_FILES" -eq 0 ]; then
    # Quick tier: small non-behavioral changes
    REQUIRED="test-runner check-runner"
  else
    # Full tier: all evidence required
    REQUIRED="pr-verified code-critic minimizer codex test-runner check-runner"
  fi

  MISSING=$(check_all_evidence "$SESSION_ID" "$REQUIRED" "$CWD" 2>&1 || true)

  if [ -n "$MISSING" ]; then
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: PR gate requirements not met. Missing:$MISSING. Complete all workflow steps before creating PR."
  }
}
EOF
    exit 0
  fi
fi

# Allow by default
echo '{}'
