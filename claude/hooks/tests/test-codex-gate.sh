#!/usr/bin/env bash
# Tests for codex-gate.sh
# Uses JSONL evidence instead of marker files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../codex-gate.sh"
source "$SCRIPT_DIR/../lib/evidence.sh"

PASS=0
FAIL=0
SESSION_ID="test-codex-gate-$$"
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

clean_evidence() {
  rm -f "$(evidence_file "$SESSION_ID")"
  rm -f "/tmp/claude-evidence-${SESSION_ID}.lock"
  rmdir "/tmp/claude-evidence-${SESSION_ID}.lock.d" 2>/dev/null || true
}

full_cleanup() {
  clean_evidence
  if [ -n "$TMPDIR_BASE" ] && [ -d "$TMPDIR_BASE" ]; then
    rm -rf "$TMPDIR_BASE"
  fi
}
trap full_cleanup EXIT

gate_input() {
  local cmd="$1"
  jq -cn \
    --arg cmd "$cmd" \
    --arg sid "$SESSION_ID" \
    --arg cwd "$TMPDIR_BASE" \
    '{tool_input:{command:$cmd},session_id:$sid,cwd:$cwd}'
}

setup_repo

echo "--- test-codex-gate.sh ---"

# Test: gate allows non-tmux-codex commands
OUTPUT=$(echo "$(gate_input 'ls -la')" | bash "$GATE")
assert "gate allows non-tmux-codex commands" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --review without critic evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "gate blocks --review without critic evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --review with both critic evidence
clean_evidence
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input '~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "gate allows --review with both critic evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate always blocks --approve (workers cannot self-approve)
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --approve')" | bash "$GATE")
assert "gate blocks --approve without evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate blocks --approve even with codex-ran evidence
clean_evidence
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --approve')" | bash "$GATE")
assert "gate blocks --approve even with codex-ran evidence" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --prompt without evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --prompt "debug this"')" | bash "$GATE")
assert "gate allows --prompt without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: gate allows --plan-review without evidence
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --plan-review PLAN.md /tmp/work')" | bash "$GATE")
assert "gate allows --plan-review without evidence" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: stale evidence rejected after code edit (phase 1)
clean_evidence
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
# Change the diff hash
cd "$TMPDIR_BASE"
echo "new code" >> impl.sh
git add impl.sh && git commit -q -m "stale test"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 1: stale critic evidence rejected after code edit" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Two-phase model ═══════════════════════════════════════════════════════

# Test: phase 2 — critics + codex-ran at SAME hash → allows re-review after fix commit
clean_evidence
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
# Fix codex finding (changes hash, stales critic evidence)
cd "$TMPDIR_BASE"
echo "fix codex finding" >> impl.sh
git add impl.sh && git commit -q -m "codex fix"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 2: critics + codex-ran at same hash → allows re-review" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: phase 2 — codex-ran WITHOUT critics at same hash → blocked
clean_evidence
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 2: codex-ran but no critics at same hash → blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

# Test: phase 2 — critics at DIFFERENT hash than codex-ran → blocked (new feature)
clean_evidence
# Simulate: old feature had critics + codex at hash_A
cd "$TMPDIR_BASE"
echo "old feature" > old.sh && git add old.sh && git commit -q -m "old feature"
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
# New unrelated commit changes the hash — critics are at old hash, codex-ran at old hash
echo "new feature" > new.sh && git add new.sh && git commit -q -m "new feature"
# Critics at old hash match codex-ran at old hash, so phase 2 still applies
# (codex will review the full diff including new.sh)
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 2: same review chain, new commit → allows re-review" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: phase 1 — no codex-ran, no critics → blocked
clean_evidence
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 1: no evidence at all → blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

# ═══ Bug regression: phase 2 hash-independence ═════════════════════════════

# Test: phase 2 — codex-ran at DIFFERENT hash than critics → still allows
# Real-world scenario: critics approve at hash_A, codex reviews at hash_A,
# --review-complete runs AFTER a fix commit → codex-ran recorded at hash_B.
# Next fix → hash_C. Phase 2 should still allow because codex HAS reviewed.
clean_evidence
cd "$TMPDIR_BASE"
# Critics approve at current hash (hash_A)
append_evidence "$SESSION_ID" "code-critic" "APPROVED" "$TMPDIR_BASE"
append_evidence "$SESSION_ID" "minimizer" "APPROVED" "$TMPDIR_BASE"
# Fix + commit → hash_B
echo "fix for codex" >> impl.sh
git add impl.sh && git commit -q -m "codex fix 1"
# codex-ran recorded at hash_B (different from critics at hash_A)
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
# Another fix + commit → hash_C
echo "fix for codex 2" >> impl.sh
git add impl.sh && git commit -q -m "codex fix 2"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 2: codex-ran at different hash than critics → still allows" \
  '! echo "$OUTPUT" | grep -q "deny"'

# Test: phase 2 — codex-ran exists but critics NEVER ran → still blocked
# Safety: codex-ran alone (without any critic evidence) must not bypass phase 1.
clean_evidence
cd "$TMPDIR_BASE"
echo "sneaky code" >> impl.sh
git add impl.sh && git commit -q -m "no critic run"
append_evidence "$SESSION_ID" "codex-ran" "COMPLETED" "$TMPDIR_BASE"
OUTPUT=$(echo "$(gate_input 'tmux-codex.sh --review main "test"')" | bash "$GATE")
assert "phase 2: codex-ran exists but critics never ran → blocked" \
  'echo "$OUTPUT" | grep -q "deny"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
