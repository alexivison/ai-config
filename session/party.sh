#!/usr/bin/env bash
# party.sh — Launch or resume a tmux session with Claude (Paladin) and Codex (Wizard)
# Usage: party.sh [--detached] [--prompt "text"] [--resume-claude ID] [--resume-codex ID] [TITLE]
#        party.sh --switch | --continue <party-id> | --stop [name] | --list | --install-tpm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/party-lib.sh"

party_usage() {
  cat <<'EOF'
Usage:
  party.sh [--detached] [--prompt "text"] [--resume-claude ID] [--resume-codex ID] [TITLE]
  party.sh --master [--detached] [--prompt "text"] [TITLE]
  party.sh --master-id <master-id> [--detached] [--prompt "text"] [TITLE]

  party.sh --promote [party-id]
  party.sh --switch
  party.sh --continue <party-id>
  party.sh continue <party-id>
  party.sh --stop [name]
  party.sh --list
  party.sh --install-tpm
EOF
}

party_install_tpm() {
  local tpm_path="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins/tpm}"
  local tpm_repo="${TPM_REPO:-https://github.com/tmux-plugins/tpm}"

  if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to install TPM." >&2
    return 1
  fi

  if [[ -d "$tpm_path/.git" ]]; then
    echo "TPM already installed at: $tpm_path"
    return 0
  fi

  if [[ -e "$tpm_path" ]]; then
    echo "Error: path exists but is not a TPM git clone: $tpm_path" >&2
    return 1
  fi

  mkdir -p "$(dirname "$tpm_path")"
  git clone "$tpm_repo" "$tpm_path" >/dev/null

  echo "TPM installed at: $tpm_path"
  echo "In tmux, press Prefix + I to install plugins."
}

party_window_name() {
  local title="${1:-}"
  if [[ -n "$title" ]]; then
    printf 'party (%s)\n' "$title"
  else
    printf 'work\n'
  fi
}

configure_party_theme() {
  local target="${1:?Usage: configure_party_theme SESSION_OR_WINDOW_TARGET}"

  # Role labels driven by @party_role metadata, with session ID suffix when available.
  # IDs appear after agents register (Claude on SessionStart, Codex on first message).
  # Use -w to set as window option so each window gets it independently.
  tmux set-option -w -t "$target" pane-border-status top
  tmux set-option -w -t "$target" pane-border-format \
    ' #{?#{==:#{@party_role},claude},The Paladin#{?#{CLAUDE_SESSION_ID}, (#{CLAUDE_SESSION_ID}),},#{?#{==:#{@party_role},codex},The Wizard#{?#{CODEX_THREAD_ID}, (#{CODEX_THREAD_ID}),},#{?#{==:#{@party_role},shell},Shell,#{?#{==:#{@party_role},tracker},Tracker,}}}} '
}

party_set_cleanup_hook() {
  local session="${1:?Usage: party_set_cleanup_hook SESSION_NAME}"
  tmux set-hook -t "$session" session-closed \
    "run-shell 'rm -rf /tmp/$session'"
}

party_launch_agents() {
  local session="${1:?Usage: party_launch_agents SESSION CWD CLAUDE_BIN CODEX_BIN AGENT_PATH [CLAUDE_RESUME_ID] [CODEX_RESUME_ID] [PROMPT]}"
  local session_cwd="${2:?Missing session_cwd}"
  local claude_bin="${3:?Missing claude_bin}"
  local codex_bin="${4:?Missing codex_bin}"
  local agent_path="${5:?Missing agent_path}"
  local claude_resume_id="${6:-}"
  local codex_resume_id="${7:-}"
  local prompt="${8:-}"
  local state_dir

  state_dir="$(ensure_party_state_dir "$session")"

  tmux set-environment -g -u CLAUDECODE 2>/dev/null || true
  tmux set-environment -t "$session" -u CLAUDECODE 2>/dev/null || true

  local q_agent_path q_claude_bin q_codex_bin
  local q_claude_resume_id q_codex_resume_id
  printf -v q_agent_path '%q' "$agent_path"
  printf -v q_claude_bin '%q' "$claude_bin"
  printf -v q_codex_bin '%q' "$codex_bin"

  local claude_cmd codex_cmd
  claude_cmd="export PATH=$q_agent_path; unset CLAUDECODE;"
  claude_cmd="$claude_cmd exec $q_claude_bin --dangerously-skip-permissions"
  if [[ -n "$claude_resume_id" ]]; then
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

  codex_cmd="export PATH=$q_agent_path; exec $q_codex_bin --dangerously-bypass-approvals-and-sandbox"
  if [[ -n "$codex_resume_id" ]]; then
    printf -v q_codex_resume_id '%q' "$codex_resume_id"
    codex_cmd="$codex_cmd resume $q_codex_resume_id"
    printf '%s\n' "$codex_resume_id" > "$state_dir/codex-thread-id"
    tmux set-environment -t "$session" CODEX_THREAD_ID "$codex_resume_id" 2>/dev/null || true
  fi

  # Pane 0: Codex (The Wizard)
  tmux respawn-pane -k -t "$session:0.0" -c "$session_cwd" "$codex_cmd"
  tmux set-option -p -t "$session:0.0" @party_role codex

  # Pane 1: Claude (The Paladin)
  tmux split-window -h -t "$session:0.0" -c "$session_cwd" "$claude_cmd"
  tmux set-option -p -t "$session:0.1" @party_role claude

  # Pane 2: Shell (operator terminal)
  tmux split-window -h -t "$session:0.1" -c "$session_cwd"
  tmux set-option -p -t "$session:0.2" @party_role shell

  tmux select-pane -t "$session:0.0" -T "The Wizard"
  tmux select-pane -t "$session:0.1" -T "The Paladin"
  tmux select-pane -t "$session:0.2" -T "Shell"
  configure_party_theme "$session"
  party_set_cleanup_hook "$session"
  tmux select-pane -t "$session:0.1"
}

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
    # Auto-discover current session
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

  # Find and replace the codex pane with the tracker
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

  # Update manifest
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

