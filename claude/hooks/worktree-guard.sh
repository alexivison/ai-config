#!/usr/bin/env bash

# Claude Code Bash guard hook
# 1. Blocks branch switching/creation in main worktree
# 2. Blocks Bash-based file editing (sed -i, awk > file, etc.) — use Edit/Write tools
#
# Triggered: PreToolUse on Bash tool
# Outputs JSON on all paths (required by hook runner when sharing a hook group)

INPUT=$(cat)
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
    echo '{}'
    exit 0
fi

if [ -z "$COMMAND" ]; then
    echo '{}'
    exit 0
fi

# ── Guard: Block Bash file-writing on implementation files ──
# Marker invalidation only fires on Edit|Write tools. Bash edits bypass it.
# Only block explicit in-place mutation commands (sed -i, awk inplace).
# Redirect operators (>, >>) are too common in read-only shell (>/dev/null, etc.) to block broadly.
if echo "$COMMAND" | grep -qE 'sed\s+-i|awk\s.*-i\s*inplace'; then
    cat << 'GUARD_EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Use Edit/Write tools instead of Bash for file modifications. Marker invalidation depends on Edit/Write tool hooks."
  }
}
GUARD_EOF
    exit 0
fi

# ── Guard: Block branch switching in main worktree ──

# Check for branch switching/creation commands
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)'; then
    echo '{}'
    exit 0
fi

# Allow file checkouts (git checkout [<tree-ish>] -- <pathspec>)
if echo "$COMMAND" | grep -qE 'git\s+checkout\b.*\s--(\s|$)'; then
    echo '{}'
    exit 0
fi
# Allow git checkout HEAD <file> (implicit pathspec, no -- separator)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+HEAD\s'; then
    echo '{}'
    exit 0
fi

# Allow switching to main/master
if echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s+(main|master)\s*$'; then
    echo '{}'
    exit 0
fi

# Get working directory
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$WORKING_DIR" ] && WORKING_DIR=$(pwd)

cd "$WORKING_DIR" 2>/dev/null || { echo '{}'; exit 0; }

# Not in a git repo - allow (nothing to protect)
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo '{}'
    exit 0
fi

# Allow if already in a worktree (not the main worktree)
MAIN_WORKTREE=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
GIT_ROOT=$(git rev-parse --show-toplevel)

if [ "$GIT_ROOT" != "$MAIN_WORKTREE" ]; then
    echo '{}'
    exit 0
fi

# Rewrite: branch switch → worktree add
REPO_NAME=$(basename "$GIT_ROOT" 2>/dev/null || echo "repo")

# Parse arguments after git checkout/switch
ARGS=$(echo "$COMMAND" | sed -E 's/^.*git[[:space:]]+(checkout|switch)[[:space:]]+//')
read -ra TOKENS <<< "$ARGS"

CREATE_FLAG=""
BRANCH=""
START_POINT=""

case "${TOKENS[0]:-}" in
  -b|-c|--create)
    CREATE_FLAG="-b"
    BRANCH="${TOKENS[1]:-}"
    START_POINT="${TOKENS[2]:-}"
    ;;
  -B|-C)
    CREATE_FLAG="-B"
    BRANCH="${TOKENS[1]:-}"
    START_POINT="${TOKENS[2]:-}"
    ;;
  -*)
    # Unknown flag — can't parse unambiguously
    BRANCH=""
    ;;
  *)
    BRANCH="${TOKENS[0]:-}"
    # Extra args without creation flag → ambiguous
    [ ${#TOKENS[@]} -gt 1 ] && BRANCH=""
    ;;
esac

# Validate: non-empty, safe characters only (prevents shell/JSON injection)
SAFE_REF='^[a-zA-Z0-9._/-]+$'
DENY=false
if [ -z "$BRANCH" ] || ! echo "$BRANCH" | grep -qE "$SAFE_REF"; then
  DENY=true
elif [ -n "$START_POINT" ] && ! echo "$START_POINT" | grep -qE "$SAFE_REF"; then
  DENY=true
fi

if [ "$DENY" = true ]; then
  jq -cn \
    --arg reason "BLOCKED: Branch switching in main worktree. Use: git worktree add ../${REPO_NAME}-<branch> [-b] <branch>" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

WORKTREE_DIR=$(echo "$BRANCH" | tr '/' '-')
WORKTREE_PATH="../${REPO_NAME}-${WORKTREE_DIR}"

if [ -n "$CREATE_FLAG" ]; then
  REWRITTEN="git worktree add ${WORKTREE_PATH} ${CREATE_FLAG} ${BRANCH}"
  [ -n "$START_POINT" ] && REWRITTEN="${REWRITTEN} ${START_POINT}"
else
  REWRITTEN="git worktree add ${WORKTREE_PATH} ${BRANCH}"
fi
REWRITTEN="${REWRITTEN} && cd ${WORKTREE_PATH}"

# Emit response via jq (safe JSON encoding)
jq -cn \
  --arg reason "Rewrote branch switch to worktree: ${BRANCH} → ${WORKTREE_PATH}" \
  --arg cmd "$REWRITTEN" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason, updatedInput: {command: $cmd}}}'
exit 0
