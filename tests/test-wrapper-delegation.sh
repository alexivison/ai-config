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
  spawn)  echo "Worker 'party-mock-w1' spawned." ;;
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

# ---- party.sh --continue delegates to party-cli continue --attach ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --continue party-test-123 2>/dev/null || true
assert "party.sh --continue delegates to party-cli with --attach" \
  'grep -q "^continue --attach party-test-123" "$MOCK_LOG"'

# ---- party.sh start delegates with --attach ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" test-title 2>/dev/null || true
assert "party.sh start passes --attach to party-cli" \
  'grep -q "start.*--attach" "$MOCK_LOG"'

# ---- party.sh --detached start does NOT pass --attach ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --detached test-title 2>/dev/null || true
assert "party.sh --detached omits --attach" \
  '! grep -q "\-\-attach" "$MOCK_LOG"'

# ---- party.sh --master forces --no-companion ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --master --primary codex test-title 2>/dev/null || true
assert "party.sh --master forwards --no-companion" \
  'grep -q "start.*--master.*--primary codex.*--no-companion" "$MOCK_LOG"'

# ---- party-relay.sh --broadcast delegates to party-cli broadcast ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --broadcast "hello workers" 2>/dev/null || true
assert "party-relay.sh --broadcast delegates to party-cli (auto-discover)" \
  'grep -q "^broadcast hello workers" "$MOCK_LOG"'

# ---- party-relay.sh --read delegates to party-cli read ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --read party-worker-1 2>/dev/null || true
assert "party-relay.sh --read delegates to party-cli" \
  'grep -q "^read party-worker-1" "$MOCK_LOG"'

# ---- party-relay.sh --report delegates to party-cli report (auto-discover) ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --report "task done" 2>/dev/null || true
assert "party-relay.sh --report delegates to party-cli (auto-discover)" \
  'grep -q "^report task done" "$MOCK_LOG"'

# ---- party-relay.sh --list delegates to party-cli workers (auto-discover) ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --list 2>/dev/null || true
assert "party-relay.sh --list delegates to party-cli (auto-discover)" \
  'grep -q "^workers" "$MOCK_LOG"'

# ---- party-relay.sh <worker> "msg" delegates to party-cli relay ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" party-worker-1 "do the thing" 2>/dev/null || true
assert "party-relay.sh direct relay delegates to party-cli" \
  'grep -q "^relay party-worker-1" "$MOCK_LOG"'

# ---- party-relay.sh --spawn delegates to party-cli spawn (auto-discover) ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --spawn "worker-title" 2>/dev/null || true
assert "party-relay.sh --spawn delegates to party-cli (auto-discover)" \
  'grep -q "^spawn worker-title" "$MOCK_LOG"'

# ---- party-relay.sh --file delegates imperative pointer wording ----
tmp_relay_file="$(mktemp)"
printf 'instructions\n' > "$tmp_relay_file"
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --file "$tmp_relay_file" party-worker-1 2>/dev/null || true
assert "party-relay.sh --file tells workers to act and report back" \
  'grep -Fq "relay party-worker-1 Read and follow the instructions in '"$tmp_relay_file"'. Act on them now, then report back with results." "$MOCK_LOG"'
rm -f "$tmp_relay_file"

# ---- party.sh --pick-entries delegates to party-cli picker entries ----
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party.sh" --pick-entries 2>/dev/null || true
assert "party.sh --pick-entries delegates to party-cli" \
  'grep -q "^picker entries" "$MOCK_LOG"'

# ---- Verify party-master.sh is no longer sourced (no duplicate functions) ----
assert "party-master.sh is retired (not sourced by party.sh)" \
  '! grep -q "source.*party-master.sh" "$REPO_ROOT/session/party.sh"'

# ---- Verify party-lib.sh is no longer sourced by wrappers ----
assert "party.sh does not source party-lib.sh" \
  '! grep -q "source.*party-lib.sh" "$REPO_ROOT/session/party.sh"'

assert "party-relay.sh --companion routes through companion helper" \
  'grep -q "party_companion_pane_target" "$REPO_ROOT/session/party-relay.sh"'

assert "party-relay.sh legacy --wizard alias removed" \
  '! grep -q -- "--wizard" "$REPO_ROOT/session/party-relay.sh"'

assert "legacy provider transport skills are removed" \
  '[ ! -e "$REPO_ROOT/claude/skills/codex-transport" ] && [ ! -e "$REPO_ROOT/codex/skills/claude-transport" ]'

# ---- Verify vestigial scripts are deleted ----
assert "party-picker.sh is deleted" \
  '[ ! -f "$REPO_ROOT/session/party-picker.sh" ]'

assert "party-preview.sh is deleted" \
  '[ ! -f "$REPO_ROOT/session/party-preview.sh" ]'

assert "party-master-jump.sh is deleted" \
  '[ ! -f "$REPO_ROOT/session/party-master-jump.sh" ]'

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

# ---- Verify no duplicate _resolve_party_cli in old locations ----
assert "no _resolve_party_cli in party-picker.sh (deleted)" \
  '[ ! -f "$REPO_ROOT/session/party-picker.sh" ]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
