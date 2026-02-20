#!/usr/bin/env bash
# Session Cleanup Hook - Removes stale marker files
# Cleans up markers older than 24 hours to prevent stale state
#
# Triggered: SessionStart

find /tmp -name "claude-pr-verified-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-security-scanned-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-skill-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-code-critic-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-tests-passed-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-checks-passed-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-minimizer-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-codex-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-codex-ran-*" -mtime +1 -delete 2>/dev/null

echo '{}'
