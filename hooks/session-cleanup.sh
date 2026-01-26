#!/bin/bash
# Session Cleanup Hook - Removes stale marker files
# Cleans up PR gate markers older than 24 hours to prevent stale state
#
# Triggered: SessionStart

find /tmp -name "claude-pr-verified-*" -mtime +1 -delete 2>/dev/null
find /tmp -name "claude-security-scanned-*" -mtime +1 -delete 2>/dev/null

echo '{}'
