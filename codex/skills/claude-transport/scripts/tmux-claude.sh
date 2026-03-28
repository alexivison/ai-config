#!/usr/bin/env bash
# tmux-claude.sh — The Wizard's direct interface to Claude via tmux
# Replaces call_claude.sh
set -euo pipefail

MESSAGE="${1:?Usage: tmux-claude.sh \"message for Claude\"}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Resolve party-cli (on PATH, or via go run as fallback)
# ---------------------------------------------------------------------------
_party_cli() {
  if command -v party-cli &>/dev/null; then
    party-cli "$@"
    return
  fi
  local repo_root
  repo_root="${PARTY_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../.." 2>/dev/null && pwd)}"
  if command -v go &>/dev/null && [[ -f "$repo_root/tools/party-cli/main.go" ]]; then
    env "PARTY_REPO_ROOT=$repo_root" go -C "$repo_root/tools/party-cli" run . "$@"
    return
  fi
  echo "Error: party-cli not found." >&2
  return 1
}

# Discover session
eval "$(_party_cli session-env)"

# Register Codex's thread ID with the party session (write-once)
if [[ -n "${CODEX_THREAD_ID:-}" && ! -s "$STATE_DIR/codex-thread-id" ]]; then
  printf '%s\n' "$CODEX_THREAD_ID" > "$STATE_DIR/codex-thread-id"
  tmux set-environment -t "$SESSION_NAME" CODEX_THREAD_ID "$CODEX_THREAD_ID" 2>/dev/null || true

  # Persist to manifest for resume path (continue.go reads codex_thread_id)
  manifest="$STATE_FILE"
  if [[ -f "$manifest" ]] && command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/party-state.XXXXXX")"
    if jq --arg v "$CODEX_THREAD_ID" '.codex_thread_id = $v' "$manifest" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$manifest"
    else
      rm -f "$tmp"
    fi
  fi
fi

# Detect completion messages by prefix-anchored patterns matching actual call sites.
# Mid-task traffic (questions, status) does not match and leaves status unchanged.
_is_completion=false
case "$MESSAGE" in
  "Review complete. Findings at: "*)       _is_completion=true ;;
  "Plan review complete. Findings at: "*)  _is_completion=true ;;
  "Task complete. Response at: "*)         _is_completion=true ;;
esac

# Send via party-cli (role=claude, auto-discovers session)
_send_rc=0
_party_cli send --role claude --session "$SESSION_NAME" "[CODEX] $MESSAGE" || _send_rc=$?

if [[ $_send_rc -eq 0 || $_send_rc -eq 76 ]]; then
  if [[ $_send_rc -eq 76 ]]; then
    echo "send: delivery unconfirmed (capture-pane miss)" >&2
  fi
  if $_is_completion; then
    _verdict=""
    _findings_file=""
    if [[ "$MESSAGE" =~ Findings\ at:\ ([^[:space:]]+) ]]; then
      _findings_file="${BASH_REMATCH[1]}"
    elif [[ "$MESSAGE" =~ Response\ at:\ ([^[:space:]]+) ]]; then
      _findings_file="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$_findings_file" && -f "$_findings_file" ]]; then
      if grep -q '^VERDICT: APPROVED' "$_findings_file" 2>/dev/null; then
        _verdict="APPROVE"
      elif grep -q '^VERDICT: REQUEST_CHANGES' "$_findings_file" 2>/dev/null; then
        _verdict="REQUEST_CHANGES"
      elif grep -q '^VERDICT: NEEDS_DISCUSSION' "$_findings_file" 2>/dev/null; then
        _verdict="NEEDS_DISCUSSION"
      fi
    fi
    _status_args=(codex-status write --session "$SESSION_NAME")
    [[ -n "$_verdict" ]] && _status_args+=(--verdict "$_verdict")
    _status_args+=("idle")
    _party_cli "${_status_args[@]}"
  fi
  echo "CLAUDE_MESSAGE_SENT"
else
  if $_is_completion; then
    _party_cli codex-status write --session "$SESSION_NAME" --error "completion delivery failed: Claude pane busy" "error"
  fi
  echo "CLAUDE_MESSAGE_DROPPED"
fi
