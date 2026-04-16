#!/usr/bin/env bash
# Tests for pr-gate.sh
# Covers: full gate, quick tier, docs-only bypass, stale evidence
#
# Usage: bash ~/.claude/hooks/tests/test-pr-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../pr-gate.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION_ID="test-pr-gate-$$"
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
  echo "#!/bin/bash" > file.sh
  git add file.sh
  git commit -q -m "initial commit"
  git checkout -q -b feature
}

config_path() {
  printf '%s\n' "$XDG_CONFIG_HOME/party-cli/config.toml"
}

clean_evidence() {
  rm -f "$(evidence_file "$SESSION_ID")"
  rm -f "/tmp/claude-evidence-${SESSION_ID}.lock"
  rmdir "/tmp/claude-evidence-${SESSION_ID}.lock.d" 2>/dev/null || true
  rm -f "$(config_path)" 2>/dev/null || true
}

full_cleanup() {
  clean_evidence
  unset XDG_CONFIG_HOME
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_cleanup EXIT

gate_input() {
  jq -cn \
    --arg sid "$SESSION_ID" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_input:{command:"gh pr create --title test"},session_id:$sid,cwd:$cwd}'
}

add_all_evidence() {
  for type in pr-verified code-critic minimizer codex test-runner check-runner; do
    append_evidence "$SESSION_ID" "$type" "PASS" "$TMPDIR_BASE"
  done
}

write_custom_evidence_config() {
  mkdir -p "$(dirname "$(config_path)")"
  cat > "$(config_path)" <<'EOF'
[evidence]
required = ["pr-verified", "test-runner", "check-runner"]
EOF
}

echo "--- test-pr-gate.sh ---"

# ═══ Docs-only bypass ═══════════════════════════════════════════════════════

echo "=== Docs-only bypass ==="
setup_repo
clean_evidence
echo "docs" > readme.md
git add readme.md && git commit -q -m "add docs"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Docs-only PR allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: .md + .svg files ==="
setup_repo
clean_evidence
echo "docs" > readme.md
echo '<svg></svg>' > diagram.svg
git add readme.md diagram.svg && git commit -q -m "add docs with svg"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Docs PR with .svg allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: .png + .txt + .csv + .drawio files ==="
setup_repo
clean_evidence
echo "img" > screenshot.png
echo "notes" > notes.txt
echo "a,b" > data.csv
echo "<mxfile>" > arch.drawio
git add screenshot.png notes.txt data.csv arch.drawio && git commit -q -m "add misc doc artifacts"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Docs PR with .png/.txt/.csv/.drawio allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: .sh file still requires evidence ==="
setup_repo
clean_evidence
echo "docs" > readme.md
echo "#!/bin/bash" > script.sh
git add readme.md script.sh && git commit -q -m "add docs and script"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with .sh file requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: Dockerfile requires evidence ==="
setup_repo
clean_evidence
echo "FROM alpine" > Dockerfile
git add Dockerfile && git commit -q -m "add Dockerfile"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with Dockerfile requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: Makefile requires evidence ==="
setup_repo
clean_evidence
echo "all:" > Makefile
git add Makefile && git commit -q -m "add Makefile"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with Makefile requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: go.mod requires evidence ==="
setup_repo
clean_evidence
echo "module example.com/foo" > go.mod
git add go.mod && git commit -q -m "add go.mod"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with go.mod requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: package-lock.json requires evidence ==="
setup_repo
clean_evidence
echo '{"lockfileVersion":3}' > package-lock.json
git add package-lock.json && git commit -q -m "add lockfile"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with package-lock.json requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Docs-only bypass: requirements.txt requires evidence ==="
setup_repo
clean_evidence
echo "flask==2.0" > requirements.txt
git add requirements.txt && git commit -q -m "add requirements.txt"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "PR with requirements.txt requires evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Full gate tests ════════════════════════════════════════════════════════

