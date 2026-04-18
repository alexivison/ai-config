#!/usr/bin/env bash
# party-lib.sh — Shared helpers for party session discovery and tmux transport
# Sourced by thin wrappers (party.sh, party-relay.sh, etc.) and the role-based
# tmux transport scripts.
#
# Manifest CRUD (create, set_field, get_field, add_worker, remove_worker)
# has been retired — party-cli (Go) is the sole manifest writer.

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

# Write the companion status file atomically via .tmp + mv.
# The Codex runtime still owns codex-status.json, so companion helpers write that file.
# Usage: write_codex_status RUNTIME_DIR STATE [TARGET] [MODE] [VERDICT] [ERROR]
write_codex_status() {
  local runtime_dir="${1:?Usage: write_codex_status RUNTIME_DIR STATE [TARGET] [MODE] [VERDICT] [ERROR]}"
  local state="${2:?Usage: write_codex_status RUNTIME_DIR STATE}"
  local target="${3:-}"
  local mode="${4:-}"
  local verdict="${5:-}"
  local error_msg="${6:-}"

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local tmp_file="$runtime_dir/codex-status.json.tmp"
  local final_file="$runtime_dir/codex-status.json"

  mkdir -p "$runtime_dir"

  # Build JSON with jq for safety (no injection from shell vars)
  jq -n \
    --arg state "$state" \
    --arg target "$target" \
    --arg mode "$mode" \
    --arg verdict "$verdict" \
    --arg error "$error_msg" \
    --arg started_at "$([ "$state" = "working" ] && echo "$now" || echo "")" \
    --arg finished_at "$([ "$state" != "working" ] && echo "$now" || echo "")" \
    '{state: $state} +
     (if $target != "" then {target: $target} else {} end) +
     (if $mode != "" then {mode: $mode} else {} end) +
     (if $verdict != "" then {verdict: $verdict} else {} end) +
     (if $started_at != "" then {started_at: $started_at} else {} end) +
     (if $finished_at != "" then {finished_at: $finished_at} else {} end) +
     (if $error != "" then {error: $error} else {} end)' \
    > "$tmp_file"

  mv "$tmp_file" "$final_file"
}

write_companion_status() {
  write_codex_status "$@"
}

# ---------------------------------------------------------------------------
# File handoff contract helpers
# ---------------------------------------------------------------------------

# Return the canonical completion notice for a file-backed response handoff.
party_transport_response_completion_message() {
  local response_path="${1:?Usage: party_transport_response_completion_message RESPONSE_PATH}"
  printf 'Task complete. Response at: %s\n' "$response_path"
}

# Return 0 when the message is a recognized transport completion notice.
# Legacy "Response ready at:" remains accepted for compatibility.
party_transport_is_completion_message() {
  local message="${1:?Usage: party_transport_is_completion_message MESSAGE}"
  case "$message" in
    "Review complete. Findings at: "*|\
    "Plan review complete. Findings at: "*|\
    "Task complete. Response at: "*|\
    "Response ready at: "*)
      return 0
      ;;
  esac
  return 1
}

# Extract the findings/response path from a recognized completion notice.
party_transport_completion_path() {
  local message="${1:?Usage: party_transport_completion_path MESSAGE}"
  case "$message" in
    "Review complete. Findings at: "*)
      printf '%s\n' "${message#Review complete. Findings at: }"
      ;;
    "Plan review complete. Findings at: "*)
      printf '%s\n' "${message#Plan review complete. Findings at: }"
      ;;
    "Task complete. Response at: "*)
      printf '%s\n' "${message#Task complete. Response at: }"
      ;;
    "Response ready at: "*)
      printf '%s\n' "${message#Response ready at: }"
      ;;
    *)
      return 1
      ;;
  esac
}

# Append the canonical handoff instruction for file-backed task replies.
party_transport_response_handoff_instruction() {
  local notify_script="${1:?Usage: party_transport_response_handoff_instruction NOTIFY_SCRIPT RESPONSE_PATH}"
  local response_path="${2:?Usage: party_transport_response_handoff_instruction NOTIFY_SCRIPT RESPONSE_PATH}"
  local completion_message
  completion_message="$(party_transport_response_completion_message "$response_path")"
  printf '%s' "Do not poll the response file. Wait for the tmux completion notice, then read it. When done, run: $notify_script \"$completion_message\""
}

# Attach or switch to a party session. Uses switch-client inside tmux,
# exec attach outside tmux.
party_attach() {
  local session="${1:?Usage: party_attach SESSION_NAME}"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$session"
  else
    # No exec — let the shell survive after tmux detaches so the user
    # can reattach to other sessions instead of losing the terminal.
    tmux attach -t "$session"
  fi
}

# ---------------------------------------------------------------------------
# Master mode helpers
# ---------------------------------------------------------------------------

