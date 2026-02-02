#!/usr/bin/env bash

# Claude Code worktree guard hook
# Blocks branch switching/creation in main worktree, suggests git worktree instead

INPUT=$(cat)
if ! COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null); then
    exit 0
fi

[ -z "$COMMAND" ] && exit 0

# Check for branch switching/creation commands
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)'; then
    exit 0
fi

# Allow file checkouts (git checkout -- file, git checkout HEAD -- file, etc.)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--' || \
   echo "$COMMAND" | grep -qE 'git\s+checkout\s+HEAD\s' || \
   echo "$COMMAND" | grep -qE 'git\s+checkout\s+[^-].*\.'; then
    exit 0
fi

# Allow switching to main/master
if echo "$COMMAND" | grep -qE 'git\s+(checkout|switch)\s+(main|master)\s*$'; then
    exit 0
fi

# Get working directory
WORKING_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$WORKING_DIR" ] && WORKING_DIR=$(pwd)

cd "$WORKING_DIR" 2>/dev/null || exit 0

# Not in a git repo - allow (nothing to protect)
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Allow if already in a worktree (not the main worktree)
MAIN_WORKTREE=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
GIT_ROOT=$(git rev-parse --show-toplevel)

if [ "$GIT_ROOT" != "$MAIN_WORKTREE" ]; then
    exit 0
fi

# Block with helpful message
REPO_NAME=$(basename "$GIT_ROOT" 2>/dev/null || echo "repo")
cat >&2 << EOF
BLOCKED: Branch switching in main worktree.

Use git worktree instead:
  git worktree add ../${REPO_NAME}-<branch-name> -b <branch-name>
  cd ../${REPO_NAME}-<branch-name>

This prevents conflicts when multiple agents work on the same repo.
EOF

exit 2
