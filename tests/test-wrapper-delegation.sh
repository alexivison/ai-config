#!/usr/bin/env bash
# Tests that bash wrappers delegate to party-cli instead of using built-in logic.
# RED phase: these tests will fail until the wrappers are thinned.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# --- Setup: mock party-cli that logs invocations ---
MOCK_DIR="/tmp/party-wrapper-test-$$"
MOCK_LOG="$MOCK_DIR/party-cli-calls.log"
MOCK_BIN="$MOCK_DIR/party-cli"

cleanup() {
  rm -rf "$MOCK_DIR"
}
trap cleanup EXIT

mkdir -p "$MOCK_DIR"
cat > "$MOCK_BIN" << 'MOCKEOF'
#!/usr/bin/env bash
echo "$@" >> "${PARTY_CLI_LOG:?}"
# For commands that parse stdout, output minimal valid data
case "$1" in
  start)  echo "Party session 'party-mock-123' started." ;;
  list)   echo "No party sessions found." ;;
  stop)   echo "Stopped: ${2:-all}" ;;
  delete) echo "Deleted: ${2:-}" ;;
  prune)  echo "Pruned." ;;
  promote) echo "Promoted." ;;
  picker) echo "" ;;
  workers) echo "No workers." ;;
  broadcast) echo "Broadcast sent." ;;
  read)   echo "(pane content)" ;;
  report) echo "Report sent." ;;
  relay)  echo "Relayed." ;;
esac
exit 0
MOCKEOF
chmod +x "$MOCK_BIN"

export PATH="$MOCK_DIR:$PATH"
export PARTY_CLI_LOG="$MOCK_LOG"

# Prevent tmux calls from interfering
export TMUX=""
export PARTY_SESSION=""

echo "--- test-wrapper-delegation.sh ---"

# ---- party.sh --list delegates to party-cli list ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --list 2>/dev/null || true
assert "party.sh --list delegates to party-cli" \
  'grep -q "^list" "$MOCK_LOG"'

# ---- party.sh --stop <id> delegates to party-cli stop ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --stop party-test-123 2>/dev/null || true
assert "party.sh --stop delegates to party-cli" \
  'grep -q "^stop party-test-123" "$MOCK_LOG"'

# ---- party.sh --delete <id> delegates to party-cli delete ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --delete party-test-123 2>/dev/null || true
assert "party.sh --delete delegates to party-cli" \
  'grep -q "^delete party-test-123" "$MOCK_LOG"'

# ---- party.sh --promote delegates to party-cli promote ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --promote party-test-123 2>/dev/null || true
assert "party.sh --promote delegates to party-cli" \
  'grep -q "^promote party-test-123" "$MOCK_LOG"'

# ---- party-relay.sh --broadcast delegates to party-cli broadcast ----
> "$MOCK_LOG"
# relay requires discover_session — set PARTY_SESSION to a master
export PARTY_STATE_ROOT="$MOCK_DIR/state"
mkdir -p "$PARTY_STATE_ROOT"
# Create a fake master manifest
FAKE_MASTER="party-test-master-$$"
export PARTY_SESSION="$FAKE_MASTER"
cat > "$PARTY_STATE_ROOT/$FAKE_MASTER.json" << EOF
{"party_id":"$FAKE_MASTER","session_type":"master","workers":[]}
EOF
bash "$REPO_ROOT/session/party-relay.sh" --broadcast "hello workers" 2>/dev/null || true
assert "party-relay.sh --broadcast delegates to party-cli" \
  'grep -q "^broadcast" "$MOCK_LOG"'

# ---- party-relay.sh --read delegates to party-cli read ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --read party-worker-1 2>/dev/null || true
assert "party-relay.sh --read delegates to party-cli" \
  'grep -q "^read party-worker-1" "$MOCK_LOG"'

# ---- party-relay.sh --report delegates to party-cli report ----
> "$MOCK_LOG"
export PARTY_SESSION="party-worker-1"
cat > "$PARTY_STATE_ROOT/party-worker-1.json" << EOF
{"party_id":"party-worker-1","parent_session":"$FAKE_MASTER"}
EOF
bash "$REPO_ROOT/session/party-relay.sh" --report "task done" 2>/dev/null || true
assert "party-relay.sh --report delegates to party-cli" \
  'grep -q "^report" "$MOCK_LOG"'

# ---- party-relay.sh --list delegates to party-cli workers ----
> "$MOCK_LOG"
export PARTY_SESSION="$FAKE_MASTER"
bash "$REPO_ROOT/session/party-relay.sh" --list 2>/dev/null || true
assert "party-relay.sh --list delegates to party-cli" \
  'grep -q "^workers" "$MOCK_LOG"'

# ---- party-relay.sh <worker> "msg" delegates to party-cli relay ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" party-worker-1 "do the thing" 2>/dev/null || true
assert "party-relay.sh direct relay delegates to party-cli" \
  'grep -q "^relay party-worker-1" "$MOCK_LOG"'