party_create_session() {
  local session="${1:?Usage: party_create_session SESSION WINDOW_NAME CWD}"
  local window_name="${2:?Missing window_name}"
  local session_cwd="${3:?Missing session_cwd}"

  # Unset TMUX to avoid nested-session errors when called from inside tmux
  TMUX= tmux new-session -d -s "$session" -n "$window_name" -c "$session_cwd"
}

party_start() {
  local title="${1:-}"
  local resume_claude="${2:-}"
  local resume_codex="${3:-}"
  local detached="${4:-0}"
  local prompt="${5:-}"
  local master_id="${6:-}"
  local session="party-$(date +%s)"
  local state_dir
  local session_cwd="$PWD"
  local window_name
  local claude_bin codex_bin agent_path

  while tmux has-session -t "$session" 2>/dev/null; do
    session="party-$(date +%s)-$RANDOM"
  done

  window_name="$(party_window_name "$title")"
  claude_bin="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
  codex_bin="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo "/opt/homebrew/bin/codex")}"
  agent_path="$HOME/.local/bin:/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

  party_prune_manifests
  state_dir="$(ensure_party_state_dir "$session")"
  party_state_upsert_manifest "$session" "$title" "$session_cwd" "$window_name" "$claude_bin" "$codex_bin" "$agent_path" || true
  party_state_set_field "$session" "last_started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true

  # Register as child of master if --master-id was provided
  if [[ -n "$master_id" ]]; then
    party_state_set_field "$session" "parent_session" "$master_id" || true
    party_state_add_worker "$master_id" "$session" 2>/dev/null || true
  fi

  party_create_session "$session" "$window_name" "$session_cwd"
  party_launch_agents "$session" "$session_cwd" "$claude_bin" "$codex_bin" "$agent_path" "$resume_claude" "$resume_codex" "$prompt"

  if [[ -n "$prompt" ]]; then
    party_state_set_field "$session" "initial_prompt" "$prompt" || true
  fi

  echo "Party session '$session' started."
  echo "State dir: $state_dir"
  echo "Manifest: $(party_state_file "$session")"
  if [[ "$detached" -eq 1 ]]; then
    echo "Party session '$session' launched detached."
  else
    party_attach "$session"
  fi
}

