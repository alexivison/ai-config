#!/usr/bin/env bash
# Marker Invalidation Hook
# Deletes review markers when implementation files are edited,
# forcing re-review after code changes.
#
# Triggered: PostToolUse on Edit|Write
# Skips: .md, /tmp/, .log, .jsonl files
# Fails open on errors (mirrors agent-trace.sh pattern)

set -e

hook_input=$(cat)

# Validate JSON input — fail open on parse errors
if ! echo "$hook_input" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
session_id=$(echo "$hook_input" | jq -r '.session_id // ""' 2>/dev/null)

# Guard: need both file path and session
if [ -z "$file_path" ] || [ -z "$session_id" ]; then
  exit 0
fi

# Skip non-implementation files — edits to these don't invalidate reviews
case "$file_path" in
  *.md)       exit 0 ;;
  /tmp/*)     exit 0 ;;
  *.log)      exit 0 ;;
  *.jsonl)    exit 0 ;;
esac

# Delete all review and verification markers — forces full re-review before PR
markers=(
  "/tmp/claude-code-critic-$session_id"
  "/tmp/claude-minimizer-$session_id"
  "/tmp/claude-codex-$session_id"
  "/tmp/claude-codex-ran-$session_id"
  "/tmp/claude-tests-passed-$session_id"
  "/tmp/claude-checks-passed-$session_id"
  "/tmp/claude-pr-verified-$session_id"
  "/tmp/claude-security-scanned-$session_id"
)

deleted=0
for marker in "${markers[@]}"; do
  if [ -f "$marker" ]; then
    rm -f "$marker"
    deleted=$((deleted + 1))
  fi
done

if [ "$deleted" -gt 0 ]; then
  echo "Markers invalidated ($deleted removed) — code edit detected: $(basename "$file_path")"
fi

exit 0
