#!/usr/bin/env bash
# Detect the primary agent's activity state from hook lifecycle events.
# Triggered: PreToolUse, Stop, PermissionRequest, SessionEnd
# Writes to: $STATE_DIR/claude-state.json + tmux @party_state + sketchybar
set -e

hook_input=$(cat)

event=$(echo "$hook_input" | jq -r '.hook_event_name // empty' 2>/dev/null)
if [[ -z "$event" ]]; then
  echo '{}'
  exit 0
fi

# Map event to state
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
if [[ ! -f "$LIB" ]]; then
  echo '{}'
  exit 0
fi
source "$LIB"

if ! discover_session 2>/dev/null; then
  echo '{}'
  exit 0
fi

# 1. Atomic write to claude-state.json (artifact name stays stable in v1)
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp_file="$STATE_DIR/claude-state.json.tmp"
printf '{"state":"%s","updated_at":"%s"}\n' "$STATE" "$now" > "$tmp_file"
mv "$tmp_file" "$STATE_DIR/claude-state.json"

# 2. Set tmux pane option (skip in test/mock mode)
if [[ -z "${MOCK_TMUX:-}" ]]; then
  PANE_TARGET=$(party_role_pane_target "$SESSION_NAME" "claude" 2>/dev/null) || true
  if [[ -n "$PANE_TARGET" ]]; then
    tmux set-option -p -t "$PANE_TARGET" @party_state "$STATE" 2>/dev/null || true
  fi
fi

# 3. Notify sketchybar
sketchybar --trigger party_state STATE="$STATE" SESSION="$SESSION_NAME" 2>/dev/null || true

echo '{}'
