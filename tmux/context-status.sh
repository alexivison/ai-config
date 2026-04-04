#!/usr/bin/env bash
# Context window widget for tmux status bar.
# Displays Claude context-remaining percentage.
#
# Usage (in tmux.conf):
#   #(~/Code/ai-party/tmux/context-status.sh)
#
# Data source:
#   Cache file written by status-line.sh (/tmp/ai-context-cache/claude-<pane>)

CACHE_DIR="/tmp/ai-context-cache"

# Color thresholds (tmux #[fg=...] style)
color_for_pct() {
    local pct="$1"
    if [[ $pct -le 5 ]]; then
        echo "#e5534b"   # red
    elif [[ $pct -le 15 ]]; then
        echo "#daaa3f"   # yellow
    else
        echo "#57ab5a"   # green
    fi
}

# Find the Claude pane in the current session via @party_role metadata.
pane_id=$(tmux list-panes -s -F '#{pane_id} #{@party_role}' 2>/dev/null \
    | awk '$2 == "claude" { print $1; exit }')
[[ -z "$pane_id" ]] && exit 0

# Build cache key matching status-line.sh: server hash + pane id.
socket_path=$(tmux display-message -p '#{socket_path}' 2>/dev/null)
server_hash=$(printf '%s' "$socket_path" | md5 -q 2>/dev/null || printf '%s' "$socket_path" | md5sum | cut -d' ' -f1)
server_hash="${server_hash:0:8}"

cache_file="$CACHE_DIR/claude-${server_hash}-${pane_id#%}"
[[ -f "$cache_file" ]] || exit 0

# Stale check: ignore if older than 10 minutes.
# Claude Code only writes on status changes (not on a timer), so short TTLs
# cause the widget to flicker during idle periods.
now=$(date +%s)
file_age=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null) || exit 0
(( now - file_age > 600 )) && exit 0

IFS=$'\t' read -r model pct < "$cache_file"
[[ -z "$pct" ]] && exit 0

c=$(color_for_pct "$pct")
printf '#[fg=#539bf5,bold]Paladin: #[fg=#768390,nobold]%s #[fg=%s,bold]%s%%#[fg=#444c56,nobold] | ' \
    "$model" "$c" "$pct"
