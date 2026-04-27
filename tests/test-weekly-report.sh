#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/claude/scripts/weekly-report.sh"

PASS=0
FAIL=0

assert() {
  local desc="$1"
  if eval "$2"; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $desc"
  fi
}

TMP_HOME="$(mktemp -d /tmp/weekly-report-test-XXXXXX)"
MOCK_BIN_DIR="$TMP_HOME/bin"
TODAY="$(date +%F)"
CURRENT_WEEK="$(date +%G-W%V)"
NOTE_PATH="$TMP_HOME/.ai-party/docs/research/$TODAY-script-path-smoke.md"
NEW_EXPORT_DIR="$TMP_HOME/.ai-party/docs/reports/$CURRENT_WEEK"
OLD_EXPORT_DIR="$TMP_HOME/Documents/Claude-Reports/$CURRENT_WEEK"

cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

mkdir -p \
  "$MOCK_BIN_DIR" \
  "$TMP_HOME/.ai-party/docs/research" \
  "$TMP_HOME/.claude/investigations" \
  "$TMP_HOME/.claude/scripts" \
  "$TMP_HOME/Documents/Claude-Reports" \
  "$TMP_HOME/Code"

cat > "$MOCK_BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
echo "[]"
EOF
chmod +x "$MOCK_BIN_DIR/gh"

cat > "$NOTE_PATH" <<'EOF'
# Script Path Smoke

Validates the weekly report script reads from the canonical research directory.
EOF

RUN_LOG="$TMP_HOME/run.log"
if HOME="$TMP_HOME" PATH="$MOCK_BIN_DIR:$PATH" bash "$SCRIPT" 0 >"$RUN_LOG" 2>&1; then
  STATUS=0
else
  STATUS=$?
fi

echo "--- test-weekly-report.sh ---"

assert "weekly-report.sh exits successfully" \
  '[ "$STATUS" -eq 0 ]'

assert "writes reports under ~/.ai-party/docs/reports" \
  '[ -d "$NEW_EXPORT_DIR" ]'

assert "does not write reports under ~/Documents/Claude-Reports" \
  '[ ! -d "$OLD_EXPORT_DIR" ]'

assert "copies research notes from ~/.ai-party/docs/research" \
  '[ -f "$NEW_EXPORT_DIR/$(basename "$NOTE_PATH")" ]'

assert "summary links the copied research note" \
  'grep -q "Script Path Smoke" "$NEW_EXPORT_DIR/SUMMARY.md"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
