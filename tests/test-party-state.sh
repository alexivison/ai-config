#!/usr/bin/env bash
# Tests for party session runtime state + persisted manifest helpers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/session/party-lib.sh"

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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found; skipping test-party-state.sh"
  exit 0
fi

SESSION="party-test-state-$$"
export PARTY_SESSION="$SESSION"
export PARTY_STATE_ROOT="/tmp/party-state-root-$$"

cleanup() {
  rm -rf "/tmp/$SESSION" "$PARTY_STATE_ROOT"
}
trap cleanup EXIT

echo "--- test-party-state.sh ---"

STATE_DIR_CREATED="$(ensure_party_state_dir "$SESSION")"
assert "ensure_party_state_dir creates runtime directory" \
  '[ -d "$STATE_DIR_CREATED" ]'
assert "ensure_party_state_dir writes session-name file" \
  '[ "$(cat "$STATE_DIR_CREATED/session-name")" = "$SESSION" ]'

party_state_upsert_manifest "$SESSION" "My Party" "/tmp/project" "party (My Party)" "/bin/claude" "/bin/codex" "/usr/bin"
MANIFEST_FILE="$(party_state_file "$SESSION")"
assert "party_state_upsert_manifest creates manifest file" \
  '[ -f "$MANIFEST_FILE" ]'
assert "manifest stores cwd" \
  '[ "$(party_state_get_field "$SESSION" "cwd")" = "/tmp/project" ]'

party_state_set_field "$SESSION" "claude_session_id" "claude-123"
party_state_set_field "$SESSION" "codex_thread_id" "codex-456"
assert "party_state_set_field stores claude session id" \
  '[ "$(party_state_get_field "$SESSION" "claude_session_id")" = "claude-123" ]'
assert "party_state_set_field stores codex thread id" \
  '[ "$(party_state_get_field "$SESSION" "codex_thread_id")" = "codex-456" ]'

# --- party_state_delete_field ---
UPDATED_BEFORE="$(jq -r '.updated_at' "$MANIFEST_FILE")"
sleep 1
party_state_delete_field "$SESSION" "codex_thread_id"
assert "delete_field removes existing key" \
  '[ -z "$(party_state_get_field "$SESSION" "codex_thread_id" 2>/dev/null)" ]'
assert "delete_field preserves other keys" \
  '[ "$(party_state_get_field "$SESSION" "claude_session_id")" = "claude-123" ]'
UPDATED_AFTER="$(jq -r '.updated_at' "$MANIFEST_FILE")"
assert "delete_field updates updated_at" \
  '[ "$UPDATED_AFTER" != "$UPDATED_BEFORE" ]'

party_state_delete_field "$SESSION" "nonexistent_key"
RC_MISSING_KEY=$?
assert "delete_field on missing key returns 0 (idempotent)" \
  '[ "$RC_MISSING_KEY" -eq 0 ]'

DELETE_SESSION="party-test-nofile-$$"
party_state_delete_field "$DELETE_SESSION" "any_key"
RC_MISSING_FILE=$?
assert "delete_field on missing file returns 0" \
  '[ "$RC_MISSING_FILE" -eq 0 ]'

rm -rf "/tmp/$SESSION"
discover_session >/dev/null 2>&1
assert "discover_session self-heals missing runtime state dir" \
  '[ -f "/tmp/$SESSION/session-name" ]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
