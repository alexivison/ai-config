#!/usr/bin/env bash
# party-picker.sh — Thin wrapper delegating to party-cli picker.
# Must be sourced after party-lib.sh (provides party_resolve_cli_bin).
# All picker logic (entries, fzf, preview) lives in party-cli.

# party_pick launches the interactive picker and returns the selected session.
party_pick() {
  party_resolve_cli_bin || return 1
  "${PARTY_CLI_CMD[@]}" picker
}

# party_switch launches the picker and attaches to the selected session.
party_switch() {
  party_resolve_cli_bin || return 1
  exec "${PARTY_CLI_CMD[@]}" picker
}
