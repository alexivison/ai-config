#!/usr/bin/env bash
# party-relay.sh — Thin wrapper for master/worker communication via party-cli.
# The --companion transport path sources party-lib.sh for pane routing helpers.
#
# Usage:
#   party-relay.sh <worker-id> "message"          # relay to one worker
#   party-relay.sh --broadcast "message"           # broadcast to all workers
#   party-relay.sh --read <worker-id> [--lines N]  # read worker's primary pane
#   party-relay.sh --report "message"              # worker reports back to master
#   party-relay.sh --list                          # list workers + status
#   party-relay.sh --delete <worker-id>            # delete a worker
#   party-relay.sh --spawn [--prompt "..."] "title" # spawn a new worker
#   party-relay.sh --file <path> <worker-id>         # send file pointer to worker
#   party-relay.sh --companion <worker-id> "message" # send raw text to worker's companion pane
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

_load_transport_helpers() {
  local repo_root
  repo_root="${PARTY_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
  # shellcheck source=session/party-lib.sh
  source "$repo_root/session/party-lib.sh"
}

relay_usage() {
  cat <<'EOF'
Usage:
  party-relay.sh <worker-id> "message"
  party-relay.sh --broadcast "message"
  party-relay.sh --read <worker-id> [--lines N]
  party-relay.sh --report "message"
  party-relay.sh --list
  party-relay.sh --delete <worker-id>
  party-relay.sh --spawn [--prompt "text"] "title"
  party-relay.sh --file <path> <worker-id>         # send file pointer to worker
  party-relay.sh --companion <worker-id> "msg"     # send raw text to worker's companion pane
EOF
}

# --- Main ---

if [[ $# -eq 0 ]]; then
  relay_usage
  exit 1
fi

_resolve_party_cli || exit 1

case "$1" in
  --broadcast)
    # party-cli broadcast auto-discovers master session when master-id is omitted
    exec "${PARTY_CLI_CMD[@]}" broadcast "${2:?--broadcast requires a message}"
    ;;
  --read)
    shift
    _read_worker="${1:?--read requires a worker ID}"
    _read_lines=50
    shift
    if [[ "${1:-}" == "--lines" ]]; then
      _read_lines="${2:?--lines requires a number}"
      shift 2
    fi
    exec "${PARTY_CLI_CMD[@]}" read "$_read_worker" --lines "$_read_lines"
    ;;
  --report)
    # party-cli report auto-discovers session when session-id is omitted
    exec "${PARTY_CLI_CMD[@]}" report "${2:?--report requires a message}"
    ;;
  --list)
    # party-cli workers auto-discovers master session when master-id is omitted
    exec "${PARTY_CLI_CMD[@]}" workers
    ;;
  --delete)
    exec "${PARTY_CLI_CMD[@]}" delete "${2:?--delete requires a worker ID}"
    ;;
  --spawn)
    shift
    # party-cli spawn auto-discovers master session when master-id is omitted
    _spawn_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --prompt) _spawn_args+=(--prompt "${2:?--prompt requires a message}"); shift 2 ;;
        *) _spawn_args+=("$1"); shift ;;
      esac
    done
    exec "${PARTY_CLI_CMD[@]}" spawn "${_spawn_args[@]}"
    ;;
  --file)
    shift
    _file_path="${1:?--file requires a file path}"
    _file_worker="${2:?--file requires a worker ID}"
    if [[ ! -f "$_file_path" ]]; then
      echo "Error: file '$_file_path' not found." >&2
      exit 1
    fi
    exec "${PARTY_CLI_CMD[@]}" relay "$_file_worker" "Read and follow the instructions in $_file_path. Act on them now, then report back with results."
    ;;
  --companion)
    _load_transport_helpers
    _relay_mode="$1"
    shift
    _companion_worker="${1:?$_relay_mode requires a worker ID}"
    _companion_msg="${2:?$_relay_mode requires a message}"
    _companion_pane=$(party_companion_pane_target "$_companion_worker") || {
      echo "Error: Cannot resolve companion pane in worker '$_companion_worker'" >&2
      exit 1
    }
    _companion_rc=0
    tmux_send "$_companion_pane" "$_companion_msg" "party-relay.sh:companion" || _companion_rc=$?
    if [[ $_companion_rc -eq 75 ]]; then
      echo "Error: Companion pane busy in worker '$_companion_worker'. Message dropped." >&2
      exit 1
    elif [[ $_companion_rc -ne 0 && $_companion_rc -ne 76 ]]; then
      echo "Error: Failed to send to companion in worker '$_companion_worker' (rc=$_companion_rc)." >&2
      exit 1
    fi
    echo "Sent to companion in '$_companion_worker'."
    ;;
  --help|-h)
    relay_usage
    ;;
  *)
    # Direct relay: party-relay.sh <worker-id> "message"
    if [[ $# -lt 2 ]]; then
      relay_usage >&2
      exit 1
    fi
    exec "${PARTY_CLI_CMD[@]}" relay "$1" "$2"
    ;;
esac
