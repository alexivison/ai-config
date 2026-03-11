#!/usr/bin/env bash
# party-picker.sh — fzf-based session picker with hierarchical display.
# Sourced by party.sh. Requires party-lib.sh already loaded.

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
    # Separate sessions into masters, workers, and standalone
    local -a masters=() workers=() standalone=()
    local -A worker_parent=()

    while IFS= read -r name; do
      local stype parent
      stype="$(party_state_get_field "$name" "session_type" 2>/dev/null || true)"
      parent="$(party_state_get_field "$name" "parent_session" 2>/dev/null || true)"
      if [[ "$stype" == "master" ]]; then
        masters+=("$name")
      elif [[ -n "$parent" ]]; then
        workers+=("$name")
        worker_parent["$name"]="$parent"
      else
        standalone+=("$name")
      fi
    done <<< "$live_sessions"

    # Print standalone sessions first
    for name in "${standalone[@]}"; do
      local cwd title marker
      cwd="$(party_state_get_field "$name" "cwd" 2>/dev/null || true)"
      title="$(party_state_get_field "$name" "title" 2>/dev/null || true)"
      marker="active"
      [[ "$name" == "$current_session" ]] && marker="* current"
      printf '%s\t%s\t%s\t%s\n' "$name" "$marker" "${title:--}" "$(_party_short_path "${cwd:--}")"
    done

    # Print masters with their workers indented beneath
    for name in "${masters[@]}"; do
      local cwd title marker worker_count
      cwd="$(party_state_get_field "$name" "cwd" 2>/dev/null || true)"
      title="$(party_state_get_field "$name" "title" 2>/dev/null || true)"
      worker_count="$(party_state_get_workers "$name" 2>/dev/null | grep -c . || echo 0)"
      marker="master ($worker_count)"
      [[ "$name" == "$current_session" ]] && marker="* master ($worker_count)"
      printf '%s\t%s\t%s\t%s\n' "$name" "$marker" "${title:--}" "$(_party_short_path "${cwd:--}")"

      # Indented workers
      for wname in "${workers[@]}"; do
        [[ "${worker_parent[$wname]:-}" == "$name" ]] || continue
        local wcwd wtitle wmarker
        wcwd="$(party_state_get_field "$wname" "cwd" 2>/dev/null || true)"
        wtitle="$(party_state_get_field "$wname" "title" 2>/dev/null || true)"
        wmarker="  worker"
        [[ "$wname" == "$current_session" ]] && wmarker="* worker"
        printf '%s\t%s\t%s\t%s\n' "  $wname" "$wmarker" "${wtitle:--}" "$(_party_short_path "${wcwd:--}")"
      done
    done

    # Orphan workers (master not running)
    for wname in "${workers[@]}"; do
      local parent="${worker_parent[$wname]:-}"
      local found=0
      for m in "${masters[@]}"; do [[ "$m" == "$parent" ]] && found=1; done
      [[ $found -eq 0 ]] || continue
      local wcwd wtitle wmarker
      wcwd="$(party_state_get_field "$wname" "cwd" 2>/dev/null || true)"
      wtitle="$(party_state_get_field "$wname" "title" 2>/dev/null || true)"
      wmarker="worker (orphan)"
      [[ "$wname" == "$current_session" ]] && wmarker="* worker (orphan)"
      printf '%s\t%s\t%s\t%s\n' "$wname" "$wmarker" "${wtitle:--}" "$(_party_short_path "${wcwd:--}")"
    done
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

# Shared fzf session picker. Returns selected session ID.
# Args: header_text [extra_fzf_args...]
_party_pick_session() {
  local header="${1:?Missing header}"
  shift

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
  selected="$(_party_fzf_select "$entries" "$header" \
    --bind="ctrl-d:execute(echo {} | grep -qv 'current' && echo {} | awk '{print \$1}' | xargs -I{} bash \"$script_path\" --delete {} || true)+reload(bash \"$script_path\" --pick-entries)" \
    "$@" \
  )" || return 1

  local target
  target="$(echo "$selected" | awk '{print $1}')"

  # Ignore separator line selection
  [[ "$target" =~ ^party- ]] || return 1

  echo "$target"
}

party_pick() {
  _party_pick_session "enter:resume  ctrl-d:delete  esc:cancel"
}

party_switch() {
  local target
  target="$(_party_pick_session "enter:switch/resume  ctrl-d:delete  esc:cancel")" || return 1

  if tmux has-session -t "$target" 2>/dev/null; then
    party_attach "$target"
  else
    party_continue "$target"
  fi
}