# Returns 0 if the session is a master session (session_type == "master").
party_is_master() {
  local session="${1:?Usage: party_is_master SESSION}"
  local file
  file="$(party_state_file "$session")"
  [[ -f "$file" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  local st
  st="$(jq -r '.session_type // empty' "$file" 2>/dev/null || true)"
  [[ "$st" == "master" ]]
}

# Discovers the party session this script is running inside.
# Uses the exact pane when available so multi-session tmux clients do not
# leak messages across party sessions.
# Sets SESSION_NAME and STATE_DIR. Returns 1 if not inside a party session.
discover_session() {
  local name

  # PARTY_SESSION override for testing (scripts run outside tmux)
  if [[ -n "${PARTY_SESSION:-}" ]]; then
    name="$PARTY_SESSION"
  elif [[ -n "${TMUX_PANE:-}" ]]; then
    name=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}' 2>/dev/null)
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
  state_dir="$(party_runtime_dir "$name")"
  mkdir -p "$state_dir"
  printf '%s\n' "$name" > "$state_dir/session-name"

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
# Returns: 0 = delivered (confirmed in pane buffer)
#          75 = pane busy/dropped (EX_TEMPFAIL)
#          76 = delivery unconfirmed (sent but not seen in buffer)
tmux_send() {
  local target="$1"
  local text="$2"
  local caller="${3:-}"

  # Force bypass for tests and explicit override (no confirmation)
  if [[ "${TMUX_SEND_FORCE:-}" == "1" ]]; then
    tmux send-keys -t "$target" -l "$text"
    sleep 0.1
    tmux send-keys -t "$target" Enter
    return 0
  fi

  # _tmux_send_once: send keys then verify delivery via capture-pane.
  # Checks that the first 40 chars of the message appear in the pane buffer.
  # False positives from stale buffer content are acceptable — the alternative
  # (embedding a sentinel in the payload) corrupts the AI prompt.
  _tmux_send_once() {
    tmux send-keys -t "$target" -l "$text"
    sleep 0.1
    tmux send-keys -t "$target" Enter

    # Verify: check pane buffer for the message using grep -F
    # (not glob match — text contains [CODEX]/[CLAUDE] brackets)
    sleep 0.2
    local verify_text="${text:0:40}"
    local buffer
    buffer=$(tmux capture-pane -t "$target" -p -S -50 2>/dev/null || true)
    if [[ -n "$buffer" ]] && printf '%s' "$buffer" | grep -qF "$verify_text"; then
      return 0
    fi
    return 1
  }

  # Try immediate send
  if tmux_pane_idle "$target"; then
    if _tmux_send_once; then
      return 0
    fi
    # Sent but not confirmed in buffer
    return 76
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
      if _tmux_send_once; then
        return 0
      fi
      return 76
    fi
  done

  # Timeout — message dropped (pane busy)
  local excerpt="${text:0:80}"
  [[ ${#text} -gt 80 ]] && excerpt="${excerpt}…"
  echo "tmux_send: timeout after ${timeout_s}s sending to '$target'${caller:+ (caller: $caller)} payload=${excerpt}" >&2
  return 75
}

# ---------------------------------------------------------------------------
# Role-based pane routing
# ---------------------------------------------------------------------------

# Map canonical role names to their legacy pane tags.
_party_role_fallback() {
  case "${1:-}" in
    primary) printf 'claude\n' ;;
    companion) printf 'codex\n' ;;
    *) return 1 ;;
  esac
}

_party_role_label() {
  case "${1:-}" in
    primary) printf 'PRIMARY\n' ;;
    companion) printf 'COMPANION\n' ;;
    claude) printf 'CLAUDE\n' ;;
    codex) printf 'CODEX\n' ;;
    *) printf '%s\n' "${1^^}" ;;
  esac
}

_party_other_canonical_role() {
  case "${1:-}" in
    primary) printf 'companion\n' ;;
    companion) printf 'primary\n' ;;
    *) return 1 ;;
  esac
}

_party_has_other_canonical_role() {
  local session="${1:?Usage: _party_has_other_canonical_role SESSION ROLE}"
  local role="${2:?Missing role}"
  local other_role
  other_role=$(_party_other_canonical_role "$role" 2>/dev/null || true)
  [[ -n "$other_role" ]] || return 1
  _party_role_resolve_exact "$session" "$other_role" >/dev/null 2>&1
}

