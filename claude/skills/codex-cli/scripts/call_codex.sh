#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  call_codex.sh --review [options]
  call_codex.sh [options] --prompt "..."
  call_codex.sh [options] --prompt-file /path/to/prompt.txt

Options:
  --review                           Switch to review mode (codex exec review)
  --base <branch>                    Base branch for review (default: main)
  --title <text>                     Change summary for review context
  --sandbox <mode>                   Sandbox level (default: read-only)
  --prompt <text>                    Inline prompt text
  --prompt-file <path>               File containing prompt text
  --timeout <seconds>                Script-level timeout (default: 300)
  -h, --help                         Show this help

Examples:
  call_codex.sh --review --base main --title "Add auth middleware"
  call_codex.sh --prompt "TASK: Architecture analysis. SCOPE: src/. OUTPUT: Findings."
  call_codex.sh --prompt-file /tmp/review-prompt.txt
EOF
}

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: 'codex' CLI not found in PATH." >&2
  echo "Install: npm install -g @openai/codex" >&2
  exit 1
fi

# Portable timeout wrapper: gtimeout (Homebrew) > timeout (Linux) > perl (macOS builtin)
TIMEOUT_CMD=""
TIMEOUT_STYLE="gnu"  # "gnu" for gtimeout/timeout, "perl" for perl fallback
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v perl >/dev/null 2>&1; then
  TIMEOUT_CMD="perl"
  TIMEOUT_STYLE="perl"
else
  echo "Error: no timeout mechanism available (need gtimeout, timeout, or perl)." >&2
  exit 1
fi

MODE="exec"
BASE="main"
TITLE=""
SANDBOX="read-only"
PROMPT=""
PROMPT_FILE=""
TIMEOUT=300

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review)
      MODE="review"
      shift
      ;;
    --base)
      BASE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --sandbox)
      SANDBOX="${2:-}"
      shift 2
      ;;
    --prompt)
      PROMPT="${2-}"
      shift 2
      ;;
    --prompt-file)
      PROMPT_FILE="${2:-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Build timeout prefix
TIMEOUT_PREFIX=()
if [[ "$TIMEOUT_STYLE" = "perl" ]]; then
  TIMEOUT_PREFIX=(perl -e "alarm($TIMEOUT); exec @ARGV" --)
else
  TIMEOUT_PREFIX=("$TIMEOUT_CMD" "${TIMEOUT}s")
fi

# Enforce read-only sandbox — never allow write access during analysis
if [[ "$SANDBOX" != "read-only" ]]; then
  echo "Error: Sandbox must be 'read-only'. Got '$SANDBOX'." >&2
  exit 1
fi

if [[ "$MODE" = "review" ]]; then
  # Review mode — uses codex exec review with built-in review logic
  cmd=("${TIMEOUT_PREFIX[@]}" codex exec review --base "$BASE" --json)
  if [[ -n "$TITLE" ]]; then
    cmd+=(--title "$TITLE")
  fi
  "${cmd[@]}" 2>/dev/null \
    | jq -rs '[.[] | select(.item.type == "agent_message")] | last | .item.text'
else
  # Exec mode — structured prompt required
  if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
    echo "Error: Use either --prompt or --prompt-file, not both." >&2
    exit 1
  fi

  if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
    echo "Error: One of --prompt or --prompt-file is required in exec mode." >&2
    exit 1
  fi

  if [[ -n "$PROMPT_FILE" ]]; then
    if [[ ! -f "$PROMPT_FILE" ]]; then
      echo "Error: Prompt file not found: $PROMPT_FILE" >&2
      exit 1
    fi
    PROMPT="$(cat "$PROMPT_FILE")"
  fi

  "${TIMEOUT_PREFIX[@]}" codex exec -s "$SANDBOX" "$PROMPT"
fi
