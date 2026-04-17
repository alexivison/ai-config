#!/usr/bin/env bash
# Notify sketchybar of Claude's primary-agent lifecycle events.
# Triggered: PreToolUse, Stop, PermissionRequest, SessionEnd
# The tracker TUI derives activity from pane-title churn, not this hook —
# this remains only to drive external indicators (sketchybar widget).
set -e

hook_input=$(cat)

event=$(echo "$hook_input" | jq -r '.hook_event_name // empty' 2>/dev/null)
if [[ -z "$event" ]]; then
  echo '{}'
  exit 0
fi

case "$event" in
  PreToolUse)        STATE="active"  ;;
  PermissionRequest) STATE="waiting" ;;
  Stop)              STATE="idle"    ;;
  SessionEnd)        STATE="done"    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../session/party-lib.sh"
if [[ -f "$LIB" ]]; then
  source "$LIB"
  discover_session 2>/dev/null || SESSION_NAME=""
fi

sketchybar --trigger party_state STATE="$STATE" SESSION="${SESSION_NAME:-}" 2>/dev/null || true

echo '{}'
