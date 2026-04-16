#!/usr/bin/env bash
# Tests for companion-trace.sh.
# Single-phase model: companion evidence is created directly from
# CODEX APPROVED + CODEX_REVIEW_RAN. No intermediate run evidence.
#
# Usage: bash ~/.claude/hooks/tests/test-codex-trace.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../companion-trace.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION="test-codex-trace-$$"
TMPDIR_BASE=""

setup_repo() {
  TMPDIR_BASE=$(mktemp -d)
  export XDG_CONFIG_HOME="$TMPDIR_BASE/.config"
  cd "$TMPDIR_BASE"
  git init -q
  git checkout -q -b main
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial commit"
  git checkout -q -b feature
  echo "impl" > impl.sh
  git add impl.sh
  git commit -q -m "add impl"
}

config_path() {
  printf '%s\n' "$XDG_CONFIG_HOME/party-cli/config.toml"
}

clean_evidence() {
  rm -f "$(evidence_file "$SESSION")"
  rm -f "/tmp/claude-evidence-${SESSION}.lock"
  rmdir "/tmp/claude-evidence-${SESSION}.lock.d" 2>/dev/null || true
}

clear_config() {
  rm -f "$(config_path)" 2>/dev/null || true
}

write_stub_companion_config() {
  mkdir -p "$(dirname "$(config_path)")"
  cat > "$(config_path)" <<'EOF'
[agents.stub]
cli = "stub"

[roles.primary]
agent = "claude"

[roles.companion]
agent = "stub"
window = 0
EOF
}

full_cleanup() {
  clean_evidence
  clear_config
  unset XDG_CONFIG_HOME
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_cleanup EXIT

assert() {
  local name="$1" condition="$2"
  if eval "$condition"; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

run_hook() {
  echo "$1" | bash "$HOOK" 2>/dev/null
}

has_evidence() {
  local type="$1"
  check_evidence "$SESSION" "$type" "$TMPDIR_BASE"
}

# Helper to build Bash hook input
bash_input_obj() {
  local cmd="$1" stdout="$2" exit_code="${3:-0}"
  jq -cn \
    --arg cmd "$cmd" \
    --arg stdout "$stdout" \
    --argjson ec "$exit_code" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_name:"Bash",tool_input:{command:$cmd},tool_response:{stdout:$stdout,stderr:"",interrupted:false,exit_code:$ec},session_id:$sid,cwd:$cwd}'
}

bash_input_str() {
  local cmd="$1" stdout="$2"
  jq -cn \
    --arg cmd "$cmd" \
    --arg stdout "$stdout" \
    --arg sid "$SESSION" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_name:"Bash",tool_input:{command:$cmd},tool_response:$stdout,session_id:$sid,cwd:$cwd}'
}

# ═══ --review-complete with APPROVED verdict ═════════════════════════════════

setup_repo

echo "=== review-complete: APPROVED creates codex evidence directly (object response) ==="
clean_evidence
COMBINED_STDOUT=$'CODEX_REVIEW_RAN\nCODEX APPROVED'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "APPROVED → codex evidence created" 'has_evidence "codex"'

echo "=== review-complete: custom companion name drives evidence type ==="
clean_evidence
clear_config
write_stub_companion_config
METRICS_FILE="$HOME/.claude/logs/review-metrics/${SESSION}.jsonl"
rm -f "$METRICS_FILE"
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "APPROVED → stub evidence created" 'has_evidence "stub"'
assert "APPROVED → codex evidence not created for stub companion" '! has_evidence "codex"'
clear_config
rm -f "$METRICS_FILE"

echo "=== review-complete: APPROVED creates codex evidence (string response) ==="
clean_evidence
run_hook "$(bash_input_str 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "String APPROVED → codex evidence created" 'has_evidence "codex"'

echo "=== review-complete: APPROVED via full path ==="
clean_evidence
run_hook "$(bash_input_obj '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")"
assert "Full path APPROVED → codex evidence created" 'has_evidence "codex"'

