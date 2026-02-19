#!/usr/bin/env bash

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'
C_GREEN='\033[38;5;71m'
C_YELLOW='\033[38;5;178m'
C_RED='\033[38;5;167m'
C_BLUE='\033[38;5;74m'
C_BAR_EMPTY='\033[38;5;238m'

input=$(cat)

# Extract fields from JSON in a single jq call
IFS=$'\t' read -r model cwd remaining < <(echo "$input" | jq -r '[
    .model.display_name // .model.id // "?",
    .cwd // "",
    .context_window.remaining_percentage // 100
] | @tsv')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch
branch=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

# Build context bar from remaining_percentage
# Auto-compact triggers at 95% usage (5% remaining)
pct=${remaining%.*}
[[ -z "$pct" || "$pct" == "null" ]] && pct=100
[[ $pct -gt 100 ]] && pct=100
[[ $pct -lt 0 ]] && pct=0

# Color tiers: green (plenty) → yellow (warning) → red (near auto-compact)
if [[ $pct -le 5 ]]; then
    C_BAR=$C_RED
elif [[ $pct -le 15 ]]; then
    C_BAR=$C_YELLOW
else
    C_BAR=$C_GREEN
fi

bar_width=10
bar=""
for ((i=0; i<bar_width; i++)); do
    bar_start=$((i * 10))
    progress=$((pct - bar_start))
    if [[ $progress -ge 8 ]]; then
        bar+="${C_BAR}█${C_RESET}"
    elif [[ $progress -ge 3 ]]; then
        bar+="${C_BAR}▄${C_RESET}"
    else
        bar+="${C_BAR_EMPTY}░${C_RESET}"
    fi
done

ctx="${bar} ${C_GRAY}${pct}% remaining"

# Build output: Model | Dir | Branch | Context
output="${C_BLUE}${model}${C_GRAY} | ${dir}"
[[ -n "$branch" ]] && output+=" | ${C_GREEN}${branch}${C_GRAY}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"
