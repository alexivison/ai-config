#!/usr/bin/env bash
# tmux-primary.sh — Shared transport for sending messages to the primary agent via tmux
set -euo pipefail

MESSAGE="${1:?Usage: tmux-primary.sh \"message for the primary agent\"}"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"
discover_session

current_role() {
  if [[ -n "${TMUX_PANE:-}" ]]; then
    tmux display-message -t "$TMUX_PANE" -p '#{@party_role}' 2>/dev/null || true
  fi
}

augment_primary_request() {
  local message="$1"
  local response_path=""
  if [[ "$message" =~ Write\ response\ to:\ ([^[:space:]]+) ]]; then
    response_path="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$response_path" || "$message" == *"When done, run:"* ]]; then
    printf '%s\n' "$message"
    return
  fi

  local notify_script="$HOME/.codex/skills/agent-transport/scripts/tmux-primary.sh"
  local handoff_instruction
  handoff_instruction="$(party_transport_response_handoff_instruction "$notify_script" "$response_path")"
  printf '%s — %s\n' "$message" "$handoff_instruction"
}

# Register the default companion thread ID with the party session (write-once).
if [[ -n "${CODEX_THREAD_ID:-}" && ! -s "$STATE_DIR/codex-thread-id" ]]; then
  printf '%s\n' "$CODEX_THREAD_ID" > "$STATE_DIR/codex-thread-id"
  tmux set-environment -t "$SESSION_NAME" CODEX_THREAD_ID "$CODEX_THREAD_ID" 2>/dev/null || true

  # Persist to manifest for resume path (continue.go reads codex_thread_id)
  manifest="$(party_state_file "$SESSION_NAME")"
  if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"
    if jq --arg v "$CODEX_THREAD_ID" '.codex_thread_id = $v' "$manifest" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$manifest"
    else
      rm -f "$tmp"
    fi
  fi
fi

sender_role="companion"
target_role="primary"
case "$(current_role)" in
  primary|claude)
    sender_role="primary"
    target_role="companion"
    ;;
  companion|codex)
    sender_role="companion"
    target_role="primary"
    ;;
esac

PEER_PANE=$(party_role_pane_target "$SESSION_NAME" "$target_role") || {
  echo "Error: Cannot resolve $target_role pane in session '$SESSION_NAME'" >&2
  exit 1
}
SENDER_PREFIX=$(party_role_message_prefix "$SESSION_NAME" "$sender_role")

# Detect completion messages by prefix-anchored patterns matching actual call sites.
# Mid-task traffic (questions, status) does not match and leaves status unchanged.
_is_completion=false
if party_transport_is_completion_message "$MESSAGE"; then
  _is_completion=true
fi

if [[ "$sender_role" == "primary" ]]; then
  MESSAGE="$(augment_primary_request "$MESSAGE")"
fi

# Send with exit-76 handling: keys sent but buffer check failed → treat as delivered
_send_rc=0
tmux_send "$PEER_PANE" "$SENDER_PREFIX $MESSAGE" "tmux-primary.sh" || _send_rc=$?

if [[ $_send_rc -eq 0 || $_send_rc -eq 76 ]]; then
  if [[ $_send_rc -eq 76 ]]; then
    echo "tmux_send: delivery unconfirmed (capture-pane miss)" >&2
  fi
  if $_is_completion && [[ "$sender_role" == "companion" ]]; then
    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    _verdict=""
    _findings_file="$(party_transport_completion_path "$MESSAGE" 2>/dev/null || true)"
    if [[ -n "$_findings_file" && -f "$_findings_file" ]]; then
      if grep -q '^VERDICT: APPROVED' "$_findings_file" 2>/dev/null; then
        _verdict="APPROVE"
      elif grep -q '^VERDICT: REQUEST_CHANGES' "$_findings_file" 2>/dev/null; then
        _verdict="REQUEST_CHANGES"
      elif grep -q '^VERDICT: NEEDS_DISCUSSION' "$_findings_file" 2>/dev/null; then
        _verdict="NEEDS_DISCUSSION"
      fi
    fi
    write_companion_status "$RUNTIME_DIR" "idle" "" "" "$_verdict"
  fi
  echo "PRIMARY_MESSAGE_SENT"
else
  if $_is_completion && [[ "$sender_role" == "companion" ]]; then
    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    write_companion_status "$RUNTIME_DIR" "error" "" "" "" "completion delivery failed: primary pane busy"
  fi
  echo "PRIMARY_MESSAGE_DROPPED"
fi