echo "=== review-complete: missing party-cli falls back to codex evidence ==="
clean_evidence
echo "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_STDOUT")" \
  | PARTY_CLI_DISABLE_GO_FALLBACK=1 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$HOOK" 2>/dev/null
assert "Missing party-cli → codex evidence created" 'has_evidence "codex"'

# ═══ --review-complete with REQUEST_CHANGES ═══════════════════════════════════

echo "=== review-complete: REQUEST_CHANGES → no codex evidence ==="
clean_evidence
RC_STDOUT=$'CODEX_REVIEW_RAN\nCODEX REQUEST_CHANGES'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$RC_STDOUT")"
assert "REQUEST_CHANGES → no codex evidence" '! has_evidence "codex"'

# ═══ --review-complete without CODEX_REVIEW_RAN sentinel ═════════════════════

echo "=== review-complete: CODEX APPROVED without CODEX_REVIEW_RAN → no evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX APPROVED')"
assert "APPROVED without review-ran sentinel → no codex evidence" '! has_evidence "codex"'

echo "=== review-complete: CODEX_REVIEW_RAN alone → no codex evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'CODEX_REVIEW_RAN')"
assert "Review-ran alone → no codex evidence" '! has_evidence "codex"'

# ═══ --plan-review (advisory only) ════════════════════════════════════════════

echo "=== plan-review: does not create evidence ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --plan-review PLAN.md /tmp/work' 'CODEX_PLAN_REVIEW_REQUESTED')"
assert "Plan-review → no codex evidence" '! has_evidence "codex"'

# ═══ Exit code extraction ════════════════════════════════════════════════════

