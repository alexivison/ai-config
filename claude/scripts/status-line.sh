#!/usr/bin/env bash
# Claude Code status line — context remaining percentage.

input=$(cat)

pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100')
pct=${pct%.*}
[[ -z "$pct" || "$pct" == "null" ]] && pct=100

echo "󰍛 ${pct}%"