# Resolve an exact @party_role match without legacy fallback.
# On success, PARTY_ROLE_TARGET contains the tmux target.
# On failure, PARTY_ROLE_ERROR contains the human-readable error.
_party_role_resolve_exact() {
  local session="${1:?Usage: party_role_pane_target SESSION ROLE}"
  local role="${2:?Missing role}"
  PARTY_ROLE_TARGET=""
  PARTY_ROLE_ERROR=""

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
      PARTY_ROLE_ERROR="ROLE_AMBIGUOUS: Multiple panes with @party_role='$role' in session '$session:$win'"
      return 1
    fi

    if [[ ${#found[@]} -eq 1 ]]; then
      PARTY_ROLE_TARGET=$(printf '%s:%s.%s' "$session" "$win" "${found[0]}")
      return 0
    fi
  done

  PARTY_ROLE_ERROR="ROLE_NOT_FOUND: No pane with @party_role='$role' in session '$session'"
  return 1
}

# Resolve a pane target by @party_role metadata, accepting canonical role names
# with legacy fallback for sessions still tagged claude/codex.
# Usage: party_role_pane_target SESSION ROLE
# stdout: target pane (e.g. "session:0.1")
# exit 0: resolved | exit 1: not found or ambiguous
party_role_pane_target() {
  local session="${1:?Usage: party_role_pane_target SESSION ROLE}"
  local role="${2:?Missing role}"

  if _party_role_resolve_exact "$session" "$role"; then
    printf '%s\n' "$PARTY_ROLE_TARGET"
    return 0
  fi

  local exact_error="$PARTY_ROLE_ERROR"
  if [[ "$exact_error" == ROLE_NOT_FOUND:* ]]; then
    if _party_has_other_canonical_role "$session" "$role"; then
      echo "$exact_error" >&2
      return 1
    fi

    local fallback_role
    fallback_role=$(_party_role_fallback "$role" 2>/dev/null || true)
    if [[ -n "$fallback_role" ]]; then
      if _party_role_resolve_exact "$session" "$fallback_role"; then
        printf '%s\n' "$PARTY_ROLE_TARGET"
        return 0
      fi
      if [[ "$PARTY_ROLE_ERROR" == ROLE_AMBIGUOUS:* ]]; then
        echo "$PARTY_ROLE_ERROR" >&2
        return 1
      fi
    fi
  fi

  echo "${exact_error:-ROLE_NOT_FOUND: No pane with @party_role='$role' in session '$session'}" >&2
  return 1
}

# Return the transport prefix for messages sent by the given logical role.
# New sessions use [PRIMARY]/[COMPANION]; legacy sessions keep [CLAUDE]/[CODEX].
party_role_message_prefix() {
  local session="${1:?Usage: party_role_message_prefix SESSION ROLE}"
  local role="${2:?Missing role}"

  if _party_role_resolve_exact "$session" "$role"; then
    printf '[%s]\n' "$(_party_role_label "$role")"
    return 0
  fi

  local fallback_role
  if _party_has_other_canonical_role "$session" "$role"; then
    printf '[%s]\n' "$(_party_role_label "$role")"
    return 0
  fi

  fallback_role=$(_party_role_fallback "$role" 2>/dev/null || true)
  if [[ -n "$fallback_role" ]] && _party_role_resolve_exact "$session" "$fallback_role"; then
    printf '[%s]\n' "$(_party_role_label "$fallback_role")"
    return 0
  fi

  printf '[%s]\n' "$(_party_role_label "$role")"
}

# ---------------------------------------------------------------------------
# Layout mode helpers
# ---------------------------------------------------------------------------

# Returns the active layout mode: "sidebar" or "classic".
# sidebar: hidden Codex window 0 + workspace window 1 (party-cli | Claude | Shell)
# classic: single window with Codex | Claude | Shell (original layout)
party_layout_mode() {
  local mode="${PARTY_LAYOUT:-sidebar}"
  case "$mode" in
    sidebar) echo "sidebar" ;;
    *)       echo "classic" ;;
  esac
}

# Resolve the primary pane target in a session.
party_primary_pane_target() {
  local session="${1:?Usage: party_primary_pane_target SESSION}"
  party_role_pane_target "$session" "primary"
}

# Resolve the companion pane target via role metadata.
# This works across classic/sidebar layouts and rejects no-companion sessions.
party_companion_pane_target() {
  local session="${1:?Usage: party_companion_pane_target SESSION}"
  party_role_pane_target "$session" "companion"
}

# Backward-compatible wrapper for older callers.
party_codex_pane_target() {
  local session="${1:?Usage: party_codex_pane_target SESSION}"
  party_companion_pane_target "$session"
}

# Resolve party-cli as an array-safe command for CLI delegation.
# Populates the global array PARTY_CLI_CMD with the command tokens.
# Usage: party_resolve_cli_bin && "${PARTY_CLI_CMD[@]}" subcommand args...
party_resolve_cli_bin() {
  PARTY_CLI_CMD=()
  if command -v party-cli &>/dev/null; then
    PARTY_CLI_CMD=(party-cli)
    return 0
  fi

  local _repo_root
  _repo_root="${PARTY_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
  if command -v go &>/dev/null && [[ -f "$_repo_root/tools/party-cli/main.go" ]]; then
    # go -C changes to the module directory before running (Go 1.21+).
    PARTY_CLI_CMD=(env "PARTY_REPO_ROOT=$_repo_root" go -C "$_repo_root/tools/party-cli" run .)
    return 0
  fi

  echo "Error: party-cli not found. Build with: cd tools/party-cli && go install ." >&2
  return 1
}
