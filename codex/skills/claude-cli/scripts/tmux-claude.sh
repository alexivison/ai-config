#!/usr/bin/env bash
# tmux-claude.sh — Codex's direct interface to Claude via tmux
# Replaces call_claude.sh
set -euo pipefail

MESSAGE="${1:?Usage: tmux-claude.sh \"message for Claude\"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"
discover_session

CLAUDE_PANE="$SESSION_NAME:work.0"

tmux_send "$CLAUDE_PANE" "[CODEX] $MESSAGE"

echo "CLAUDE_MESSAGE_SENT"
