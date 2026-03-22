#!/usr/bin/env bash
# party.sh — Thin wrapper that delegates to party-cli for all operations.
# Session creation, lifecycle, messaging, and picker are handled by party-cli.
# party-lib.sh is retained for tmux-codex.sh and classic routing helpers.
#
# Usage: party.sh [--detached] [--prompt "text"] [--resume-claude ID] [--resume-codex ID] [TITLE]
#        party.sh --switch | --continue <party-id> | --stop [name] | --list | --install-tpm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/party-lib.sh"

# party_attach is provided by party-lib.sh (sourced above)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
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
    --help|-h) party_usage; exit ;;

    # Commands that delegate directly to party-cli (no attach needed)
    --list)
      party_resolve_cli_bin || exit 1
      exec "${PARTY_CLI_CMD[@]}" list
      ;;
    --stop)
      party_resolve_cli_bin || exit 1
      exec "${PARTY_CLI_CMD[@]}" stop ${2:+"$2"}
      ;;
    --delete)
      party_resolve_cli_bin || exit 1
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
      party_resolve_cli_bin || exit 1
      exec "${PARTY_CLI_CMD[@]}" promote "$_promote_target"
      ;;
    --pick-entries)
      party_resolve_cli_bin || exit 1
      exec "${PARTY_CLI_CMD[@]}" picker entries
      ;;

    # Commands that delegate to party-cli then attach
    --switch|switch)
      party_resolve_cli_bin || exit 1
      exec "${PARTY_CLI_CMD[@]}" picker
      ;;
    --continue|continue)
      session="${2:-}"
      party_resolve_cli_bin || exit 1
      if [[ -z "$session" ]]; then
        exec "${PARTY_CLI_CMD[@]}" picker
      fi
      "${PARTY_CLI_CMD[@]}" continue "$session" || exit 1
      party_attach "$session"
      exit
      ;;

    # Accumulate flags for start
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

# Remaining positional args after -- (e.g., title from tracker spawn)
[[ $# -gt 0 && -z "$_party_title" ]] && _party_title="$1"

# --- Start a new session via party-cli ---
party_resolve_cli_bin || exit 1

start_args=(start)
[[ -n "$_party_title" ]]        && start_args+=("$_party_title")
[[ "$_party_master" -eq 1 ]]    && start_args+=(--master)
[[ -n "$_party_master_id" ]]    && start_args+=(--master-id "$_party_master_id")
[[ -n "$_party_prompt" ]]       && start_args+=(--prompt "$_party_prompt")
[[ -n "$_party_resume_claude" ]] && start_args+=(--resume-claude "$_party_resume_claude")
[[ -n "$_party_resume_codex" ]]  && start_args+=(--resume-codex "$_party_resume_codex")

output="$("${PARTY_CLI_CMD[@]}" "${start_args[@]}")" || exit 1
echo "$output"

# Extract session ID from party-cli output.
# party-cli prints "... session 'party-XXXX' started." — extract the quoted ID.
session_id="$(echo "$output" | sed -n "s/.*'\(party-[^']*\)'.*/\1/p" | head -1)"

if [[ -z "$session_id" ]]; then
  echo "Error: could not extract session ID from party-cli output." >&2
  exit 1
fi

if [[ "$_party_detached" -eq 0 ]]; then
  party_attach "$session_id"
fi
