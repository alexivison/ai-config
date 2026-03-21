#!/usr/bin/env bash
# session-id-helper.sh — Discover the current Claude Code session ID
#
# The session_id is a runtime UUID injected into hook JSON input. Claude (the agent)
# cannot access it directly. This helper finds it from evidence artifacts.
#
# Strategy: look for the most recent worktree override or evidence file
# associated with the current working directory's git repo.
#
# Usage:
#   source "$(dirname "$0")/lib/session-id-helper.sh"
#   sid=$(discover_session_id)
#   # or from CLI:
#   bash ~/.claude/hooks/lib/session-id-helper.sh [cwd]

discover_session_id() {
  local cwd="${1:-$(pwd)}"

  # Strategy 1: Check party session manifest (most reliable in party sessions)
  if [ -n "${CLAUDE_PARTY_SESSION:-}" ]; then
    local manifest="/tmp/party-${CLAUDE_PARTY_SESSION}/manifest.json"
    if [ -f "$manifest" ]; then
      local sid
      sid=$(jq -r '.claude_session_id // empty' "$manifest" 2>/dev/null)
      if [ -n "$sid" ]; then
        echo "$sid"
        return 0
      fi
    fi
  fi

  # Strategy 2: Find worktree override files that point to our cwd
  local resolved_cwd
  resolved_cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || return 1

  for f in /tmp/claude-worktree-*; do
    [ -f "$f" ] || continue
    local override_path
    override_path=$(cat "$f")
    if [ -n "$override_path" ] && [ -d "$override_path" ]; then
      local resolved_override
      resolved_override=$(cd "$override_path" 2>/dev/null && pwd -P) || continue
      if [ "$resolved_override" = "$resolved_cwd" ]; then
        # Extract session ID from filename: /tmp/claude-worktree-{session_id}
        local sid="${f#/tmp/claude-worktree-}"
        echo "$sid"
        return 0
      fi
    fi
  done

  # Strategy 3: Find evidence files and match by repo
  local repo_root
  repo_root=$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1

  local newest_sid="" newest_ts=0
  for f in /tmp/claude-evidence-*.jsonl; do
    [ -f "$f" ] || continue
    # Check if any entry references our repo (via cwd in _resolve_cwd)
    local sid="${f#/tmp/claude-evidence-}"
    sid="${sid%.jsonl}"
    # Verify this session's worktree override relates to our repo
    local override="/tmp/claude-worktree-${sid}"
    if [ -f "$override" ]; then
      local op
      op=$(cat "$override")
      if [ -n "$op" ] && [ -d "$op" ]; then
        local op_root
        op_root=$(cd "$op" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || continue
        if [ "$op_root" = "$repo_root" ]; then
          local mtime
          mtime=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null || echo 0)
          if [ "$mtime" -gt "$newest_ts" ]; then
            newest_sid="$sid"
            newest_ts="$mtime"
          fi
        fi
      fi
    fi
  done

  if [ -n "$newest_sid" ]; then
    echo "$newest_sid"
    return 0
  fi

  return 1
}

# CLI mode: print session ID when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sid=$(discover_session_id "${1:-}")
  if [ -n "$sid" ]; then
    echo "$sid"
  else
    echo "ERROR: Could not discover session ID for ${1:-$(pwd)}" >&2
    exit 1
  fi
fi
