#!/usr/bin/env bash

_PARTY_CLI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

party_cli_query() {
  local query_root="${1:-}"
  local mode="${2:-}"
  local helper_dir repo_root output

  [ -n "$mode" ] || return 1

  if output=$(party-cli agent query "$mode" 2>/dev/null); then
    printf '%s\n' "$output"
    return 0
  fi

  # Tests use this to simulate a missing CLI even on systems where `go run`
  # could rebuild it from the checked-out source tree.
  if [ "${PARTY_CLI_DISABLE_GO_FALLBACK:-}" = "1" ]; then
    return 1
  fi

  if ! command -v go >/dev/null 2>&1; then
    return 1
  fi

  helper_dir="$_PARTY_CLI_LIB_DIR"
  repo_root="$(cd "$helper_dir/../../.." && pwd)"
  if [ ! -f "$repo_root/tools/party-cli/go.mod" ]; then
    return 1
  fi

  output=$(
    cd "$repo_root/tools/party-cli" &&
      go run . agent query "$mode"
  2>/dev/null) || return 1

  printf '%s\n' "$output"
}
