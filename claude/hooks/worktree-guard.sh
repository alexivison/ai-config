#!/usr/bin/env bash

# Claude Code worktree guard hook
# Blocks branch switching/creation in main worktree, suggests git worktree instead
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

# Check for branch switching/creation commands
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)'; then
    echo '{}'
    exit 0
fi

# Allow file checkouts (git checkout -- file, git checkout HEAD -- file, etc.)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--' || \
   echo "$COMMAND" | grep -qE 'git\s+checkout\s+HEAD\s' || \
   echo "$COMMAND" | grep -qE 'git\s+checkout\s+[^-].*\.'; then
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

# Block with proper JSON deny format
REPO_NAME=$(basename "$GIT_ROOT" 2>/dev/null || echo "repo")
cat << EOF
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: Branch switching in main worktree. Use: git worktree add ../${REPO_NAME}-<branch> -b <branch>"
  }
}
EOF
exit 0
