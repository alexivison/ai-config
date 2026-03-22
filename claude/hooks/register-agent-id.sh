#!/usr/bin/env bash
# Register Claude's session ID with the party session state.
# Triggered: SessionStart
# Writes to: $STATE_DIR/claude-session-id + tmux environment
set -e

hook_input=$(cat)

session_id=$(echo "$hook_input" | jq -r '.session_id // empty' 2>/dev/null)
if [[ -z "$session_id" ]]; then
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../session/party-lib.sh"

if ! discover_session 2>/dev/null; then
  echo '{}'
  exit 0
fi

# Write once — skip if already registered with this ID
id_file="$STATE_DIR/claude-session-id"
if [[ -f "$id_file" ]] && [[ "$(cat "$id_file")" == "$session_id" ]]; then
  echo '{}'
  exit 0
fi

printf '%s\n' "$session_id" > "$id_file"
tmux set-environment -t "$SESSION_NAME" CLAUDE_SESSION_ID "$session_id" 2>/dev/null || true

# Persist to manifest for resume path (continue.go reads claude_session_id from manifest)
manifest="$(party_state_file "$SESSION_NAME")"
if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"
  if jq --arg v "$session_id" '.claude_session_id = $v' "$manifest" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$manifest"
  else
    rm -f "$tmp"
  fi
fi

echo '{}'
