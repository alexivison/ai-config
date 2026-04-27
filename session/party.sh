#!/usr/bin/env bash
# party.sh — Thin wrapper that delegates to party-cli for all operations.
# party-lib.sh is retained only for the role-based transport layer
# (tmux-companion.sh, tmux-primary.sh).
#
# Usage: party.sh [--detached] [--prompt "text"] [--primary AGENT] [--companion AGENT] [--no-companion] [--resume-agent ROLE=ID] [TITLE]
#        party.sh --switch | --continue <party-id> | --delete <party-id> | --list | --install-tpm
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve party-cli binary (on PATH, or via go run as fallback)
# ---------------------------------------------------------------------------
_resolve_party_cli() {
  if command -v party-cli &>/dev/null; then
    PARTY_CLI_CMD=(party-cli)
    return 0
  fi

  local repo_root
  repo_root="${PARTY_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
  if command -v go &>/dev/null && [[ -f "$repo_root/tools/party-cli/main.go" ]]; then
    PARTY_CLI_CMD=(env "PARTY_REPO_ROOT=$repo_root" go -C "$repo_root/tools/party-cli" run .)
    return 0
  fi

  echo "Error: party-cli not found. Build with: cd tools/party-cli && go install ." >&2
  return 1
}

PARTY_CLI_CMD=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
party_usage() {
  cat <<'EOF'
Usage:
  party.sh [--detached] [--prompt "text"] [--primary AGENT] [--companion AGENT] [--no-companion] [--resume-agent ROLE=ID] [TITLE]
  party.sh --master [--detached] [--prompt "text"] [--primary AGENT] [--resume-agent ROLE=ID] [TITLE]
  party.sh --master-id <master-id> [--detached] [--prompt "text"] [--primary AGENT] [--companion AGENT] [--no-companion] [--resume-agent ROLE=ID] [TITLE]

  party.sh --promote [party-id]
  party.sh --switch
  party.sh --continue <party-id>
  party.sh continue <party-id>
  party.sh --delete <party-id>
  party.sh --list
  party.sh --install-tpm

All commands delegate to party-cli. Run 'party-cli --help' for details.
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

# ---------------------------------------------------------------------------
# Parse arguments and delegate
# ---------------------------------------------------------------------------
_party_resume_agents=()
_party_title=""
_party_detached=0
_party_prompt=""
_party_master=0
_party_master_id=""
_party_primary=""
_party_companion=""
_party_no_companion=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-tpm) party_install_tpm; exit ;;
    --help|-h) party_usage; exit ;;

    # Commands that delegate directly to party-cli (no attach needed)
    --list)
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" list
      ;;
    --delete)
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" delete "${2:?--delete requires a session ID}"
      ;;
    --promote)
      _promote_target="${2:-}"
      if [[ -z "$_promote_target" && -n "${TMUX:-}" ]]; then
        _promote_target="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
      fi
      if [[ -z "$_promote_target" ]]; then
        echo "Error: --promote requires a session ID or must be run inside tmux." >&2
        exit 1
      fi
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" promote "$_promote_target"
      ;;
    --resize)
      _resize_target="${2:-}"
      if [[ -z "$_resize_target" && -n "${TMUX:-}" ]]; then
        _resize_target="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
      fi
      if [[ -z "$_resize_target" ]]; then
        echo "Error: --resize requires a session ID or must be run inside tmux." >&2
        exit 1
      fi
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" resize "$_resize_target"
      ;;
    --pick-entries)
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" picker entries
      ;;

    # Commands that delegate to party-cli then attach
    --switch|switch)
      _resolve_party_cli || exit 1
      exec "${PARTY_CLI_CMD[@]}" picker
      ;;
    --continue|continue)
      session="${2:-}"
      _resolve_party_cli || exit 1
      if [[ -z "$session" ]]; then
        exec "${PARTY_CLI_CMD[@]}" picker
      fi
      exec "${PARTY_CLI_CMD[@]}" continue --attach "$session"
      ;;

    # Accumulate flags for start
    --detached) _party_detached=1; shift ;;
    --prompt) _party_prompt="${2:?--prompt requires a message}"; shift 2 ;;
    --primary) _party_primary="${2:?--primary requires an agent name}"; shift 2 ;;
    --companion) _party_companion="${2:?--companion requires an agent name}"; shift 2 ;;
    --no-companion) _party_no_companion=1; shift ;;
    --resume-agent) _party_resume_agents+=("${2:?--resume-agent requires ROLE=ID}"); shift 2 ;;
    --master) _party_master=1; shift ;;
    --master-id) _party_master_id="${2:?--master-id requires a session ID}"; shift 2 ;;

    --)      shift; break ;;
    --*)     party_usage >&2; exit 1 ;;
    *)       _party_title="$1"; shift ;;
  esac
done

# Remaining positional args after -- (e.g., title from tracker spawn)
[[ $# -gt 0 && -z "$_party_title" ]] && _party_title="$1"

# Master sessions replace the companion pane with the tracker.
if [[ "$_party_master" -eq 1 ]]; then
  _party_no_companion=1
fi

# --- Start a new session via party-cli ---
_resolve_party_cli || exit 1

start_args=(start --cwd "$PWD")
[[ -n "$_party_title" ]]        && start_args+=("$_party_title")
[[ "$_party_master" -eq 1 ]]    && start_args+=(--master)
[[ -n "$_party_master_id" ]]    && start_args+=(--master-id "$_party_master_id")
[[ -n "$_party_primary" ]]      && start_args+=(--primary "$_party_primary")
[[ "$_party_no_companion" -eq 0 && -n "$_party_companion" ]] && start_args+=(--companion "$_party_companion")
[[ "$_party_no_companion" -eq 1 ]] && start_args+=(--no-companion)
[[ -n "$_party_prompt" ]]       && start_args+=(--prompt "$_party_prompt")
for ra in "${_party_resume_agents[@]}"; do
  start_args+=(--resume-agent "$ra")
done

# Use --attach when not detached to let party-cli handle attach directly.
if [[ "$_party_detached" -eq 0 ]]; then
  start_args+=(--attach)
fi

exec "${PARTY_CLI_CMD[@]}" "${start_args[@]}"
