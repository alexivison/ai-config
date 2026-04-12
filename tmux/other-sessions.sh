#!/bin/bash
# Show session counts in the tmux status bar.
# Party sessions: active/idle breakdown based on @party_state.
# Other sessions: count of non-party sessions (excluding current).
# Output: nothing if only the current session exists.

current=$(tmux display-message -p '#{session_name}' 2>/dev/null)
all_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

party_active=0
party_idle=0
other_active=0
other_idle=0
while IFS= read -r sid; do
    [[ -z "$sid" ]] && continue
    if [[ "$sid" == party-* ]]; then
        # Find the Claude pane by @party_role and read its @party_state.
        state=""
        while IFS=$'\t' read -r target role; do
            [[ "$role" == "claude" ]] && { state=$(tmux show-options -p -v -t "$target" @party_state 2>/dev/null); break; }
        done < <(tmux list-panes -s -t "$sid" -F '#{pane_id}	#{@party_role}' 2>/dev/null)
        case "$state" in
            active|waiting) party_active=$((party_active + 1)) ;;
            *)              party_idle=$((party_idle + 1)) ;;
        esac
    elif [[ "$sid" != "$current" ]]; then
        # Check if any pane is running claude (active) or just a shell (idle)
        if tmux list-panes -s -t "$sid" -F '#{pane_current_command}' 2>/dev/null | grep -q 'claude'; then
            other_active=$((other_active + 1))
        else
            other_idle=$((other_idle + 1))
        fi
    fi
done <<< "$all_sessions"

party_total=$((party_active + party_idle))
other_total=$((other_active + other_idle))
[[ $party_total -eq 0 && $other_total -eq 0 ]] && exit 0

output=""
if [[ $party_total -gt 0 ]]; then
    output="#[fg=#768390,bg=#343b45]⚔ "
    [[ $party_active -gt 0 ]] && output="${output}#[fg=#a3be8c,bg=#343b45]${party_active}▸"
    [[ $party_idle -gt 0 ]]   && output="${output}#[fg=#768390,bg=#343b45]${party_idle}"
fi
if [[ $other_total -gt 0 ]]; then
    output="${output:+$output  }#[fg=#768390,bg=#343b45]◈ "
    [[ $other_active -gt 0 ]] && output="${output}#[fg=#a3be8c,bg=#343b45]${other_active}▸"
    [[ $other_idle -gt 0 ]]   && output="${output}#[fg=#768390,bg=#343b45]${other_idle}"
fi

[[ -z "$output" ]] && exit 0
# Pill-shaped segment matching SketchyBar theme
BAR_BG="#22272e"
PILL_BG="#343b45"
printf '#[fg=%s,bg=%s]#[bg=%s] %s #[fg=%s,bg=%s]' \
    "$PILL_BG" "$BAR_BG" "$PILL_BG" "$output" "$PILL_BG" "$BAR_BG"
