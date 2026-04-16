#!/usr/bin/env bash
# Tests for companion-guard.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../companion-guard.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

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

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  export XDG_CONFIG_HOME="$TMPDIR_BASE/.config"
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
}

config_path() {
  printf '%s\n' "$XDG_CONFIG_HOME/party-cli/config.toml"
}

cleanup() {
  rm -f "$(config_path)" 2>/dev/null || true
  unset XDG_CONFIG_HOME
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap cleanup EXIT

hook_input() {
  local cmd="$1"
  jq -cn --arg cmd "$cmd" '{tool_input:{command:$cmd},session_id:"guard-test"}'
}

no_companion_config() {
  mkdir -p "$(dirname "$(config_path)")"
  cat > "$(config_path)" <<'EOF'
[roles.primary]
agent = "claude"
EOF
}

echo "--- test-companion-guard.sh ---"

setup_repo

OUTPUT=$(echo "$(hook_input 'ls -la')" | bash "$HOOK")
assert "non-tmux commands are allowed" \
  '! echo "$OUTPUT" | grep -q "deny"'

OUTPUT=$(echo "$(hook_input 'tmux send-keys -t companion:0.0 Enter')" | bash "$HOOK")
assert "raw tmux send-keys to companion is blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

OUTPUT=$(echo "$(hook_input 'tmux list-panes | grep companion')" | bash "$HOOK")
assert "tmux pipeline filtering for companion is blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

OUTPUT=$(echo "$(hook_input 'tmux send-keys -t primary:0.0 Enter')" | bash "$HOOK")
assert "primary targets are not blocked by companion guard" \
  '! echo "$OUTPUT" | grep -q "deny"'

no_companion_config
OUTPUT=$(echo "$(hook_input 'tmux send-keys -t companion:0.0 Enter')" | bash "$HOOK")
assert "no companion configured fails open" \
  '! echo "$OUTPUT" | grep -q "deny"'

rm -f "$(config_path)"
OUTPUT=$(echo "$(hook_input 'tmux send-keys -t companion:0.0 Enter')" | PARTY_CLI_DISABLE_GO_FALLBACK=1 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$HOOK")
assert "missing party-cli fails open" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
