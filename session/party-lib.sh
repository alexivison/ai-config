#!/usr/bin/env bash
# party-lib.sh — Shared helpers for party session discovery
# Sourced by party.sh, tmux-codex.sh, and tmux-claude.sh

party_state_root() {
  printf '%s\n' "${PARTY_STATE_ROOT:-$HOME/.party-state}"
}

party_state_file() {
  local session="${1:?Usage: party_state_file SESSION_NAME}"
  printf '%s/%s.json\n' "$(party_state_root)" "$session"
}

party_runtime_dir() {
  local session="${1:?Usage: party_runtime_dir SESSION_NAME}"
  printf '/tmp/%s\n' "$session"
}

ensure_party_state_dir() {
  local session="${1:?Usage: ensure_party_state_dir SESSION_NAME}"
  local state_dir
  state_dir="$(party_runtime_dir "$session")"

  mkdir -p "$state_dir"
  printf '%s\n' "$session" > "$state_dir/session-name"
  printf '%s\n' "$state_dir"
}

# Attach or switch to a party session. Uses switch-client inside tmux,
# exec attach outside tmux.
party_attach() {
  local session="${1:?Usage: party_attach SESSION_NAME}"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$session"
  else
    exec tmux attach -t "$session"
  fi
}

# ---------------------------------------------------------------------------
# Portable file locking (used by all manifest write operations)
# ---------------------------------------------------------------------------

# Acquire a lock via atomic mkdir. Returns 0 on success, 1 on timeout (~10s).
_party_lock() {
  local lockdir="$1"
  local max_attempts=100  # 100 × 0.1s = 10s timeout
  local attempts=0

  while ! mkdir "$lockdir" 2>/dev/null; do
    if [[ $attempts -ge $max_attempts ]]; then
      return 1
    fi
    sleep 0.1
    attempts=$((attempts + 1))
  done
  return 0
}

_party_unlock() {
  local lockdir="$1"
  rmdir "$lockdir" 2>/dev/null || true
}

# Persist launch metadata for a party session. JSON persistence is best-effort:
# if jq is unavailable, runtime behavior still works, but resume metadata is skipped.
party_state_upsert_manifest() {
  local session="${1:?Usage: party_state_upsert_manifest SESSION TITLE CWD WINDOW CLAUDE_BIN CODEX_BIN AGENT_PATH}"
  local title="${2:-}"
  local cwd="${3:?Missing cwd}"
  local window_name="${4:?Missing window_name}"
  local claude_bin="${5:?Missing claude_bin}"
  local codex_bin="${6:?Missing codex_bin}"
  local agent_path="${7:?Missing agent_path}"

  command -v jq >/dev/null 2>&1 || return 0

  local root file tmp now
  root="$(party_state_root)"
  file="$(party_state_file "$session")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$root"
  local lockdir="${file}.lock"
  local tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"

  _party_lock "$lockdir" || { rm -f "$tmp"; return 1; }

  if [[ -f "$file" ]]; then
    jq --arg session "$session" \
      --arg title "$title" \
      --arg cwd "$cwd" \
      --arg window "$window_name" \
      --arg claude "$claude_bin" \
      --arg codex "$codex_bin" \
      --arg path "$agent_path" \
      --arg now "$now" \
      '
      .party_id = (.party_id // $session)
      | .created_at = (.created_at // $now)
      | .updated_at = $now
      | .title = $title
      | .cwd = $cwd
      | .window_name = $window
      | .claude_bin = $claude
      | .codex_bin = $codex
      | .agent_path = $path
      ' "$file" > "$tmp" || {
      rm -f "$tmp"
      _party_unlock "$lockdir"
      return 1
    }
  else
    jq -n \
      --arg session "$session" \
      --arg title "$title" \
      --arg cwd "$cwd" \
      --arg window "$window_name" \
      --arg claude "$claude_bin" \
      --arg codex "$codex_bin" \
      --arg path "$agent_path" \
      --arg now "$now" \
      '
      {
        party_id: $session,
        created_at: $now,
        updated_at: $now,
        title: $title,
        cwd: $cwd,
        window_name: $window,
        claude_bin: $claude,
        codex_bin: $codex,
        agent_path: $path
      }
      ' > "$tmp" || {
      rm -f "$tmp"
      _party_unlock "$lockdir"
      return 1
    }
  fi

  mv "$tmp" "$file"
  _party_unlock "$lockdir"
}

party_state_set_field() {
  local session="${1:?Usage: party_state_set_field SESSION KEY VALUE}"
  local key="${2:?Missing key}"
  local value="${3:-}"

  command -v jq >/dev/null 2>&1 || return 0

  local root file tmp now
  root="$(party_state_root)"
  file="$(party_state_file "$session")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$root"
  local lockdir="${file}.lock"
  local tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"

  _party_lock "$lockdir" || { rm -f "$tmp"; return 1; }

  if [[ -f "$file" ]]; then
    jq --arg session "$session" \
      --arg key "$key" \
      --arg value "$value" \
      --arg now "$now" \
      '
      .party_id = (.party_id // $session)
      | .created_at = (.created_at // $now)
      | .updated_at = $now
      | .[$key] = $value
      ' "$file" > "$tmp" || {
      rm -f "$tmp"
      _party_unlock "$lockdir"
      return 1
    }
  else
    jq -n \
      --arg session "$session" \
      --arg key "$key" \
      --arg value "$value" \
      --arg now "$now" \
      '
      {
        party_id: $session,
        created_at: $now,
        updated_at: $now
      }
      | .[$key] = $value
      ' > "$tmp" || {
      rm -f "$tmp"
      _party_unlock "$lockdir"
      return 1
    }
  fi

  mv "$tmp" "$file"
  _party_unlock "$lockdir"
}

