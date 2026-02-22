#!/usr/bin/env bash
# party-lib.sh — Shared helpers for party session discovery
# Sourced by party.sh, tmux-codex.sh, and tmux-claude.sh

# Discovers the party session this script is running inside.
# Uses $TMUX env var to self-discover — no global pointer file needed.
# Sets SESSION_NAME and STATE_DIR. Returns 1 if not inside a party session.
discover_session() {
  local name

  # PARTY_SESSION override for testing (scripts run outside tmux)
  if [[ -n "${PARTY_SESSION:-}" ]]; then
    name="$PARTY_SESSION"
  elif [[ -n "${TMUX:-}" ]]; then
    name=$(tmux display-message -p '#{session_name}' 2>/dev/null)
  else
    echo "Error: Not inside a tmux session" >&2
    return 1
  fi

  if [[ ! "$name" =~ ^party- ]]; then
    echo "Error: Current tmux session '$name' is not a party session" >&2
    return 1
  fi

  local state_dir="/tmp/$name"
  if [[ ! -d "$state_dir" || ! -f "$state_dir/session-name" ]]; then
    echo "Error: State directory missing for session '$name'" >&2
    return 1
  fi

  SESSION_NAME="$name"
  STATE_DIR="$state_dir"
}

# Sends text to a tmux pane running a TUI agent (Claude Code / Codex CLI).
# Uses -l flag + delay + separate Enter to avoid paste-mode newline issue.
tmux_send() {
  local target="$1"
  local text="$2"
  tmux send-keys -t "$target" -l "$text"
  sleep 0.1
  tmux send-keys -t "$target" Enter
}
