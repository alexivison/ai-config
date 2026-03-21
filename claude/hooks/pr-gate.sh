#!/usr/bin/env bash
# PR Gate Hook - Enforces workflow completion before PR creation
# Uses JSONL evidence log with diff_hash matching (stale evidence auto-ignored).
#
# Two tiers:
#   - Quick tier: requires explicit "quick-tier" evidence (from quick-fix-workflow)
#     + code-critic + test-runner + check-runner. Size-gated: ≤30 lines, ≤3 files, 0 new files.
#   - Full tier (default): pr-verified, code-critic, minimizer, codex, test-runner, check-runner
#
# The quick tier ONLY activates when quick-tier evidence exists — size alone is
# insufficient. This prevents behavioral changes from skipping review.
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
  CWD=$(_resolve_cwd "$SESSION_ID" "$CWD")
  # Fail closed: assume code PR unless we can prove docs-only
  # Use working-tree diff (no ..HEAD) to match evidence.sh scope
  IMPL_FILES="unknown"
  if [ -n "$CWD" ]; then
    if ! _resolve_merge_base "$CWD"; then
      IMPL_FILES="unknown"
    elif [ -n "$_EVIDENCE_MERGE_BASE" ]; then
      IMPL_FILES=$(cd "$CWD" 2>/dev/null && git diff --name-only "$_EVIDENCE_MERGE_BASE" 2>/dev/null \
        | grep -E '\.(sh|bash|go|py|ts|js|tsx|jsx|rs|rb|java|kt|swift|c|cpp|h|hpp|sql|proto|css|scss|html|vue|svelte|zig|hs|ex|exs|el|clj|lua|php|pl|pm|scala|groovy|tf|nix|cmake|gradle|xml|mod|sum|lock)$|(^|/)(Makefile|Dockerfile|Jenkinsfile|Vagrantfile|Rakefile|Gemfile|Taskfile|go\.sum|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|Gemfile\.lock|poetry\.lock|composer\.lock|requirements\.txt|constraints\.txt|pip\.conf|setup\.cfg|tox\.ini)$' || true)
    fi
  fi

  # Docs/config-only PRs skip the gate entirely (empty = no impl files found)
  if [ -z "$IMPL_FILES" ]; then
    echo '{}'
    exit 0
  fi

  # Quick tier: requires explicit quick-tier evidence AND small diff
  # The quick-fix-workflow skill writes quick-tier evidence after scope validation.
  # Size alone never qualifies — prevents behavioral changes from skipping review.
  if check_evidence "$SESSION_ID" "quick-tier" "$CWD" 2>/dev/null; then
    STATS=$(diff_stats "$CWD")
    LINES=$(echo "$STATS" | awk '{print $1}')
    FILES=$(echo "$STATS" | awk '{print $2}')
    NEW_FILES=$(echo "$STATS" | awk '{print $3}')

    if [ "$LINES" -le 30 ] && [ "$FILES" -le 3 ] && [ "$NEW_FILES" -eq 0 ]; then
      REQUIRED="quick-tier code-critic test-runner check-runner"
    else
      # Over size limit — fall through to full gate
      REQUIRED="pr-verified code-critic minimizer codex test-runner check-runner"
    fi
  else
    # No quick-tier evidence — full gate
    # Two-phase model: if codex approved at current hash and critics ran at
    # any point in this session, skip critic hash-matching. Phase 1 (codex-gate)
    # already enforced critics before the first --review, so codex-ran implies
    # critics passed. Hash-independence avoids the invalidation loop where fix
    # commits between iterations force unnecessary critic re-runs.
    EVIDENCE_FILE=$(evidence_file "$SESSION_ID")
    HAS_CODEX_RAN=""
    if [ -f "$EVIDENCE_FILE" ]; then
      HAS_CODEX_RAN=$(jq -r 'select(.type == "codex-ran")' "$EVIDENCE_FILE" 2>/dev/null | head -1)
    fi
    if check_evidence "$SESSION_ID" "codex" "$CWD" 2>/dev/null && \
       [ -n "$HAS_CODEX_RAN" ] && \
       jq -e 'select(.type == "code-critic")' "$EVIDENCE_FILE" >/dev/null 2>&1 && \
       jq -e 'select(.type == "minimizer")' "$EVIDENCE_FILE" >/dev/null 2>&1; then
      REQUIRED="pr-verified codex test-runner check-runner"
    else
      REQUIRED="pr-verified code-critic minimizer codex test-runner check-runner"
    fi
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
