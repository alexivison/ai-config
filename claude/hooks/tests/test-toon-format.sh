#!/usr/bin/env bash
# Lightweight TOON findings-format sanity checks.
set -euo pipefail

if ! command -v toon &>/dev/null; then
  echo "SKIP: toon CLI not available"
  exit 0
fi

PASS=0
FAIL=0
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HELPER="$REPO_ROOT/shared/references/agent-transport/scripts/toon-transport.sh"

assert() {
  local desc="$1" condition="$2"
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $desc"
  fi
}

write_temp() {
  local tmp_file
  tmp_file="$(mktemp)"
  cat >"$tmp_file"
  echo "$tmp_file"
}

echo "--- test-toon-format.sh ---"

TOON_VALID=$(cat <<'TOON_EOF'
findings[2]{id,file,line,severity,category,description,suggestion}:
  F1,src/app.ts,10,blocking,correctness,"Missing null check","Add guard clause"
  F2,src/util.ts,25,non-blocking,style,"Inconsistent naming","Rename to camelCase"
summary: Two findings across two files
stats:
  blocking_count: 1
  non_blocking_count: 1
  files_reviewed: 2
TOON_EOF
)

TOON_BAD_COUNT=$(cat <<'TOON_EOF'
findings[3]{id,file,line,severity,category,description,suggestion}:
  F1,src/app.ts,10,blocking,correctness,"Missing null check","Add guard clause"
  F2,src/util.ts,25,non-blocking,style,"Inconsistent naming","Rename to camelCase"
summary: Row count mismatch
stats:
  blocking_count: 1
  non_blocking_count: 1
  files_reviewed: 2
TOON_EOF
)

TOON_BAD_HEADER=$(cat <<'TOON_EOF'
findings[2]{id,file,severity,category,description,suggestion}:
  F1,src/app.ts,blocking,correctness,"Missing null check","Add guard clause"
  F2,src/util.ts,non-blocking,style,"Inconsistent naming","Rename to camelCase"
summary: Missing line field in header
stats:
  blocking_count: 1
  non_blocking_count: 1
  files_reviewed: 2
TOON_EOF
)

TOON_ZERO=$(cat <<'TOON_EOF'
findings[0]{id,file,line,severity,category,description,suggestion}:
summary: No findings
stats:
  blocking_count: 0
  non_blocking_count: 0
  files_reviewed: 2
TOON_EOF
)

JSON_VALID=$(cat <<'JSON_EOF'
{
  "findings": [
    {
      "id": "F1",
      "file": "src/app.ts",
      "line": 10,
      "severity": "blocking",
      "category": "correctness",
      "description": "Missing null check, then crash",
      "suggestion": "Add guard clause, then test"
    },
    {
      "id": "F2",
      "file": "src/util.ts",
      "line": 25,
      "severity": "non-blocking",
      "category": "style",
      "description": "Inconsistent naming",
      "suggestion": "Rename to camelCase"
    }
  ],
  "summary": "Two findings across two files",
  "stats": {
    "blocking_count": 1,
    "non_blocking_count": 1,
    "files_reviewed": 2
  }
}
JSON_EOF
)

JSON_BAD_STATS=$(cat <<'JSON_EOF'
{
  "findings": [
    {
      "id": "F1",
      "file": "src/app.ts",
      "line": 10,
      "severity": "blocking",
      "category": "correctness",
      "description": "Missing null check",
      "suggestion": "Add guard clause"
    }
  ],
  "summary": "Bad stats",
  "stats": {
    "blocking_count": 0,
    "non_blocking_count": 1,
    "files_reviewed": 1
  }
}
JSON_EOF
)

TOON_VALID_FILE="$(printf '%s\n' "$TOON_VALID" | write_temp)"
TOON_BAD_COUNT_FILE="$(printf '%s\n' "$TOON_BAD_COUNT" | write_temp)"
TOON_BAD_HEADER_FILE="$(printf '%s\n' "$TOON_BAD_HEADER" | write_temp)"
TOON_ZERO_FILE="$(printf '%s\n' "$TOON_ZERO" | write_temp)"
JSON_VALID_FILE="$(printf '%s\n' "$JSON_VALID" | write_temp)"
JSON_BAD_STATS_FILE="$(printf '%s\n' "$JSON_BAD_STATS" | write_temp)"
ENCODED_FILE="$(mktemp)"
DECODED_FILE="$(mktemp)"
trap 'rm -f "$TOON_VALID_FILE" "$TOON_BAD_COUNT_FILE" "$TOON_BAD_HEADER_FILE" "$TOON_ZERO_FILE" "$JSON_VALID_FILE" "$JSON_BAD_STATS_FILE" "$ENCODED_FILE" "$DECODED_FILE"' EXIT

assert "TOON sanity check passes on valid sample" \
  'bash "$HELPER" validate-findings "$TOON_VALID_FILE"'
assert "TOON sanity check fails on row-count mismatch" \
  '! bash "$HELPER" validate-findings "$TOON_BAD_COUNT_FILE" 2>/dev/null'
assert "TOON sanity check fails on invalid header fields" \
  '! bash "$HELPER" validate-findings "$TOON_BAD_HEADER_FILE" 2>/dev/null'
assert "TOON sanity check passes on zero findings" \
  'bash "$HELPER" validate-findings "$TOON_ZERO_FILE"'
assert "Helper encodes canonical findings JSON to TOON" \
  'bash "$HELPER" encode-findings "$JSON_VALID_FILE" "$ENCODED_FILE" && bash "$HELPER" validate-findings "$ENCODED_FILE"'
assert "Helper decodes TOON back to canonical JSON" \
  'bash "$HELPER" decode "$ENCODED_FILE" "$DECODED_FILE" && diff -u <(jq -S . "$JSON_VALID_FILE") <(jq -S . "$DECODED_FILE")'
assert "Helper rejects inconsistent JSON stats before encoding" \
  '! bash "$HELPER" encode-findings "$JSON_BAD_STATS_FILE" "$ENCODED_FILE" 2>/dev/null'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
