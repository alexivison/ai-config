#!/usr/bin/env bash
# party.sh — Launch a tmux session with Claude (Paladin) and Codex (Wizard)
# Usage: party.sh [--raw|--stop [name]|--list]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/party-lib.sh"

configure_keybindings() {
  local session="${1:?Usage: configure_keybindings SESSION_NAME}"

  # Pane navigation (global — tmux doesn't support session-scoped bindings)
  # Harmless in -CC mode (iTerm2 handles its own keybindings)
  tmux bind-key -n M-Left  select-pane -L
  tmux bind-key -n M-Right select-pane -R
  tmux bind-key Left  select-pane -L
  tmux bind-key Right select-pane -R

  # Window/tab management
  tmux bind-key t new-window
  tmux bind-key w kill-pane
  tmux bind-key -n M-1 select-window -t 0
  tmux bind-key -n M-2 select-window -t 1
  tmux bind-key f resize-pane -Z
  tmux bind-key Q kill-session           # Prefix + Q → kill entire session

  # Pane theming (raw tmux mode only — invisible in -CC / iTerm2 control mode)
  tmux set-option -t "$session" pane-border-status top
  tmux set-option -t "$session" pane-border-format \
    ' #{?#{==:#{pane_title},The Wizard},#[fg=colour141 bold],#[fg=colour220 bold]}#{pane_title}#[default] '
  tmux set-option -t "$session" pane-border-style "fg=colour240"
  tmux set-option -t "$session" pane-active-border-style "fg=colour220"

  # Swap active border color on pane focus
  tmux set-hook -t "$session" pane-focus-in "if-shell \
    'test \"#{pane_title}\" = \"The Paladin\"' \
    'set pane-active-border-style fg=colour220' \
    'set pane-active-border-style fg=colour141'"

  # Status bar
  tmux set-option -t "$session" status-style "bg=colour235,fg=colour248"
  tmux set-option -t "$session" status-left "#[fg=colour141,bold] party #[default] "
  tmux set-option -t "$session" status-right ""
}

party_start() {
  local session="party-$(date +%s)"
  local state_dir="/tmp/$session"

  mkdir -p "$state_dir"
  echo "$session" > "$state_dir/session-name"

  # Detect iTerm2 for control mode
  local use_cc=false
  if [[ "${TERM_PROGRAM:-}" == "iTerm.app" && "${PARTY_RAW:-}" != "1" ]]; then
    use_cc=true
  fi

  # Create detached session — launch agents via login shell for PATH.
  tmux new-session -d -s "$session" -n work

  # Purge CLAUDECODE from tmux environment at every level.
  # The tmux server inherits this if it was started from a Claude Code session.
  # Global unset needed because session-level unset alone doesn't affect pane
  # processes — they inherit from the server's global environment.
  tmux set-environment -g -u CLAUDECODE 2>/dev/null || true
  tmux set-environment -t "$session" -u CLAUDECODE 2>/dev/null || true

  # Launch agents with full paths and explicit PATH.
  # Tmux panes use non-interactive shells which don't source .zshrc.
  local claude_bin="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
  local codex_bin="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo "/opt/homebrew/bin/codex")}"
  local agent_path="$HOME/.local/bin:/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

  tmux respawn-pane -k -t "$session:work.0" \
    "export PATH='$agent_path'; unset CLAUDECODE; exec '$claude_bin' --dangerously-skip-permissions"
  tmux split-window -h -t "$session:work" \
    "export PATH='$agent_path'; exec '$codex_bin' --full-auto --sandbox read-only"

  # Label panes and prevent agents from overriding titles
  tmux select-pane -t "$session:work.0" -T "The Paladin"
  tmux select-pane -t "$session:work.1" -T "The Wizard"
  tmux set-option -t "$session" allow-rename off

  configure_keybindings "$session"

  # Focus Claude pane
  tmux select-pane -t "$session:work.0"

  echo "Party session '$session' started."
  echo "State dir: $state_dir"

  # Attach
  if [[ "$use_cc" == true ]]; then
    exec tmux -CC attach -t "$session"
  else
    exec tmux attach -t "$session"
  fi
}

party_stop() {
  local target="${1:-}"

  if [[ -n "$target" ]]; then
    # Validate prefix to prevent path traversal (rm -rf "/tmp/$target")
    if [[ ! "$target" =~ ^party- ]]; then
      echo "Error: invalid session name '$target' (must start with party-)" >&2
      return 1
    fi
    tmux kill-session -t "$target" 2>/dev/null || true
    rm -rf "/tmp/$target"
    echo "Party session '$target' stopped."
    return 0
  fi

  # Stop all party sessions
  local sessions
  sessions=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' || true)

  if [[ -z "$sessions" ]]; then
    echo "No active party sessions."
    return 0
  fi

  while IFS= read -r name; do
    tmux kill-session -t "$name" 2>/dev/null || true
    rm -rf "/tmp/$name"
    echo "Stopped: $name"
  done <<< "$sessions"
}

party_list() {
  local sessions
  sessions=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' || true)

  if [[ -z "$sessions" ]]; then
    echo "No active party sessions."
    return 0
  fi

  echo "Active party sessions:"
  while IFS= read -r name; do
    echo "  $name"
  done <<< "$sessions"
}

case "${1:-}" in
  --stop) party_stop "${2:-}" ;;
  --list) party_list ;;
  --raw)  PARTY_RAW=1 party_start ;;
  "")     party_start ;;
  *)      echo "Usage: party.sh [--raw|--stop [name]|--list]" >&2; exit 1 ;;
esac