# ---- party.sh --pick-entries delegates to party-cli picker entries ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --pick-entries 2>/dev/null || true
assert "party.sh --pick-entries delegates to party-cli" \
  'grep -q "^picker entries" "$MOCK_LOG"'

# ---- Verify party-master.sh is no longer sourced (no duplicate functions) ----
assert "party-master.sh is retired (not sourced by party.sh)" \
  '! grep -q "source.*party-master.sh" "$REPO_ROOT/session/party.sh"'

# ---- Verify party-preview.sh delegates to party-cli ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-preview.sh" party-test-123 "$PARTY_STATE_ROOT" "$HOME" 2>/dev/null || true
assert "party-preview.sh delegates to party-cli picker preview" \
  'grep -q "^picker preview -- party-test-123" "$MOCK_LOG"'

# ---- Verify duplicate bash functions are removed from party.sh ----
assert "party_list() removed from party.sh" \
  '! grep -q "^party_list()" "$REPO_ROOT/session/party.sh"'

assert "party_stop() removed from party.sh" \
  '! grep -q "^party_stop()" "$REPO_ROOT/session/party.sh"'

assert "party_continue() removed from party.sh" \
  '! grep -q "^party_continue()" "$REPO_ROOT/session/party.sh"'

assert "party_delete() removed from party.sh" \
  '! grep -q "^party_delete()" "$REPO_ROOT/session/party.sh"'

assert "party_prune_manifests() removed from party.sh" \
  '! grep -q "^party_prune_manifests()" "$REPO_ROOT/session/party.sh"'

assert "party_launch_agents() removed from party.sh" \
  '! grep -q "^party_launch_agents()" "$REPO_ROOT/session/party.sh"'

assert "_party_launch_classic() removed from party.sh" \
  '! grep -q "^_party_launch_classic()" "$REPO_ROOT/session/party.sh"'

assert "_party_launch_sidebar() removed from party.sh" \
  '! grep -q "^_party_launch_sidebar()" "$REPO_ROOT/session/party.sh"'

# ---- Verify duplicate bash functions are removed from party-relay.sh ----
assert "relay_to_worker() removed from party-relay.sh" \
  '! grep -q "^relay_to_worker()" "$REPO_ROOT/session/party-relay.sh"'

assert "relay_broadcast() removed from party-relay.sh" \
  '! grep -q "^relay_broadcast()" "$REPO_ROOT/session/party-relay.sh"'

assert "relay_list() removed from party-relay.sh" \
  '! grep -q "^relay_list()" "$REPO_ROOT/session/party-relay.sh"'

assert "relay_read() removed from party-relay.sh" \
  '! grep -q "^relay_read()" "$REPO_ROOT/session/party-relay.sh"'

assert "relay_report() removed from party-relay.sh" \
  '! grep -q "^relay_report()" "$REPO_ROOT/session/party-relay.sh"'

# ---- Verify party-picker.sh delegate functions are removed ----
assert "party_pick_entries() removed from party-picker.sh" \
  '! grep -q "^party_pick_entries()" "$REPO_ROOT/session/party-picker.sh"'

assert "_party_fzf_select() removed from party-picker.sh" \
  '! grep -q "^_party_fzf_select()" "$REPO_ROOT/session/party-picker.sh"'

# ---- Verify party-lib.sh is retained ----
assert "party-lib.sh still exists" \
  '[ -f "$REPO_ROOT/session/party-lib.sh" ]'

assert "party-lib.sh still has discover_session" \
  'grep -q "^discover_session()" "$REPO_ROOT/session/party-lib.sh"'

assert "party-lib.sh still has tmux_send" \
  'grep -q "^tmux_send()" "$REPO_ROOT/session/party-lib.sh"'

assert "party-lib.sh still has write_codex_status" \
  'grep -q "^write_codex_status()" "$REPO_ROOT/session/party-lib.sh"'

# ---- Verify shared resolver exists in party-lib.sh ----
assert "party_resolve_cli_bin() exists in party-lib.sh" \
  'grep -q "^party_resolve_cli_bin()" "$REPO_ROOT/session/party-lib.sh"'

# ---- Verify no duplicate _resolve_party_cli in wrappers ----
assert "no _resolve_party_cli in party.sh (uses shared)" \
  '! grep -q "_resolve_party_cli()" "$REPO_ROOT/session/party.sh"'

assert "no _resolve_party_cli in party-relay.sh (uses shared)" \
  '! grep -q "_resolve_party_cli()" "$REPO_ROOT/session/party-relay.sh"'

assert "no _picker_resolve_cli in party-picker.sh (uses shared)" \
  '! grep -q "_picker_resolve_cli()" "$REPO_ROOT/session/party-picker.sh"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
