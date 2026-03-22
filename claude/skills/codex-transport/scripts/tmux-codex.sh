#!/usr/bin/env bash
# tmux-codex.sh — Claude's direct interface to Codex via tmux
set -euo pipefail

MODE="${1:?Usage: tmux-codex.sh --review|--plan-review|--prompt|--review-complete|--needs-discussion}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
source "$SCRIPT_DIR/../../../../session/party-lib.sh"

# Render a template file by replacing {{VAR}} placeholders.
# Args: template_file [VAR=value ...]
_render_template() {
  local template_file="$1"; shift
  local content
  content=$(cat "$template_file")
  local key val
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    content="${content//\{\{$key\}\}/$val}"
  done
  # Strip lines that are just unreplaced placeholders (conditional sections not filled)
  echo "$content" | grep -v '^{{.*}}$'
}

# Session discovery only for modes that need tmux (--review, --prompt).
# Evidence/escalation modes (--review-complete, --needs-discussion)
# only emit sentinel strings and work without a party session.
_require_session() {
  discover_session
  # Master sessions have no Codex pane — guard early
  if party_is_master "$SESSION_NAME" 2>/dev/null; then
    echo "CODEX_NOT_AVAILABLE: Master sessions have no Codex pane. Route review work through a worker session." >&2
    exit 1
  fi
  CODEX_PANE=$(party_codex_pane_target "$SESSION_NAME") || {
    echo "Error: Cannot resolve Codex pane in session '$SESSION_NAME'" >&2
    exit 1
  }
}

# Delivery-confirmed send. Exit 76 (keys sent but buffer check failed)
# is treated as success — the keys were delivered, capture-pane just
# couldn't confirm. Retrying would cause duplicate dispatch.
# Returns 0 on success/unconfirmed, 75 on pane busy (dropped).
_send_with_retry() {
  local target="$1" text="$2" caller="$3"
  local rc=0
  tmux_send "$target" "$text" "$caller" || rc=$?
  if [[ $rc -eq 76 ]]; then
    # Keys were sent, buffer verification failed — treat as delivered
    echo "tmux_send: delivery unconfirmed for '$caller' (capture-pane miss)" >&2
    return 0
  fi
  return $rc
}

