#!/usr/bin/env bash
# party-preview.sh — Thin wrapper delegating to party-cli picker preview.
# Called by fzf preview in legacy paths. New paths use party-cli directly.
set -euo pipefail

sid="${1:?Usage: party-preview.sh SESSION_ID [MANIFEST_ROOT] [HOME]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/party-lib.sh"

party_resolve_cli_bin || exit 1
exec "${PARTY_CLI_CMD[@]}" picker preview -- "$sid"
