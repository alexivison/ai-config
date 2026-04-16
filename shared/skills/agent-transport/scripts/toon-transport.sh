#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
Usage:
  toon-transport.sh encode-findings <input.json> <output.toon>
  toon-transport.sh decode <input.toon> [output.json]
  toon-transport.sh validate-findings <input.toon|input.json>
EOF
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Missing required command: $1" >&2
    exit 1
  fi
}

TMP_FILES=()
cleanup() {
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    rm -f "${TMP_FILES[@]}"
  fi
}
trap cleanup EXIT

validate_findings_json() {
  local input="$1"

  jq -e '
    type == "object" and
    (.findings | type == "array") and
    (.summary | type == "string") and
    (.stats | type == "object") and
    (.stats.blocking_count | type == "number" and floor == . and . >= 0) and
    (.stats.non_blocking_count | type == "number" and floor == . and . >= 0) and
    (.stats.files_reviewed | type == "number" and floor == . and . >= 0) and
    all(.findings[]?;
      type == "object" and
      ((keys | sort) == ["category", "description", "file", "id", "line", "severity", "suggestion"]) and
      (.id | type == "string" and length > 0) and
      (.file | type == "string" and length > 0) and
      (.line | type == "number" and floor == . and . >= 1) and
      (.severity | type == "string" and (. == "blocking" or . == "non-blocking")) and
      (.category | type == "string" and length > 0) and
      (.description | type == "string" and length > 0) and
      (.suggestion | type == "string" and length > 0)
    ) and
    (.stats.blocking_count == ([.findings[] | select(.severity == "blocking")] | length)) and
    (.stats.non_blocking_count == ([.findings[] | select(.severity == "non-blocking")] | length))
  ' "$input" >/dev/null
}

json_input_for() {
  local input="$1"
  local tmp_json

  if [[ "$input" == *.json ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  tmp_json="$(mktemp)"
  TMP_FILES+=("$tmp_json")
  if ! toon --decode "$input" >"$tmp_json"; then
    return 1
  fi
  printf '%s\n' "$tmp_json"
}

encode_findings() {
  local input_json="$1"
  local output_toon="$2"

  validate_findings_json "$input_json"
  toon --encode "$input_json" >"$output_toon"
}

decode_toon() {
  local input_toon="$1"
  local output_json="${2:-}"

  if [[ -n "$output_json" ]]; then
    toon --decode "$input_toon" >"$output_json"
  else
    toon --decode "$input_toon"
  fi
}

validate_findings() {
  local input="$1"
  local json_input

  json_input="$(json_input_for "$input")"
  validate_findings_json "$json_input"
}

main() {
  local cmd="${1:-}"

  require_cmd toon
  require_cmd jq

  case "$cmd" in
    encode-findings)
      [[ $# -eq 3 ]] || usage
      encode_findings "$2" "$3"
      ;;
    decode)
      [[ $# -eq 2 || $# -eq 3 ]] || usage
      decode_toon "$2" "${3:-}"
      ;;
    validate-findings)
      [[ $# -eq 2 ]] || usage
      validate_findings "$2"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
