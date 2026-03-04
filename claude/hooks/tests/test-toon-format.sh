#!/usr/bin/env bash
# Lightweight TOON findings-format sanity checks.
set -euo pipefail

PASS=0
FAIL=0

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

toon_validate() {
  local input="$1"
  local header declared actual

  header=$(echo "$input" | head -1)
  if ! echo "$header" | grep -qE '^findings\[[0-9]+\]\{id,file,line,severity,category,description,suggestion\}:$'; then
    return 1
  fi

  declared=$(echo "$header" | grep -oE '\[[0-9]+\]' | tr -d '[]')
  actual=$(echo "$input" | tail -n +2 | grep -cE '^ +F[0-9]+,' || echo 0)
  [ "$declared" -eq "$actual" ]
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

assert "TOON sanity check passes on valid sample" \
  'toon_validate "$TOON_VALID"'
assert "TOON sanity check fails on row-count mismatch" \
  '! toon_validate "$TOON_BAD_COUNT"'
assert "TOON sanity check fails on invalid header fields" \
  '! toon_validate "$TOON_BAD_HEADER"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