case "$MODE" in

  --review)
    _require_session
    shift # consume --review
    # Parse flags and positional args
    _review_scope=""
    _review_dispute=""
    _review_prior=""
    _review_positional=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --scope) _review_scope="${2:?--scope requires a value}"; shift 2 ;;
        --dispute) _review_dispute="${2:?--dispute requires a file path}"; shift 2 ;;
        --prior-findings) _review_prior="${2:?--prior-findings requires a file path}"; shift 2 ;;
        *) _review_positional+=("$1"); shift ;;
      esac
    done
    WORK_DIR="${_review_positional[0]:?Missing work_dir — pass the worktree/repo path}"
    BASE="${_review_positional[1]:-main}"
    TITLE="${_review_positional[2]:-Code review}"
    FINDINGS_FILE="$STATE_DIR/codex-findings-$(date +%s%N).toon"

    NOTIFY_SCRIPT="$(cd "$SCRIPT_DIR/../../../../codex/skills/claude-transport/scripts" && pwd)/tmux-claude.sh"
    NOTIFY_CMD="$NOTIFY_SCRIPT \"Review complete. Findings at: $FINDINGS_FILE\""

    # Build conditional sections (printf for real newlines)
    SCOPE_SECTION=""
    if [[ -n "$_review_scope" ]]; then
      SCOPE_SECTION=$(printf '## Scope\n\nOnly review changes within this scope: %s\nFindings outside this scope should be classified as out-of-scope and omitted.' "$_review_scope")
    fi
    DISPUTE_SECTION=""
    if [[ -n "$_review_dispute" && -f "$_review_dispute" ]]; then
      DISPUTE_SECTION=$(printf '## Dispute Context\n\nRead dismissed findings and rationales from: %s\nFor each dismissed finding: accept if the rationale is valid (drop from findings), or challenge with a specific file:line reference if invalid. Do NOT re-raise accepted dismissals.' "$_review_dispute")
    fi
    REREVEW_SECTION=""
    if [[ -n "$_review_prior" && -f "$_review_prior" ]]; then
      REREVEW_SECTION=$(printf '## Re-review\n\nThis is a re-review. Prior findings at: %s\nFocus on whether blocking issues were addressed. Do NOT re-raise findings that were already fixed. Flag only genuinely NEW issues.' "$_review_prior")
    fi

    MSG=$(_render_template "$TEMPLATE_DIR/review.md" \
      "WORK_DIR=$WORK_DIR" \
      "BASE=$BASE" \
      "TITLE=$TITLE" \
      "FINDINGS_FILE=$FINDINGS_FILE" \
      "NOTIFY_CMD=$NOTIFY_CMD" \
      "SCOPE_SECTION=$SCOPE_SECTION" \
      "DISPUTE_SECTION=$DISPUTE_SECTION" \
      "REREVEW_SECTION=$REREVEW_SECTION")

    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    if _send_with_retry "$CODEX_PANE" "$MSG" "tmux-codex.sh:review"; then
      write_codex_status "$RUNTIME_DIR" "working" "$BASE" "review"
      echo "CODEX_REVIEW_REQUESTED"
      echo "Claude is NOT blocked. Codex will notify via tmux when complete."
    else
      write_codex_status "$RUNTIME_DIR" "error" "" "" "" "review dispatch failed: pane busy"
      echo "CODEX_REVIEW_DROPPED"
      echo "Codex pane is busy. Message dropped (best-effort delivery)."
    fi
    echo "Findings will be written to: $FINDINGS_FILE"
    echo "Working directory: $WORK_DIR"
    ;;

  --plan-review)
    _require_session
    PLAN_PATH="${2:?Missing plan path}"
    WORK_DIR="${3:?Missing work_dir — pass the worktree/repo path as 3rd argument}"
    FINDINGS_FILE="$STATE_DIR/codex-plan-findings-$(date +%s%N).toon"

    NOTIFY_SCRIPT="$(cd "$SCRIPT_DIR/../../../../codex/skills/claude-transport/scripts" && pwd)/tmux-claude.sh"
    NOTIFY_CMD="$NOTIFY_SCRIPT \"Plan review complete. Findings at: $FINDINGS_FILE\""

    MSG=$(_render_template "$TEMPLATE_DIR/plan-review.md" \
      "WORK_DIR=$WORK_DIR" \
      "PLAN_PATH=$PLAN_PATH" \
      "FINDINGS_FILE=$FINDINGS_FILE" \
      "NOTIFY_CMD=$NOTIFY_CMD")

    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    if _send_with_retry "$CODEX_PANE" "$MSG" "tmux-codex.sh:plan-review"; then
      write_codex_status "$RUNTIME_DIR" "working" "$PLAN_PATH" "plan-review"
      echo "CODEX_PLAN_REVIEW_REQUESTED"
      echo "Claude is NOT blocked. Codex will notify via tmux when complete."
    else
      write_codex_status "$RUNTIME_DIR" "error" "" "" "" "plan-review dispatch failed: pane busy"
      echo "CODEX_PLAN_REVIEW_DROPPED"
      echo "Codex pane is busy. Message dropped (best-effort delivery)."
    fi
    echo "Findings will be written to: $FINDINGS_FILE"
    echo "Working directory: $WORK_DIR"
    ;;

  --prompt)
    _require_session
    PROMPT_TEXT="${2:?Missing prompt text}"
    WORK_DIR="${3:?Missing work_dir — pass the worktree/repo path as 3rd argument}"
    RESPONSE_FILE="$STATE_DIR/codex-response-$(date +%s%N).toon"

    NOTIFY_SCRIPT="$(cd "$SCRIPT_DIR/../../../../codex/skills/claude-transport/scripts" && pwd)/tmux-claude.sh"

    MSG="[CLAUDE] cd '$WORK_DIR' && $PROMPT_TEXT — Write response to: $RESPONSE_FILE — When done, run: $NOTIFY_SCRIPT \"Task complete. Response at: $RESPONSE_FILE\""
    RUNTIME_DIR="$(party_runtime_dir "$SESSION_NAME")"
    if _send_with_retry "$CODEX_PANE" "$MSG" "tmux-codex.sh:prompt"; then
      write_codex_status "$RUNTIME_DIR" "working" "$PROMPT_TEXT" "prompt"
      echo "CODEX_TASK_REQUESTED"
      echo "Codex will notify via tmux when complete."
    else
      write_codex_status "$RUNTIME_DIR" "error" "" "" "" "prompt dispatch failed: pane busy"
      echo "CODEX_TASK_DROPPED"
      echo "Codex pane is busy. Message dropped (best-effort delivery)."
    fi
    echo "Response will be written to: $RESPONSE_FILE"
    echo "Working directory: $WORK_DIR"
    ;;

  --review-complete)
    FINDINGS_FILE="${2:?Missing findings file path}"
    if [[ ! -f "$FINDINGS_FILE" ]]; then
      echo "Error: Findings file not found: $FINDINGS_FILE" >&2
      exit 1
    fi
    echo "CODEX_REVIEW_RAN"
    # Parse verdict from findings file (written by Codex, not the worker).
    # Only Codex writes the findings file, so this verdict is trustworthy.
    if grep -qx 'VERDICT: APPROVED' "$FINDINGS_FILE"; then
      echo "CODEX APPROVED"
    elif grep -qx 'VERDICT: REQUEST_CHANGES' "$FINDINGS_FILE"; then
      echo "CODEX REQUEST_CHANGES"
    else
      echo "WARNING: No verdict line found in findings file. Review ran but no approval granted." >&2
      echo "CODEX VERDICT_MISSING"
    fi
    ;;

  --approve)
    echo "Error: --approve is deprecated. Codex approval flows through --review-complete," >&2
    echo "which reads the VERDICT line from the findings file Codex wrote." >&2
    echo "Do not self-approve. Use: tmux-codex.sh --review-complete <findings_file>" >&2
    exit 1
    ;;

  --needs-discussion)
    REASON="${2:-Multiple valid approaches or unresolvable findings}"
    echo "CODEX NEEDS_DISCUSSION — $REASON"
    ;;

  --triage-override)
    TYPE="${2:?Usage: tmux-codex.sh --triage-override <type> <rationale>}"
    RATIONALE="${3:?Usage: tmux-codex.sh --triage-override <type> <rationale>}"
    echo "TRIAGE_OVERRIDE $TYPE | $RATIONALE"
    ;;

  *)
    echo "Error: Unknown mode '$MODE'" >&2
    echo "Usage: tmux-codex.sh --review|--plan-review|--prompt|--review-complete|--needs-discussion|--triage-override" >&2
    exit 1
    ;;
esac