echo "=== Full gate: blocks when evidence missing ==="
setup_repo
clean_evidence
echo "change" >> file.sh
git add file.sh && git commit -q -m "code change"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate blocks without evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: allows when all evidence present ==="
clean_evidence
add_all_evidence
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate allows with all evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: blocks on stale diff_hash ==="
clean_evidence
add_all_evidence
cd "$TMPDIR_BASE"
echo "stale" >> file.sh
git add file.sh && git commit -q -m "stale edit"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Full gate blocks stale evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: small diff still requires full evidence ==="
setup_repo
clean_evidence
echo "tiny fix" >> file.sh
git add file.sh && git commit -q -m "tiny fix"
# Only provide test-runner + check-runner (not full set)
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Small diff with partial evidence blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: custom evidence-required config drives requirements ==="
setup_repo
clean_evidence
write_custom_evidence_config
echo "configurable" >> file.sh
git add file.sh && git commit -q -m "configurable gate"
append_evidence "$SESSION_ID" "pr-verified" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Custom evidence list allows without critic/minimizer/companion evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Full gate: missing party-cli falls back to default evidence list ==="
setup_repo
clean_evidence
write_custom_evidence_config
echo "fallback" >> file.sh
git add file.sh && git commit -q -m "fallback gate"
append_evidence "$SESSION_ID" "pr-verified" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | PARTY_CLI_DISABLE_GO_FALLBACK=1 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$GATE")
assert "Missing party-cli restores default full gate" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Quick tier tests ════════════════════════════════════════════════════════

echo "=== Quick tier: explicit quick-tier evidence → passes with quick evidence ==="
setup_repo
clean_evidence
echo "small edit" >> file.sh
git add file.sh && git commit -q -m "small edit"
append_evidence "$SESSION_ID" "quick-tier" "AUTHORIZED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Quick tier: explicit quick-tier + critic + runners passes" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Quick tier: size alone insufficient without quick-tier evidence ==="
setup_repo
clean_evidence
echo "small edit" >> file.sh
git add file.sh && git commit -q -m "small edit"
# No quick-tier evidence — only critic + runners
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Quick tier: no quick-tier evidence → full gate → blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

echo "=== Quick tier: quick-tier evidence with large diff still passes quick gate ==="
setup_repo
clean_evidence
for i in $(seq 1 40); do echo "line $i" >> file.sh; done
git add file.sh && git commit -q -m "big edit"
append_evidence "$SESSION_ID" "quick-tier" "AUTHORIZED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Quick tier: large diff with quick-tier evidence passes" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo "=== Quick tier: quick-tier evidence with new file still passes quick gate ==="
setup_repo
clean_evidence
echo "new" > new.sh
git add new.sh && git commit -q -m "new file"
append_evidence "$SESSION_ID" "quick-tier" "AUTHORIZED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Quick tier: new file with quick-tier evidence passes" \
  '! echo "$OUTPUT" | grep -q "deny"'

# ═══ Full gate: stale critics blocked (no phase-2 relaxation) ═════════════

echo "=== Full gate: stale critics at old hash + codex at current → blocked ==="
setup_repo
clean_evidence
cd "$TMPDIR_BASE"
echo "impl code" > impl.sh && git add impl.sh && git commit -q -m "impl"
# Critics approve at hash_A
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
# Fix commit → hash_B (critics now at stale hash)
echo "codex fix" >> impl.sh && git add impl.sh && git commit -q -m "codex fix"
# Codex approves at hash_B, plus other required evidence at hash_B
append_evidence "$SESSION_ID" "codex" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "pr-verified" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "test-runner" "PASS" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "check-runner" "PASS" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input)" | bash "$GATE")
assert "Stale critics at old hash + codex at current → blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Non-PR commands pass through ═══════════════════════════════════════════

echo "=== Non-PR commands allowed ==="
setup_repo
clean_evidence
NON_PR_INPUT=$(jq -cn \
  --arg sid "$SESSION_ID" \
  --arg cwd "$TMPDIR_BASE" \
  '{tool_input:{command:"git push"},session_id:$sid,cwd:$cwd}')
OUTPUT=$(echo "$NON_PR_INPUT" | bash "$GATE")
assert "git push allowed without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
