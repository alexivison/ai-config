#!/usr/bin/env bash
# tmux-claude.sh — Codex's direct interface to Claude via tmux
# Replaces call_claude.sh
set -euo pipefail

MESSAGE="${1:?Usage: tmux-claude.sh \"message for Claude\"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"
discover_session

# Register Codex's thread ID with the party session (write-once)
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

CLAUDE_PANE=$(party_role_pane_target "$SESSION_NAME" "claude") || {
  echo "Error: Cannot resolve Claude pane in session '$SESSION_NAME'" >&2
  exit 1
}

# Detect completion messages by prefix-anchored patterns matching actual call sites.
# Mid-task traffic (questions, status) does not match and leaves status unchanged.
_is_completion=false
case "$MESSAGE" in
  "Review complete. Findings at: "*)       _is_completion=true ;;
  "Plan review complete. Findings at: "*)  _is_completion=true ;;
  "Task complete. Response at: "*)         _is_completion=true ;;
esac

# Send with exit-76 handling: keys sent but buffer check failed → treat as delivered
_send_rc=0
tmux_send "$CLAUDE_PANE" "[CODEX] $MESSAGE" "tmux-claude.sh" || _send_rc=$?

if [[ $_send_rc -eq 0 || $_send_rc -eq 76 ]]; then
  if [[ $_send_rc -eq 76 ]]; then
    echo "tmux_send: delivery unconfirmed (capture-pane miss)" >&2
  fi
  if $_is_completion; then
    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    _verdict=""
    _findings_file=""
    if [[ "$MESSAGE" =~ Findings\ at:\ ([^[:space:]]+) ]]; then
      _findings_file="${BASH_REMATCH[1]}"
    elif [[ "$MESSAGE" =~ Response\ at:\ ([^[:space:]]+) ]]; then
      _findings_file="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$_findings_file" && -f "$_findings_file" ]]; then
      if grep -q '^VERDICT: APPROVED' "$_findings_file" 2>/dev/null; then
        _verdict="APPROVE"
      elif grep -q '^VERDICT: REQUEST_CHANGES' "$_findings_file" 2>/dev/null; then
        _verdict="REQUEST_CHANGES"
      elif grep -q '^VERDICT: NEEDS_DISCUSSION' "$_findings_file" 2>/dev/null; then
        _verdict="NEEDS_DISCUSSION"
      fi
    fi
    write_codex_status "$RUNTIME_DIR" "idle" "" "" "$_verdict"
  fi
  echo "CLAUDE_MESSAGE_SENT"
else
  if $_is_completion; then
    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    write_codex_status "$RUNTIME_DIR" "error" "" "" "" "completion delivery failed: Claude pane busy"
  fi
  echo "CLAUDE_MESSAGE_DROPPED"
fi
