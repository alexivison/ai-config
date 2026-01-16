#!/bin/bash

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'
C_GREEN='\033[38;5;71m'
C_BLUE='\033[38;5;74m'
C_BAR_EMPTY='\033[38;5;238m'

input=$(cat)

# Extract all fields from JSON in a single jq call for performance
IFS=$'\t' read -r model cwd transcript_path max_context < <(echo "$input" | jq -r '[
    .model.display_name // .model.id // "?",
    .cwd // "",
    .transcript_path // "",
    .context_window.context_window_size // 200000
] | @tsv')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch
branch=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
fi

# max_context already extracted above
# Calculate tokens from transcript (more accurate than total_input_tokens which
# excludes system prompt/tools/memory). See: github.com/anthropics/claude-code/issues/13652
max_k=$((max_context / 1000))

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_BLUE}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_BLUE}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}${pct_prefix}${pct}% of ${max_k}k tokens"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_BLUE}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_BLUE}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}% of ${max_k}k tokens"
fi

# Build output: Model | Dir | Branch | Context
output="${C_BLUE}${model}${C_GRAY} | ${dir}"
[[ -n "$branch" ]] && output+=" | ${C_GREEN}${branch}${C_GRAY}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"