echo "=== Exit code: top-level tool_exit_code ==="
clean_evidence
INPUT=$(jq -cn \
  --arg sid "$SESSION" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN\nCODEX APPROVED",stderr:""},tool_exit_code:1,session_id:$sid,cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "tool_exit_code=1 → no evidence" '! has_evidence "codex"'

echo "=== Exit code: nested in tool_response ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' 'Error' 1)" || true
assert "tool_response.exit_code=1 → no evidence" '! has_evidence "codex"'

# ═══ Guard clauses ═══════════════════════════════════════════════════════════

echo "=== Guard: Non-tmux command ignored ==="
clean_evidence
run_hook "$(bash_input_obj 'echo CODEX_REVIEW_RAN' "$COMBINED_STDOUT")"
assert "Non-tmux → no evidence" '! has_evidence "codex"'

echo "=== Guard: Invalid JSON fails open ==="
clean_evidence
echo 'not json' | bash "$HOOK" 2>/dev/null || true
assert "Invalid JSON → no crash" 'true'

echo "=== Guard: Missing session_id → no evidence ==="
clean_evidence
INPUT=$(jq -cn \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_name:"Bash",tool_input:{command:"tmux-codex.sh --review-complete /tmp/f.toon"},tool_response:{stdout:"CODEX_REVIEW_RAN\nCODEX APPROVED",stderr:""},cwd:$cwd}')
echo "$INPUT" | bash "$HOOK" 2>/dev/null || true
assert "No session_id → no evidence" '! has_evidence "codex"'

# ═══ Full workflow simulation ════════════════════════════════════════════════

echo "=== Workflow: APPROVED verdict → codex evidence ==="
clean_evidence
APPROVED_STDOUT=$'CODEX_REVIEW_RAN\nCODEX APPROVED'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Workflow: codex evidence created" 'has_evidence "codex"'

echo "=== Workflow: stale evidence after code edit ==="
clean_evidence
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Step 1: codex evidence created" 'has_evidence "codex"'
# Simulate code edit — changes diff_hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "code edit"
assert "Step 2: codex stale after edit" '! has_evidence "codex"'
# Re-do review with approval
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$APPROVED_STDOUT")"
assert "Step 3: codex recreated" 'has_evidence "codex"'

# ═══ --triage-override ════════════════════════════════════════════════════════

echo "=== triage-override: valid type with prior critic run ==="
clean_evidence
# Critic must have run first
append_evidence "$SESSION" "code-critic" "REQUEST_CHANGES" "$TMPDIR_BASE"
OVERRIDE_STDOUT='TRIAGE_OVERRIDE code-critic | Out-of-scope: rebased auth files'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override code-critic "Out-of-scope: rebased auth files"' "$OVERRIDE_STDOUT")"
assert "Valid triage override → code-critic evidence" 'has_evidence "code-critic"'

echo "=== triage-override: rejected without prior critic run ==="
clean_evidence
OVERRIDE_STDOUT2='TRIAGE_OVERRIDE code-critic | No critic ran'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override code-critic "No critic ran"' "$OVERRIDE_STDOUT2")"
assert "No prior critic → no evidence" '! has_evidence "code-critic"'

echo "=== triage-override: invalid type rejected ==="
clean_evidence
OVERRIDE_BAD='TRIAGE_OVERRIDE codex | Trying to bypass'
run_hook "$(bash_input_obj 'tmux-codex.sh --triage-override codex "Trying to bypass"' "$OVERRIDE_BAD")"
assert "Invalid type → no codex evidence" '! has_evidence "codex"'

echo "=== triage-override: combined with CODEX_REVIEW_RAN ==="
clean_evidence
# Critic must have run first
append_evidence "$SESSION" "minimizer" "REQUEST_CHANGES" "$TMPDIR_BASE"
COMBINED_OVERRIDE=$'CODEX_REVIEW_RAN\nTRIAGE_OVERRIDE minimizer | Rebased code from PR #65315'
run_hook "$(bash_input_obj 'tmux-codex.sh --review-complete /tmp/f.toon' "$COMBINED_OVERRIDE")"
assert "Combined → minimizer override evidence" 'has_evidence "minimizer"'

# ─── Triage/Resolution metrics from codex findings ──────────────────────────

echo "=== Codex triage: findings from TOON file get triage events ==="
clean_evidence
METRICS_FILE="$HOME/.claude/logs/review-metrics/${SESSION}.jsonl"
rm -f "$METRICS_FILE"

# Create a TOON findings file with 2 findings
TOON_FILE=$(mktemp /tmp/test-codex-XXXXXX.toon)
cat > "$TOON_FILE" << 'TOON'
findings[2]{id,file,line,severity,category,description,suggestion}:
  F1,src/app.ts,42,blocking,correctness,Missing null check,Add check
  F2,src/util.ts,10,low,style,Unused import,Remove it

summary:
  VERDICT: REQUEST_CHANGES
TOON

CODEX_RC_RESP=$'CODEX_REVIEW_RAN\nCODEX REQUEST_CHANGES'
run_hook "$(bash_input_obj "tmux-codex.sh --review-complete $TOON_FILE" "$CODEX_RC_RESP")"

CODEX_FINDINGS=$(jq -s '[.[] | select(.event == "finding_raised" and .source == "codex")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Codex triage: 2 findings raised" '[ "$CODEX_FINDINGS" -eq 2 ]'

CODEX_TRIAGE=$(jq -s '[.[] | select(.event == "triage" and .source == "codex")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Codex triage: 2 triage events recorded" '[ "$CODEX_TRIAGE" -eq 2 ]'

CODEX_BLOCK_FIX=$(jq -s '[.[] | select(.event == "triage" and .source == "codex" and .action == "fix")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Codex triage: blocking finding triaged as fix" '[ "$CODEX_BLOCK_FIX" -eq 1 ]'

echo "=== Codex resolution: APPROVED resolves prior findings ==="
clean_evidence
# Write approval response
CODEX_APPR_RESP=$'CODEX_REVIEW_RAN\nCODEX APPROVED'
run_hook "$(bash_input_obj "tmux-codex.sh --review-complete $TOON_FILE" "$CODEX_APPR_RESP")"

CODEX_RESOLVED=$(jq -s '[.[] | select(.event == "resolved" and .resolution == "fixed")] | length' "$METRICS_FILE" 2>/dev/null || echo 0)
assert "Codex resolution: prior fix findings resolved" '[ "$CODEX_RESOLVED" -ge 1 ]'

rm -f "$TOON_FILE" "$METRICS_FILE"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "companion-trace.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"
[ "$FAIL" -eq 0 ] || exit 1
