#!/usr/bin/env bash
# party-relay.sh — Thin wrapper for master/worker communication via party-cli.
# Usage:
#   party-relay.sh <worker-id> "message"          # relay to one worker
#   party-relay.sh --broadcast "message"           # broadcast to all workers
#   party-relay.sh --read <worker-id> [--lines N]  # read worker's Claude pane
#   party-relay.sh --report "message"              # worker reports back to master
#   party-relay.sh --list                          # list workers + status
#   party-relay.sh --stop <worker-id>              # stop a worker
#   party-relay.sh --spawn [--prompt "..."] "title" # spawn a new worker
#   party-relay.sh --file <path> <worker-id>        # send file pointer to worker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/party-lib.sh"

relay_usage() {
  cat <<'EOF'
Usage:
  party-relay.sh <worker-id> "message"
  party-relay.sh --broadcast "message"
  party-relay.sh --read <worker-id> [--lines N]
  party-relay.sh --report "message"
  party-relay.sh --list
  party-relay.sh --stop <worker-id>
  party-relay.sh --spawn [--prompt "text"] "title"
  party-relay.sh --file <path> <worker-id>    # send file pointer to worker
EOF
}

# Discover master session for commands that require it.
relay_discover_master() {
  discover_session || {
    echo "Error: party-relay.sh must be run inside a party session or with PARTY_SESSION set." >&2
    return 1
  }
  if ! party_is_master "$SESSION_NAME"; then
    echo "Error: session '$SESSION_NAME' is not a master session." >&2
    return 1
  fi
}

# --- Main ---

if [[ $# -eq 0 ]]; then
  relay_usage
  exit 1
fi

party_resolve_cli_bin || exit 1

case "$1" in
  --broadcast)
    relay_discover_master
    exec "${PARTY_CLI_CMD[@]}" broadcast "$SESSION_NAME" "${2:?--broadcast requires a message}"
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
    discover_session || { echo "Error: must be run inside a party session." >&2; exit 1; }
    exec "${PARTY_CLI_CMD[@]}" report "$SESSION_NAME" "${2:?--report requires a message}"
    ;;
  --list)
    relay_discover_master
    exec "${PARTY_CLI_CMD[@]}" workers "$SESSION_NAME"
    ;;
  --stop)
    relay_discover_master
    exec "${PARTY_CLI_CMD[@]}" stop "${2:?--stop requires a worker ID}"
    ;;
  --spawn)
    relay_discover_master
    shift
    _spawn_args=("$SESSION_NAME")
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
    exec "${PARTY_CLI_CMD[@]}" relay "$_file_worker" "Read relay instructions at $_file_path"
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
