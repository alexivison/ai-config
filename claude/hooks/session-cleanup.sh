#!/usr/bin/env bash
# Session Cleanup Hook - Removes stale marker files
# Cleans up markers older than 24 hours to prevent stale state
#
# Triggered: SessionStart

# Ensure logs dir exists (PreToolUse hooks redirect stderr here)
mkdir -p "$HOME/.claude/logs" 2>/dev/null

find /tmp -maxdepth 1 -name "claude-*" -mtime +1 -delete 2>/dev/null

echo '{}'
