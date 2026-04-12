#!/bin/bash
# Show session counts in the tmux status bar.
# Party sessions: active/idle breakdown based on @party_state.
# Other sessions: count of non-party sessions (excluding current).
# Output: nothing if only the current session exists.

current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
all_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

party_active=0
party_idle=0
other_count=0
while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    if [[ "$sid" == party-* ]]; then
        # Read @party_state from the Claude pane.
        # Sidebar layout: window 1, pane 0. Classic layout: window 0, pane 1.
        state=$(tmux show-options -p -v -t "${sid}:1.0" @party_state 2>/dev/null)
        [[ -z "$state" ]] && state=$(tmux show-options -p -v -t "${sid}:0.1" @party_state 2>/dev/null)
        case "$state" in
            active|waiting) party_active=$((party_active + 1)) ;;
            *)              party_idle=$((party_idle + 1)) ;;
        esac
    elif [[ "$sid" != "$current" ]]; then
        other_count=$((other_count + 1))
    fi
done <<< "$all_sessions"

party_total=$((party_active + party_idle))
[[ $party_total -eq 0 && $other_count -eq 0 ]] && exit 0

output=""
if [[ $party_total -gt 0 ]]; then
    output="#[fg=#768390,bg=#343b45]⚔ "
    [[ $party_active -gt 0 ]] && output="${output}#[fg=#a3be8c,bg=#343b45]${party_active}⚡"
    [[ $party_idle -gt 0 ]]   && output="${output}#[fg=#555555,bg=#343b45]${party_idle}○"
fi
[[ $other_count -gt 0 ]] && output="${output:+$output  }#[fg=#768390,bg=#343b45]◈ ${other_count}"

[[ -z "$output" ]] && exit 0
# Pill-shaped segment matching SketchyBar theme
BAR_BG="#22272e"
PILL_BG="#343b45"
printf '#[fg=%s,bg=%s]#[bg=%s] %s #[fg=%s,bg=%s]' \
    "$PILL_BG" "$BAR_BG" "$PILL_BG" "$output" "$PILL_BG" "$BAR_BG"