party_continue() {
  local session="${1:-}"
  if [[ -z "$session" ]]; then
    session="$(party_pick)" || return 1
  fi
  if [[ ! "$session" =~ ^party- ]]; then
    echo "Error: invalid session name '$session' (must start with party-)." >&2
    return 1
  fi

  if tmux has-session -t "$session" 2>/dev/null; then
    ensure_party_state_dir "$session" >/dev/null
    echo "Party session '$session' is already running. Re-attaching."
    party_attach "$session"
    return
  fi

  local manifest
  manifest="$(party_state_file "$session")"
  if [[ ! -f "$manifest" ]]; then
    echo "Error: No persisted party manifest for '$session' at $manifest" >&2
    echo "Start a new session with ./session/party.sh first." >&2
    return 1
  fi

  local session_cwd window_name
  local claude_bin codex_bin agent_path
  local title claude_resume_id codex_resume_id

  session_cwd="$(party_state_get_field "$session" "cwd" || true)"
  window_name="$(party_state_get_field "$session" "window_name" || true)"
  title="$(party_state_get_field "$session" "title" || true)"
  claude_bin="$(party_state_get_field "$session" "claude_bin" || true)"
  codex_bin="$(party_state_get_field "$session" "codex_bin" || true)"
  agent_path="$(party_state_get_field "$session" "agent_path" || true)"
  claude_resume_id="$(party_state_get_field "$session" "claude_session_id" || true)"
  codex_resume_id="$(party_state_get_field "$session" "codex_thread_id" || true)"

  [[ -n "$session_cwd" ]] || session_cwd="$PWD"
  if [[ ! -d "$session_cwd" ]]; then
    echo "Note: saved cwd '$session_cwd' no longer exists; using '$PWD'."
    session_cwd="$PWD"
  fi
  [[ -n "$window_name" ]] || window_name="$(party_window_name "$title")"
  [[ -n "$claude_bin" ]] || claude_bin="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
  [[ -n "$codex_bin" ]] || codex_bin="${CODEX_BIN:-$(command -v codex 2>/dev/null || echo "/opt/homebrew/bin/codex")}"
  [[ -n "$agent_path" ]] || agent_path="$HOME/.local/bin:/opt/homebrew/bin:${PATH:-/usr/bin:/bin}"

  ensure_party_state_dir "$session" >/dev/null
  party_create_session "$session" "$window_name" "$session_cwd"

  # Branch: master vs regular session
  local session_type
  session_type="$(party_state_get_field "$session" "session_type" 2>/dev/null || true)"

  if [[ "$session_type" == "master" ]]; then
    party_launch_master "$session" "$session_cwd" "$claude_bin" "$agent_path" "$claude_resume_id"
  else
    party_launch_agents "$session" "$session_cwd" "$claude_bin" "$codex_bin" "$agent_path" "$claude_resume_id" "$codex_resume_id"
  fi

  party_state_upsert_manifest "$session" "$title" "$session_cwd" "$window_name" "$claude_bin" "$codex_bin" "$agent_path" || true
  party_state_set_field "$session" "last_resumed_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || true

  # Re-register with parent master if this is a child worker
  local parent_session
  parent_session="$(party_state_get_field "$session" "parent_session" 2>/dev/null || true)"
  if [[ -n "$parent_session" ]]; then
    party_state_add_worker "$parent_session" "$session" 2>/dev/null || true
  fi

  echo "Party session '$session' resumed."
  echo "State dir: $(party_runtime_dir "$session")"
  echo "Manifest: $manifest"
  if [[ "$session_type" == "master" ]]; then
    echo "Master session resumed (no Codex pane)."
  else
    if [[ -z "$claude_resume_id" ]]; then
      echo "Note: Claude session id missing in manifest; launched fresh Claude session."
    fi
    if [[ -z "$codex_resume_id" ]]; then
      echo "Note: Codex session id missing in manifest; launched fresh Codex session."
    fi
  fi
  party_attach "$session"
}

# Deregister a session from its parent master (if any).
_party_deregister_from_parent() {
  local session="$1"
  local parent
  parent="$(party_state_get_field "$session" "parent_session" 2>/dev/null || true)"
  if [[ -n "$parent" ]]; then
    party_state_remove_worker "$parent" "$session" 2>/dev/null || true
  fi
}

party_delete() {
  local session="${1:?Usage: party_delete SESSION_NAME}"
  if [[ ! "$session" =~ ^party- ]]; then
    echo "Error: invalid session name '$session' (must start with party-)" >&2
    return 1
  fi
  _party_deregister_from_parent "$session"
  tmux kill-session -t "$session" 2>/dev/null || true
  rm -rf "/tmp/$session"
  rm -f "$(party_state_file "$session")"
  echo "Deleted: $session"
}

_party_short_path() {
  local p="${1:-}"
  if [[ "$p" == "$HOME"* ]]; then
    printf '~%s' "${p#"$HOME"}"
  else
    printf '%s' "$p"
  fi
}

_party_short_ts() {
  # 2026-03-03T00:28:08Z → 03/03
  local ts="${1:-}"
  [[ "$ts" == "-" || -z "$ts" ]] && { printf '-'; return; }
  printf '%s/%s' "${ts:5:2}" "${ts:8:2}"
}

