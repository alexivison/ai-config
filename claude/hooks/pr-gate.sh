#!/usr/bin/env bash
# PR Gate Hook - Enforces workflow completion before PR creation
# Uses JSONL evidence log with diff_hash matching (stale evidence auto-ignored).
#
# Three tiers (checked in priority order):
#   - CI-gate tier: hook-assigned via skill-marker.sh SKILL_TIERS mapping.
#     Requires: pr-verified + test-runner + check-runner. For repos with CI review bots.
#   - Quick tier: requires explicit "quick-tier" evidence
#     + code-critic + test-runner + check-runner.
#   - Full tier (default): pr-verified, code-critic, minimizer, codex, test-runner, check-runner
#
# The quick tier ONLY activates when quick-tier evidence exists — size alone is
# insufficient.
#
# Triggered: PreToolUse on Bash tool
# Fails open on errors (allows operation if hook can't determine state)

source "$(dirname "$0")/lib/evidence.sh"
source "$(dirname "$0")/lib/party-cli.sh"

required_evidence_types() {
  local required
  required=$(party_cli_query "$CWD" "evidence-required" 2>/dev/null || true)
  if [ -n "$required" ]; then
    echo "$required"
    return 0
  fi

  echo "pr-verified code-critic minimizer codex test-runner check-runner"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fail open if we can't parse input
if [ -z "$SESSION_ID" ]; then
  hook_log "pr-gate" "unknown" "allow" "no session_id — fail open"
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
    hook_log "pr-gate" "$SESSION_ID" "allow" "docs-only PR — gate bypassed"
    echo '{}'
    exit 0
  fi

  # Tier selection: hook-assigned tier > quick-tier > full
  # get_session_tier is hash-independent (session-level decision, not code-state).
  TIER=$(get_session_tier "$SESSION_ID" 2>/dev/null || echo "")

  if [ "$TIER" = "ci-gate" ]; then
    # CI-gate tier: repo has CI-based review bots — local critics/codex skipped
    REQUIRED="pr-verified test-runner check-runner"
  elif check_evidence "$SESSION_ID" "quick-tier" "$CWD" 2>/dev/null; then
    # Quick tier: explicit quick-tier evidence opts the session into the lighter gate.
    REQUIRED="quick-tier code-critic test-runner check-runner"
  else
    # No tier evidence — full gate requires all evidence at current hash
    REQUIRED=$(required_evidence_types)
  fi

  DIAG_FILE=$(mktemp 2>/dev/null || echo "/tmp/pr-gate-diag-$$")
  MISSING=$(check_all_evidence "$SESSION_ID" "$REQUIRED" "$CWD" 2>"$DIAG_FILE" || true)
  STALE_DIAG=""
  [ -f "$DIAG_FILE" ] && STALE_DIAG=$(cat "$DIAG_FILE") && rm -f "$DIAG_FILE"

  if [ -n "$MISSING" ]; then
    REASON="BLOCKED: PR gate requirements not met. Missing:$MISSING. Complete all workflow steps before creating PR."
    [ -n "$STALE_DIAG" ] && REASON="${REASON}${STALE_DIAG}"
    hook_log "pr-gate" "$SESSION_ID" "deny" "missing:$MISSING"
    jq -cn --arg reason "$REASON" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
  fi

  hook_log "pr-gate" "$SESSION_ID" "allow" "pr-create passed"
fi

# Allow by default
hook_log "pr-gate" "$SESSION_ID" "allow" ""
echo '{}'
