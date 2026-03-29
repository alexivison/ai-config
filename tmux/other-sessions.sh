#!/bin/bash
# Show active party sessions in the tmux status bar.
# Displays other party-* sessions (not the current one) with titles
# from manifests when available, falling back to short IDs.
# Output: nothing if no other sessions, otherwise styled session list.

current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
others=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^party-' | grep -v "^${current}$")

[[ -z "$others" ]] && exit 0

state_root="${PARTY_STATE_ROOT:-$HOME/.party-state}"
parts=()
while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    # Default: short ID with long timestamps truncated to last 6 chars
    label="${sid##party-}"
    [[ ${#label} -gt 6 ]] && label="${label: -6}"

    manifest="$state_root/$sid.json"
    if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
        IFS=$'\t' read -r title stype < <(jq -r '[(.title // ""), (.session_type // "")] | @tsv' "$manifest" 2>/dev/null)
        [[ -n "$title" ]] && label="$title"
        [[ "$stype" == "master" ]] && label="$label*"
    fi
    parts+=("$label")
done <<< "$others"

[[ ${#parts[@]} -eq 0 ]] && exit 0

# Count includes current session if it's a party session
total=${#parts[@]}
[[ "$current" == party-* ]] && total=$((total + 1))

list=$(IFS='·'; echo "${parts[*]}")
printf '#[fg=#444c56] | #[fg=#768390]⚔ %d  %s ' "$total" "$list"