party_state_get_field() {
  local session="${1:?Usage: party_state_get_field SESSION KEY}"
  local key="${2:?Missing key}"
  local file

  file="$(party_state_file "$session")"
  [[ -f "$file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  jq -r --arg key "$key" '.[$key] // empty' "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Master mode helpers
# ---------------------------------------------------------------------------

# Returns 0 if the session is a master session (session_type == "master").
party_is_master() {
  local session="${1:?Usage: party_is_master SESSION}"
  local st
  st="$(party_state_get_field "$session" "session_type" 2>/dev/null || true)"
  [[ "$st" == "master" ]]
}

# Add a worker to a master's workers array. Deduplicates. Locked.
party_state_add_worker() {
  local master="${1:?Usage: party_state_add_worker MASTER WORKER}"
  local worker="${2:?Missing worker}"
  local file lockdir tmp

  file="$(party_state_file "$master")"
  [[ -f "$file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  lockdir="${file}.lock"
  tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"

  _party_lock "$lockdir" || {
    rm -f "$tmp"
    return 1
  }

  jq --arg w "$worker" '.workers = ((.workers // []) + [$w] | unique)' "$file" > "$tmp" && mv "$tmp" "$file"
  local rc=$?

  _party_unlock "$lockdir"
  return $rc
}

# Remove a worker from a master's workers array. Locked.
party_state_remove_worker() {
  local master="${1:?Usage: party_state_remove_worker MASTER WORKER}"
  local worker="${2:?Missing worker}"
  local file lockdir tmp

  file="$(party_state_file "$master")"
  [[ -f "$file" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  lockdir="${file}.lock"
  tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"

  _party_lock "$lockdir" || {
    rm -f "$tmp"
    return 1
  }

  jq --arg w "$worker" '.workers = ((.workers // []) - [$w])' "$file" > "$tmp" && mv "$tmp" "$file"
  local rc=$?

  _party_unlock "$lockdir"
  return $rc
}

# Print worker IDs from a master's manifest, one per line.
party_state_get_workers() {
  local master="${1:?Usage: party_state_get_workers MASTER}"
  local file

  file="$(party_state_file "$master")"
  [[ -f "$file" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  jq -r '.workers // [] | .[]' "$file" 2>/dev/null
}

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
    # Not inside tmux — scan for a running party session
    local matches
    matches=$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^party-' || true)
    local count
    count=$(echo "$matches" | grep -c . 2>/dev/null || echo 0)

    if [[ "$count" -eq 1 ]]; then
      name="$matches"
    elif [[ "$count" -gt 1 ]]; then
      echo "Error: Multiple party sessions found — set PARTY_SESSION to disambiguate:" >&2
      echo "$matches" >&2
      return 1
    else
      echo "Error: No party session found and not inside tmux" >&2
      return 1
    fi
  fi

  if [[ ! "$name" =~ ^party- ]]; then
    echo "Error: Current tmux session '$name' is not a party session" >&2
    return 1
  fi

  local state_dir
  state_dir="$(ensure_party_state_dir "$name")"

  SESSION_NAME="$name"
  STATE_DIR="$state_dir"
}

# Returns 0 if the target pane is idle (safe to send), 1 if busy.
# Busy = pane is in copy mode (user is reading scrollback).
# Fails closed: tmux command failure → return 1 (uncertain = busy).
tmux_pane_idle() {
  local target="$1"
  local pane_in_mode

  pane_in_mode=$(tmux display-message -t "$target" -p '#{pane_in_mode}' 2>/dev/null) || return 1
  [[ "$pane_in_mode" -gt 0 ]] && return 1

  return 0
}

# Sends text to a tmux pane running a TUI agent (Claude Code / Codex CLI).
# Uses -l flag + delay + separate Enter to avoid paste-mode newline issue.
# Guards against injecting text while a human has the pane focused.
# Returns 75 (EX_TEMPFAIL) on timeout — message is dropped (best-effort delivery).
tmux_send() {
  local target="$1"
  local text="$2"
  local caller="${3:-}"

  # Force bypass for tests and explicit override
  if [[ "${TMUX_SEND_FORCE:-}" == "1" ]]; then
    tmux send-keys -t "$target" -l "$text"
    sleep 0.1
    tmux send-keys -t "$target" Enter
    return 0
  fi

  # Try immediate send
  if tmux_pane_idle "$target"; then
    tmux send-keys -t "$target" -l "$text"
    sleep 0.1
    tmux send-keys -t "$target" Enter
    return 0
  fi

  # Poll until idle or timeout
  local timeout_s="${TMUX_SEND_TIMEOUT:-1.5}"
  local timeout_ms
  timeout_ms=$(awk -v s="$timeout_s" 'BEGIN { printf "%d", s * 1000 }')
  local elapsed_ms=0

  while (( elapsed_ms < timeout_ms )); do
    sleep 0.1
    elapsed_ms=$(( elapsed_ms + 100 ))
    if tmux_pane_idle "$target"; then
      tmux send-keys -t "$target" -l "$text"
      sleep 0.1
      tmux send-keys -t "$target" Enter
      return 0
    fi
  done

  # Timeout — message dropped (best-effort delivery)
  return 75
}

# ---------------------------------------------------------------------------
# Role-based pane routing
# ---------------------------------------------------------------------------

# Resolve a pane target by @party_role metadata.
# Usage: party_role_pane_target SESSION ROLE
# stdout: target pane (e.g. "session:0.1")
# exit 0: resolved | exit 1: not found or ambiguous
party_role_pane_target() {
  local session="${1:?Usage: party_role_pane_target SESSION ROLE}"
  local role="${2:?Missing role}"

  # Auto-discover the window this pane is in. TMUX_PANE gives the exact pane ID
  # (e.g. %5), so -t ensures we get OUR window, not the client's active window.
  # This matters when multiple windows have the same roles.
  local window
  if [[ -n "${TMUX_PANE:-}" ]]; then
    window="$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null || echo 0)"
  else
    window="$(tmux display-message -p '#{window_index}' 2>/dev/null || echo 0)"
  fi

  # Search current window first, then all windows in the session
  local -a search_windows=("$window")
  local all_windows
  all_windows=$(tmux list-windows -t "$session" -F '#{window_index}' 2>/dev/null || true)
  while IFS= read -r w; do
    [[ -n "$w" && "$w" != "$window" ]] && search_windows+=("$w")
  done <<< "$all_windows"

  for win in "${search_windows[@]}"; do
    local pane_list
    pane_list=$(tmux list-panes -t "$session:$win" -F '#{pane_index} #{@party_role}' 2>/dev/null) || continue

    local -a found=()
    local idx pane_role
    while IFS=' ' read -r idx pane_role; do
      [[ -n "$idx" ]] || continue
      [[ "$pane_role" == "$role" ]] && found+=("$idx")
    done <<< "$pane_list"

    if [[ ${#found[@]} -gt 1 ]]; then
      echo "ROLE_AMBIGUOUS: Multiple panes with @party_role='$role' in session '$session:$win'" >&2
      return 1
    fi

    if [[ ${#found[@]} -eq 1 ]]; then
      printf '%s:%s.%s\n' "$session" "$win" "${found[0]}"
      return 0
    fi
  done

  echo "ROLE_NOT_FOUND: No pane with @party_role='$role' in session '$session'" >&2
  return 1
}

# Resolve pane target with legacy fallback for pre-change sessions.
# Fallback only activates for exactly 2-pane sessions with no role metadata.
# Usage: party_role_pane_target_with_fallback SESSION ROLE
# stdout: target pane | exit 0: resolved | exit 1: unresolved
party_role_pane_target_with_fallback() {
  local session="${1:?Usage: party_role_pane_target_with_fallback SESSION ROLE}"
  local role="${2:?Missing role}"

  # Capture both stdout (target) and stderr (diagnostics) to preserve error codes
  local output rc=0
  output=$(party_role_pane_target "$session" "$role" 2>&1) || rc=$?

  if [[ $rc -eq 0 ]]; then
    printf '%s\n' "$output"
    return 0
  fi

  # Propagate ROLE_AMBIGUOUS — fallback cannot resolve duplicate roles
  if [[ "$output" == *"ROLE_AMBIGUOUS"* ]]; then
    echo "$output" >&2
    return 1
  fi

  # Topology-guarded fallback: only for legacy 2-pane sessions without role metadata
  local window
  if [[ -n "${TMUX_PANE:-}" ]]; then
    window="$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null || echo 0)"
  else
    window="$(tmux display-message -p '#{window_index}' 2>/dev/null || echo 0)"
  fi

  local pane_list
  pane_list=$(tmux list-panes -t "$session:$window" -F '#{pane_index} #{@party_role}' 2>/dev/null) || {
    echo "ROUTING_UNRESOLVED: Cannot list panes for session '$session:$window'" >&2
    return 1
  }

  local pane_count=0 has_roles=0
  local idx pane_role
  while IFS=' ' read -r idx pane_role; do
    [[ -n "$idx" ]] || continue
    pane_count=$((pane_count + 1))
    [[ -z "$pane_role" ]] || has_roles=1
  done <<< "$pane_list"

  if [[ "$pane_count" -eq 2 && "$has_roles" -eq 0 ]]; then
    case "$role" in
      claude) printf '%s:%s.0\n' "$session" "$window"; return 0 ;;
      codex)  printf '%s:%s.1\n' "$session" "$window"; return 0 ;;
    esac
  fi

  echo "ROUTING_UNRESOLVED: Cannot resolve role '$role' in session '$session:$window'" >&2
  return 1
}
