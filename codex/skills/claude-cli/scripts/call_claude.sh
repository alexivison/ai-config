#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  call_claude.sh [options] --prompt "..."
  call_claude.sh [options] --prompt-file /path/to/prompt.txt

Options:
  --model <model>                    Claude model alias/name (default: opus[1m])
  --effort <level>                   Reasoning effort (default: high)
  --tools <tools>                    Tool list for Claude (default: "")
  --permission-mode <mode>           Claude permission mode
  --output-format <fmt>              text|json|stream-json (default: text)
  --json-schema <schema>             JSON schema when output-format=json
  --max-budget-usd <amount>          Maximum budget for the request
  --add-dir <dir>                    Additional directory access (repeatable)
  --prompt <text>                    Inline prompt text
  --prompt-file <path>               File containing prompt text
  -h, --help                         Show this help

Examples:
  call_claude.sh --prompt "Summarize these notes: ..."
  call_claude.sh --tools Read --permission-mode bypassPermissions \
    --prompt "Review PLAN.md and return verdict with file:line findings."
EOF
}

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: 'claude' CLI not found in PATH." >&2
  echo "Install: curl -fsSL https://cli.anthropic.com/install.sh | sh" >&2
  exit 1
fi

MODEL="opus[1m]"
EFFORT="high"
TOOLS=""
PERMISSION_MODE=""
OUTPUT_FORMAT="text"
JSON_SCHEMA=""
MAX_BUDGET_USD=""
PROMPT=""
PROMPT_FILE=""
declare -a ADD_DIRS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --effort)
      EFFORT="${2:-}"
      shift 2
      ;;
    --tools)
      TOOLS="${2-}"
      shift 2
      ;;
    --permission-mode)
      PERMISSION_MODE="${2:-}"
      shift 2
      ;;
    --output-format)
      OUTPUT_FORMAT="${2:-}"
      shift 2
      ;;
    --json-schema)
      JSON_SCHEMA="${2:-}"
      shift 2
      ;;
    --max-budget-usd)
      MAX_BUDGET_USD="${2:-}"
      shift 2
      ;;
    --add-dir)
      ADD_DIRS+=("${2:-}")
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

if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
  echo "Error: Use either --prompt or --prompt-file, not both." >&2
  exit 1
fi

if [[ -z "$PROMPT" && -z "$PROMPT_FILE" ]]; then
  echo "Error: One of --prompt or --prompt-file is required." >&2
  exit 1
fi

if [[ -n "$PROMPT_FILE" ]]; then
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file not found: $PROMPT_FILE" >&2
    exit 1
  fi
  PROMPT="$(cat "$PROMPT_FILE")"
fi

cmd=(
  claude
  -p
  --model "$MODEL"
  --effort "$EFFORT"
  --disable-slash-commands
  --tools "$TOOLS"
  --output-format "$OUTPUT_FORMAT"
)

if [[ -n "$PERMISSION_MODE" ]]; then
  cmd+=(--permission-mode "$PERMISSION_MODE")
fi

if [[ -n "$JSON_SCHEMA" ]]; then
  cmd+=(--json-schema "$JSON_SCHEMA")
fi

if [[ -n "$MAX_BUDGET_USD" ]]; then
  cmd+=(--max-budget-usd "$MAX_BUDGET_USD")
fi

for dir in "${ADD_DIRS[@]}"; do
  cmd+=(--add-dir "$dir")
done

cmd+=("$PROMPT")
"${cmd[@]}"
