#!/usr/bin/env bash
# party-master.sh — Master session launch, promote, and lifecycle.
# Sourced by party.sh. Requires party-lib.sh already loaded.

party_launch_master() {
  local session="${1:?Usage: party_launch_master SESSION CWD CLAUDE_BIN AGENT_PATH [CLAUDE_RESUME_ID] [PROMPT]}"
  local session_cwd="${2:?Missing session_cwd}"
  local claude_bin="${3:?Missing claude_bin}"
  local agent_path="${4:?Missing agent_path}"
  local claude_resume_id="${5:-}"
  local prompt="${6:-}"
  local state_dir

  state_dir="$(ensure_party_state_dir "$session")"

  tmux set-environment -g -u CLAUDECODE 2>/dev/null || true
  tmux set-environment -t "$session" -u CLAUDECODE 2>/dev/null || true

  local q_agent_path q_claude_bin
  printf -v q_agent_path '%q' "$agent_path"
  printf -v q_claude_bin '%q' "$claude_bin"

  local claude_cmd
  claude_cmd="export PATH=$q_agent_path; unset CLAUDECODE;"
  claude_cmd="$claude_cmd exec $q_claude_bin --dangerously-skip-permissions"
  if [[ -n "$claude_resume_id" ]]; then
    local q_claude_resume_id
    printf -v q_claude_resume_id '%q' "$claude_resume_id"
    claude_cmd="$claude_cmd --resume $q_claude_resume_id"
    printf '%s\n' "$claude_resume_id" > "$state_dir/claude-session-id"
    tmux set-environment -t "$session" CLAUDE_SESSION_ID "$claude_resume_id" 2>/dev/null || true
  fi

  if [[ -n "$prompt" ]]; then
    local q_prompt
    printf -v q_prompt '%q' "$prompt"
    claude_cmd="$claude_cmd -- $q_prompt"
  fi

  # Resolve tracker binary: PATH first, then repo-local build
  local tracker_bin
  tracker_bin="$(command -v party-tracker 2>/dev/null || true)"
  if [[ -z "$tracker_bin" ]]; then
    local repo_tracker="$SCRIPT_DIR/../tools/party-tracker/party-tracker"
    if [[ -x "$repo_tracker" ]]; then
      tracker_bin="$repo_tracker"
    else
      echo "Warning: party-tracker binary not found. Run 'go build' in tools/party-tracker/." >&2
      tracker_bin="echo 'party-tracker not installed'; read"
    fi
  fi

  # Pane 0: Tracker (set PARTY_REPO_ROOT so tracker finds scripts post-install)
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
  tmux respawn-pane -k -t "$session:0.0" -c "$session_cwd" "PARTY_REPO_ROOT=$repo_root $tracker_bin $session"
  tmux set-option -p -t "$session:0.0" @party_role tracker

  # Pane 1: Claude (The Paladin — orchestrator)
  tmux split-window -h -t "$session:0.0" -c "$session_cwd" "$claude_cmd"
  tmux set-option -p -t "$session:0.1" @party_role claude

  # Pane 2: Shell (operator terminal)
  tmux split-window -h -t "$session:0.1" -c "$session_cwd"
  tmux set-option -p -t "$session:0.2" @party_role shell

  tmux select-pane -t "$session:0.0" -T "Tracker"
  tmux select-pane -t "$session:0.1" -T "The Paladin"
  tmux select-pane -t "$session:0.2" -T "Shell"
  configure_party_theme "$session:0"
  party_set_cleanup_hook "$session"
  tmux select-pane -t "$session:0.1"
}

party_promote() {
  local session="${1:-}"

  if [[ -z "$session" ]]; then
    if [[ -n "${TMUX:-}" ]]; then
      session="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
    else
      echo "Error: --promote requires a session name or must be run inside tmux." >&2
      return 1
    fi
  fi

  if [[ ! "$session" =~ ^party- ]]; then
    echo "Error: '$session' is not a party session." >&2
    return 1
  fi

  if party_is_master "$session" 2>/dev/null; then
    echo "Session '$session' is already a master session." >&2
    return 0
  fi

  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "Error: session '$session' is not running." >&2
    return 1
  fi

  # Resolve tracker binary
  local tracker_bin
  tracker_bin="$(command -v party-tracker 2>/dev/null || true)"
  if [[ -z "$tracker_bin" ]]; then
    local repo_tracker="$SCRIPT_DIR/../tools/party-tracker/party-tracker"
    if [[ -x "$repo_tracker" ]]; then
      tracker_bin="$repo_tracker"
    else
      echo "Error: party-tracker binary not found. Run 'go build' in tools/party-tracker/." >&2
      return 1
    fi
  fi

  local codex_pane
  codex_pane="$(party_role_pane_target "$session" "codex" 2>/dev/null)" || {
    echo "Error: cannot find Codex pane to replace." >&2
    return 1
  }

  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  tmux respawn-pane -k -t "$codex_pane" "PARTY_REPO_ROOT=$repo_root $tracker_bin $session"
  tmux set-option -p -t "$codex_pane" @party_role tracker
  tmux select-pane -t "$codex_pane" -T "Tracker"

  party_state_set_field "$session" "session_type" "master" || true

  echo "Session '$session' promoted to master."
}

party_start_master() {
  local title="${1:-}"
  local resume_claude="${2:-}"
  local detached="${3:-0}"
  local prompt="${4:-}"
  local session="party-$(date +%s)"
  local state_dir
  local session_cwd="$PWD"
  local window_name
  local claude_bin agent_path

  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required for master party mode." >&2
    return 1
  fi

  while tmux has-session -t "$session" 2>/dev/null; do
    session="party-$(date +%s)-$RANDOM"
  done

  window_name="$(party_window_name "$title")"
  claude_bin="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
  agent_path="$HOME/.local/bin:/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

  party_prune_manifests
  state_dir="$(ensure_party_state_dir "$session")"
  party_state_upsert_manifest "$session" "$title" "$session_cwd" "$window_name" "$claude_bin" "" "$agent_path" || true
  party_state_set_field "$session" "session_type" "master" || true
  party_state_set_field "$session" "last_started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true

  party_create_session "$session" "$window_name" "$session_cwd"
  party_launch_master "$session" "$session_cwd" "$claude_bin" "$agent_path" "$resume_claude" "$prompt"

  if [[ -n "$prompt" ]]; then
    party_state_set_field "$session" "initial_prompt" "$prompt" || true
  fi

  echo "Master session '$session' started."
  echo "State dir: $state_dir"
  echo "Manifest: $(party_state_file "$session")"
  if [[ "$detached" -eq 1 ]]; then
    echo "Master session '$session' launched detached."
  else
    party_attach "$session"
  fi
}
