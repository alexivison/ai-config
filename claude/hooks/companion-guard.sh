#!/usr/bin/env bash
# companion-guard.sh — Block direct tmux interaction with the companion.
# Forces Claude to use the companion transport script.
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
QUERY_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

source "$(dirname "$0")/lib/party-cli.sh"

DENY_MSG="BLOCKED: Do not interact with the companion directly via tmux. Use the transport script instead (--review, --prompt, --plan-review). The script handles pane/window resolution."

COMPANION_PATTERN=$(
  {
    party_cli_query "$QUERY_ROOT" "roles" 2>/dev/null || true
    party_cli_query "$QUERY_ROOT" "companion-name" 2>/dev/null || true
  } | awk 'NF && $0 != "primary"' \
    | sed 's/[][(){}.^$+*?|\\/]/\\&/g' \
    | sort -u \
    | paste -sd'|' -
)

[ -n "$COMPANION_PATTERN" ] || exit 0

deny() {
  jq -nc --arg reason "$DENY_MSG" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

has_companion_ref() {
  [[ "$1" =~ ($COMPANION_PATTERN) ]]
}

has_tmux_subcmd() {
  [[ "$1" =~ tmux[[:space:]].*(capture-pane|list-panes|send-keys|select-pane|select-window|swap-pane) ]]
}

IFS='|' read -ra SEGMENTS <<< "$CMD"
for i in "${!SEGMENTS[@]}"; do
  seg="${SEGMENTS[$i]}"
  if has_tmux_subcmd "$seg" && has_companion_ref "$seg"; then
    deny
  fi
  if has_tmux_subcmd "$seg"; then
    for (( j=i+1; j<${#SEGMENTS[@]}; j++ )); do
      later="${SEGMENTS[$j]}"
      if [[ "$later" =~ (grep|rg) ]] && has_companion_ref "$later"; then
        deny
      fi
    done
  fi
done

exit 0