party_pick_entries() {
  local active_only="${1:-0}"
  local live_sessions manifest_dir
  live_sessions=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' | sort -r || true)
  manifest_dir="$(party_state_root)"

  local current_session
  current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null || true)"

  if [[ -n "$live_sessions" ]]; then
    while IFS= read -r name; do
      local cwd title marker
      cwd="$(party_state_get_field "$name" "cwd" 2>/dev/null || true)"
      title="$(party_state_get_field "$name" "title" 2>/dev/null || true)"
      marker="active"
      [[ "$name" == "$current_session" ]] && marker="* current"
      printf '%s\t%s\t%s\t%s\n' "$name" "$marker" "${title:--}" "$(_party_short_path "${cwd:--}")"
    done <<< "$live_sessions"
  fi

  # Skip stale manifests in active-only mode
  if [[ "$active_only" -eq 1 ]]; then
    return
  fi

  if [[ -d "$manifest_dir" ]]; then
    local stale_files=()
    for f in "$manifest_dir"/party-*.json; do
      [[ -f "$f" ]] || continue
      local sid
      sid="$(basename "$f" .json)"
      if [[ -n "$live_sessions" ]] && grep -qxF "$sid" <<< "$live_sessions"; then
        continue
      fi
      stale_files+=("$f")
    done

    if [[ ${#stale_files[@]} -gt 0 ]]; then
      # Separator between active and resumable sections
      [[ -n "$live_sessions" ]] && printf '\033[38;2;99;110;123m── resumable ──────────────────────────────\033[0m\n'
      while IFS= read -r f; do
        local sid cwd title ts
        sid="$(basename "$f" .json)"
        cwd="$(jq -r '.cwd // "-"' "$f" 2>/dev/null || echo "-")"
        title="$(jq -r '.title // empty' "$f" 2>/dev/null || true)"
        ts="$(jq -r '.last_started_at // .created_at // "-"' "$f" 2>/dev/null || echo "-")"
        printf '%s\t%s\t%s\t%s\n' "$sid" "$(_party_short_ts "$ts")" "${title:--}" "$(_party_short_path "$cwd")"
      done < <(printf '%s\0' "${stale_files[@]}" | xargs -0 ls -t)
    fi
  fi
}

# Shared fzf picker. Args: entries, header, [extra_fzf_args...]
_party_fzf_select() {
  local entries="$1"
  local header="$2"
  shift 2

  local manifest_root preview_script
  manifest_root="$(party_state_root)"
  preview_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/party-preview.sh"

  printf '%s\n' "$entries" | column -t -s $'\t' | fzf \
    --ansi \
    --header="$header" \
    --no-info \
    --reverse \
    --preview="bash \"$preview_script\" \$(echo {1} | cut -d\" \" -f1) \"$manifest_root\" \"$HOME\"" \
    --preview-window=right:40% \
    "$@"
}

party_pick() {
  if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is required for interactive picker. Install with: brew install fzf" >&2
    return 1
  fi

  local entries
  entries="$(party_pick_entries)"
  if [[ -z "$entries" ]]; then
    echo "No party sessions found." >&2
    return 1
  fi

  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/party.sh"

  local selected
  selected="$(_party_fzf_select "$entries" "enter:resume  ctrl-d:delete  esc:cancel" \
    --bind="ctrl-d:execute(echo {} | grep -qv 'current' && echo {} | awk '{print \$1}' | xargs -I{} bash \"$script_path\" --delete {} || true)+reload(bash \"$script_path\" --pick-entries)" \
  )" || return 1

  echo "$selected" | awk '{print $1}'
}

party_switch() {
  if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is required for interactive picker. Install with: brew install fzf" >&2
    return 1
  fi

  local entries
  entries="$(party_pick_entries)"
  if [[ -z "$entries" ]]; then
    echo "No party sessions found."
    [[ -t 0 ]] && read -r -s -n 1
    return 1
  fi

  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/party.sh"

  local selected
  selected="$(_party_fzf_select "$entries" "enter:switch/resume  ctrl-d:delete  esc:cancel" \
    --bind="ctrl-d:execute(echo {} | grep -qv 'current' && echo {} | awk '{print \$1}' | xargs -I{} bash \"$script_path\" --delete {} || true)+reload(bash \"$script_path\" --pick-entries)" \
  )" || return 1

  local target
  target="$(echo "$selected" | awk '{print $1}')"

  # Ignore separator line selection
  [[ "$target" =~ ^party- ]] || return 0

  if tmux has-session -t "$target" 2>/dev/null; then
    party_attach "$target"
  else
    party_continue "$target"
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
    _party_deregister_from_parent "$target"
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
    _party_deregister_from_parent "$name"
    tmux kill-session -t "$name" 2>/dev/null || true
    rm -rf "/tmp/$name"
    echo "Stopped: $name"
  done <<< "$sessions"
}

party_prune_manifests() {
  local max_age_days="${PARTY_PRUNE_DAYS:-7}"
  local manifest_dir
  manifest_dir="$(party_state_root)"
  [[ -d "$manifest_dir" ]] || return 0

  # Delete manifests older than max_age_days, skip any with a live tmux session
  local live_sessions
  live_sessions=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' || true)

  local pruned=0
  while IFS= read -r -d '' f; do
    local sid
    sid="$(basename "$f" .json)"
    if [[ -n "$live_sessions" ]] && grep -qxF "$sid" <<< "$live_sessions"; then
      continue
    fi
    rm -f "$f" && pruned=$((pruned + 1))
  done < <(find "$manifest_dir" -name 'party-*.json' -mtime +"$max_age_days" -print0 2>/dev/null)
  if [[ $pruned -gt 0 ]]; then
    echo "Pruned $pruned party manifest(s) older than $max_age_days days."
  fi
}

party_list() {
  local live_sessions manifest_dir stale=()
  live_sessions=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' || true)
  manifest_dir="$(party_state_root)"

  # Show live tmux sessions
  if [[ -n "$live_sessions" ]]; then
    echo "Active:"
    while IFS= read -r name; do
      local cwd title
      cwd="$(party_state_get_field "$name" "cwd" 2>/dev/null || true)"
      title="$(party_state_get_field "$name" "title" 2>/dev/null || true)"
      printf '  %s  %s  %s\n' "$name" "${title:+($title)}" "${cwd:-}"
    done <<< "$live_sessions"
  fi

  # Show resumable manifests (not currently live)
  if [[ -d "$manifest_dir" ]]; then
    for f in "$manifest_dir"/party-*.json; do
      [[ -f "$f" ]] || continue
      local sid
      sid="$(basename "$f" .json)"
      if [[ -n "$live_sessions" ]] && grep -qxF "$sid" <<< "$live_sessions"; then
        continue
      fi
      stale+=("$f")
    done

    if [[ ${#stale[@]} -gt 0 ]]; then
      echo "Resumable (--continue <id>):"
      # Sort by modification time, newest first; show last 10
      printf '%s\0' "${stale[@]}" | xargs -0 ls -t | head -10 | while IFS= read -r f; do
        local sid cwd title ts
        sid="$(basename "$f" .json)"
        cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null || true)"
        title="$(jq -r '.title // empty' "$f" 2>/dev/null || true)"
        ts="$(jq -r '.last_started_at // .created_at // empty' "$f" 2>/dev/null || true)"
        printf '  %s  %s  %s  %s\n' "$sid" "${ts:+[$ts]}" "${title:+($title)}" "${cwd:-}"
      done
    fi
  fi

  if [[ -z "$live_sessions" && ${#stale[@]} -eq 0 ]]; then
    echo "No party sessions found."
  fi
}

# Parse arguments
_party_resume_claude=""
_party_resume_codex=""
_party_title=""
_party_detached=0
_party_prompt=""
_party_master=0
_party_master_id=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-tpm) party_install_tpm; exit ;;
    --stop)  party_stop "${2:-}"; exit ;;
    --list)  party_list; exit ;;
    --continue|continue) party_continue "${2:-}"; exit ;;
    --promote) party_promote "${2:-}"; exit ;;
    --delete) party_delete "${2:?--delete requires a session ID}"; exit ;;
    --switch|switch) party_switch; exit ;;
    --pick-entries) party_pick_entries; exit ;;
    --help|-h) party_usage; exit ;;
    --detached) _party_detached=1; shift ;;
    --prompt) _party_prompt="${2:?--prompt requires a message}"; shift 2 ;;
    --resume-claude) _party_resume_claude="${2:?--resume-claude requires a session ID}"; shift 2 ;;
    --resume-codex)  _party_resume_codex="${2:?--resume-codex requires a session ID}"; shift 2 ;;
    --master) _party_master=1; shift ;;
    --master-id) _party_master_id="${2:?--master-id requires a session ID}"; shift 2 ;;

    --)      shift; break ;;
    --*)     party_usage >&2; exit 1 ;;
    *)       _party_title="$1"; shift ;;
  esac
done

if [[ "$_party_master" -eq 1 ]]; then
  party_start_master "$_party_title" "$_party_resume_claude" "$_party_detached" "$_party_prompt"
elif [[ -n "$_party_master_id" ]]; then
  party_start "$_party_title" "$_party_resume_claude" "$_party_resume_codex" "$_party_detached" "$_party_prompt" "$_party_master_id"
else
  party_start "$_party_title" "$_party_resume_claude" "$_party_resume_codex" "$_party_detached" "$_party_prompt"
fi
