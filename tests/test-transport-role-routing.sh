#!/usr/bin/env bash
# Tests for role-aware transport scripts and the party-relay --wizard helper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

MOCK_DIR="$(mktemp -d)"
MOCK_LOG="$MOCK_DIR/tmux.log"

cleanup() {
  rm -rf "$MOCK_DIR"
  rm -rf /tmp/party-transport-new-$$ /tmp/party-transport-old-$$
}
trap cleanup EXIT

cat > "$MOCK_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  display-message)
    if [[ "$*" == *'#{@party_role}'* ]]; then
      printf '%s\n' "${MOCK_CURRENT_ROLE:-}"
      exit 0
    fi
    if [[ "$*" == *'#{window_index}'* ]]; then
      printf '%s\n' "${MOCK_CURRENT_WINDOW:-0}"
      exit 0
    fi
    if [[ "$*" == *'#{session_name}'* ]]; then
      printf '%s\n' "${PARTY_SESSION:-party-test}"
      exit 0
    fi
    printf '\n'
    ;;
  list-windows)
    printf '%b\n' "${MOCK_WINDOW_LIST:-0}"
    ;;
  list-panes)
    target=""
    prev=""
    for arg in "$@"; do
      if [[ "$prev" == "-t" ]]; then
        target="$arg"
        break
      fi
      prev="$arg"
    done
    win="${target##*:}"
    var_name="MOCK_PANES_${win//[^0-9]/}"
    printf '%b\n' "${!var_name:-}"
    ;;
  send-keys)
    target=""
    text=""
    prev=""
    for arg in "$@"; do
      if [[ "$prev" == "-t" ]]; then
        target="$arg"
        prev=""
        continue
      fi
      if [[ "$prev" == "-l" ]]; then
        text="$arg"
        prev=""
        continue
      fi
      case "$arg" in
        -t|-l) prev="$arg" ;;
      esac
    done
    if [[ -n "$text" ]]; then
      printf '%s\t%s\n' "$target" "$text" >> "${MOCK_TMUX_LOG:?}"
    fi
    ;;
  capture-pane|set-environment|set-option|attach|switch-client)
    ;;
  *)
    ;;
esac
EOF
chmod +x "$MOCK_DIR/tmux"

cat > "$MOCK_DIR/party-cli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_DIR/party-cli"

export PATH="$MOCK_DIR:$PATH"
export MOCK_TMUX_LOG="$MOCK_LOG"
export TMUX_SEND_FORCE=1
export PARTY_REPO_ROOT="$REPO_ROOT"

run_and_capture() {
  local session="$1"
  shift
  PARTY_SESSION="$session" "$@" >/dev/null
}

assert_log() {
  local target="$1"
  local prefix="$2"
  local needle
  needle="$(printf '%s\t%s' "$target" "$prefix")"
  if grep -Fq "$needle" "$MOCK_LOG"; then
    PASS=$((PASS + 1))
    echo "  [PASS] log contains target $target with prefix $prefix"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] log contains target $target with prefix $prefix"
    echo "         actual log:"
    sed 's/^/         /' "$MOCK_LOG"
  fi
}

assert_log_contains() {
  local needle="$1"
  if grep -Fq "$needle" "$MOCK_LOG"; then
    PASS=$((PASS + 1))
    echo "  [PASS] log contains $needle"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] log contains $needle"
    echo "         actual log:"
    sed 's/^/         /' "$MOCK_LOG"
  fi
}

echo "--- test-transport-role-routing.sh ---"

SESSION_NEW="party-transport-new-$$"
SESSION_OLD="party-transport-old-$$"

echo ""
echo "  === tmux-claude.sh ==="

export MOCK_WINDOW_LIST=$'0\n1'
export MOCK_PANES_0=$'0 companion'
export MOCK_PANES_1=$'0 tracker\n1 primary\n2 shell'
> "$MOCK_LOG"
run_and_capture "$SESSION_NEW" bash "$REPO_ROOT/codex/skills/claude-transport/scripts/tmux-claude.sh" "Task complete. Response at: /tmp/resp.toon"
assert_log "${SESSION_NEW}:1.1" "[COMPANION] Task complete. Response at: /tmp/resp.toon"

export TMUX_PANE="%99"
export MOCK_CURRENT_ROLE="primary"
> "$MOCK_LOG"
run_and_capture "$SESSION_NEW" bash "$REPO_ROOT/codex/skills/claude-transport/scripts/tmux-claude.sh" "Question: tell me a joke. Write response to: /tmp/resp.toon"
assert_log "${SESSION_NEW}:0.0" "[PRIMARY] Question: tell me a joke. Write response to: /tmp/resp.toon"
assert_log_contains 'When done, run:'
assert_log_contains 'Response ready at: /tmp/resp.toon'
unset TMUX_PANE
unset MOCK_CURRENT_ROLE

export MOCK_WINDOW_LIST="0"
export MOCK_PANES_0=$'0 codex\n1 claude\n2 shell'
unset MOCK_PANES_1
> "$MOCK_LOG"
run_and_capture "$SESSION_OLD" bash "$REPO_ROOT/codex/skills/claude-transport/scripts/tmux-claude.sh" "Task complete. Response at: /tmp/resp.toon"
assert_log "${SESSION_OLD}:0.1" "[CODEX] Task complete. Response at: /tmp/resp.toon"

echo ""
echo "  === tmux-codex.sh ==="

export MOCK_WINDOW_LIST=$'0\n1'
export MOCK_PANES_0=$'0 companion'
export MOCK_PANES_1=$'0 tracker\n1 primary\n2 shell'
> "$MOCK_LOG"
run_and_capture "$SESSION_NEW" bash "$REPO_ROOT/claude/skills/codex-transport/scripts/tmux-codex.sh" --prompt "inspect this" /tmp/work
assert_log "${SESSION_NEW}:0.0" "[PRIMARY] cd '/tmp/work' && inspect this"

export TMUX_PANE="%41"
export MOCK_CURRENT_ROLE="companion"
export CURRENT_ROLE="primary"
> "$MOCK_LOG"
run_and_capture "$SESSION_NEW" bash "$REPO_ROOT/claude/skills/codex-transport/scripts/tmux-codex.sh" --prompt "Response ready at: /tmp/resp.toon" /tmp/work
assert_log "${SESSION_NEW}:1.1" "[COMPANION] Response ready at: /tmp/resp.toon"
unset TMUX_PANE
unset MOCK_CURRENT_ROLE
unset CURRENT_ROLE

export MOCK_WINDOW_LIST="0"
export MOCK_PANES_0=$'0 codex\n1 claude\n2 shell'
unset MOCK_PANES_1
> "$MOCK_LOG"
run_and_capture "$SESSION_OLD" bash "$REPO_ROOT/claude/skills/codex-transport/scripts/tmux-codex.sh" --prompt "inspect this" /tmp/work
assert_log "${SESSION_OLD}:0.0" "[CLAUDE] cd '/tmp/work' && inspect this"

echo ""
echo "  === party-relay.sh --wizard ==="

export MOCK_PANES_0=$'0 companion\n1 primary\n2 shell'
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --wizard "$SESSION_NEW" "raw ping" >/dev/null
assert_log "${SESSION_NEW}:0.0" "raw ping"

export MOCK_PANES_0=$'0 codex\n1 claude\n2 shell'
> "$MOCK_LOG"
bash "$REPO_ROOT/session/party-relay.sh" --wizard "$SESSION_OLD" "legacy ping" >/dev/null
assert_log "${SESSION_OLD}:0.0" "legacy ping"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
