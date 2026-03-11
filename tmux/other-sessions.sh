#!/bin/bash
# Show other tmux sessions (dimmed, next to the active session pill)
current=$(tmux display-message -p '#{session_name}')
tmux list-sessions -F '#{session_name}' | grep -v "^${current}$" | paste -sd '·' -
