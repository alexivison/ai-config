#!/usr/bin/env bash
# party.sh — Backward-compatibility shim. Delegates all operations to party-cli.
# New code should call party-cli directly.
set -euo pipefail

# Resolve party-cli binary
if command -v party-cli &>/dev/null; then
  CLI=(party-cli)
elif command -v go &>/dev/null; then
  repo_root="${PARTY_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
  if [[ -f "$repo_root/tools/party-cli/main.go" ]]; then
    CLI=(env "PARTY_REPO_ROOT=$repo_root" go -C "$repo_root/tools/party-cli" run .)
  fi
fi

if [[ ${#CLI[@]} -eq 0 ]]; then
  echo "Error: party-cli not found. Build with: cd tools/party-cli && go install ." >&2
  exit 1
fi

# Parse arguments and translate to party-cli subcommands.
case "${1:-}" in
  --help|-h)       exec "${CLI[@]}" --help ;;
  --list)          exec "${CLI[@]}" list ;;
  --stop)          shift; exec "${CLI[@]}" stop "$@" ;;
  --delete)        shift; exec "${CLI[@]}" delete "$@" ;;
  --promote)       shift; exec "${CLI[@]}" promote "$@" ;;
  --resize)        shift; exec "${CLI[@]}" resize "$@" ;;
  --switch|switch) exec "${CLI[@]}" picker ;;
  --continue|continue)
    shift
    if [[ -z "${1:-}" ]]; then
      exec "${CLI[@]}" picker
    fi
    exec "${CLI[@]}" continue --attach "$@"
    ;;
  --install-tpm)
    tpm_path="${TMUX_PLUGIN_MANAGER_PATH:-$HOME/.tmux/plugins/tpm}"
    if [[ -d "$tpm_path/.git" ]]; then echo "TPM already installed at: $tpm_path"; exit 0; fi
    git clone https://github.com/tmux-plugins/tpm "$tpm_path" >/dev/null
    echo "TPM installed at: $tpm_path"
    exit 0
    ;;
esac

# Accumulate start flags.
args=(start --cwd "$PWD")
detached=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --detached) detached=1; shift ;;
    --prompt) args+=(--prompt "$2"); shift 2 ;;
    --resume-claude) args+=(--resume-claude "$2"); shift 2 ;;
    --resume-codex) args+=(--resume-codex "$2"); shift 2 ;;
    --master) args+=(--master); shift ;;
    --master-id) args+=(--master-id "$2"); shift 2 ;;
    --) shift; break ;;
    --*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) args+=("$1"); shift ;;
  esac
done
[[ $# -gt 0 ]] && args+=("$1")
[[ "$detached" -eq 0 ]] && args+=(--attach)

exec "${CLI[@]}" "${args[@]}"
