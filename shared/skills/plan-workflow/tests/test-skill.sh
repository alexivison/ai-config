#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_ROOT/../../.." && pwd)"

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

assert_readlink() {
  local desc="$1" path="$2" expected="$3" actual=""
  if [[ -L "$path" ]]; then
    actual="$(readlink "$path")"
  fi
  if [[ "$actual" == "$expected" ]]; then
    PASS=$((PASS + 1))
    echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $desc"
  fi
}

assert_grep() {
  local desc="$1" file="$2" pattern="$3" negate="${4:-}"
  if [[ "$negate" == "!" ]]; then
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
      PASS=$((PASS + 1))
      echo "  [PASS] $desc"
    else
      FAIL=$((FAIL + 1))
      echo "  [FAIL] $desc"
    fi
  else
    if grep -q "$pattern" "$file" 2>/dev/null; then
      PASS=$((PASS + 1))
      echo "  [PASS] $desc"
    else
      FAIL=$((FAIL + 1))
      echo "  [FAIL] $desc"
    fi
  fi
}

echo "=== Shared skill files ==="

assert "shared SKILL.md exists" \
  "[ -f '$SKILL_ROOT/SKILL.md' ]"

for template in create-plan.md revise-plan.md spec.md design.md plan.md task.md; do
  assert "template exists: $template" \
    "[ -f '$SKILL_ROOT/templates/$template' ]"
done

echo "=== Shared skill paths ==="

assert_grep "shared SKILL.md uses no ~/.claude paths" "$SKILL_ROOT/SKILL.md" '~/.claude' "!"
assert_grep "shared SKILL.md uses no ~/.codex paths" "$SKILL_ROOT/SKILL.md" '~/.codex' "!"
assert_grep "shared SKILL.md uses no ~/.pi paths" "$SKILL_ROOT/SKILL.md" '~/.pi' "!"
assert_grep "shared SKILL.md documents primary-agent placeholder" "$SKILL_ROOT/SKILL.md" '<primary-agent-skill-root>'
assert_grep "shared SKILL.md documents companion-agent placeholder" "$SKILL_ROOT/SKILL.md" '<companion-agent-skill-root>'

assert_grep "create-plan uses relative plan template path" "$SKILL_ROOT/templates/create-plan.md" './templates/plan.md'
assert_grep "create-plan uses relative task template path" "$SKILL_ROOT/templates/create-plan.md" './templates/task.md'
assert_grep "revise-plan uses relative canonical templates path" "$SKILL_ROOT/templates/revise-plan.md" './templates/'
assert_grep "prompt templates avoid ~/.claude" "$SKILL_ROOT/templates/create-plan.md" '~/.claude' "!"
assert_grep "prompt templates avoid ~/.codex" "$SKILL_ROOT/templates/create-plan.md" '~/.codex' "!"
assert_grep "prompt templates avoid ~/.pi" "$SKILL_ROOT/templates/create-plan.md" '~/.pi' "!"
assert_grep "revise template avoids ~/.claude" "$SKILL_ROOT/templates/revise-plan.md" '~/.claude' "!"
assert_grep "revise template avoids ~/.codex" "$SKILL_ROOT/templates/revise-plan.md" '~/.codex' "!"
assert_grep "revise template avoids ~/.pi" "$SKILL_ROOT/templates/revise-plan.md" '~/.pi' "!"

echo "=== Agent-local wiring ==="

legacy_codex_dir="$REPO_ROOT/codex/skills/plann""ing"

assert "claude plan-workflow is a symlink" \
  "[ -L '$REPO_ROOT/claude/skills/plan-workflow' ]"
assert_readlink "claude plan-workflow points at shared skill" \
  "$REPO_ROOT/claude/skills/plan-workflow" "../../shared/skills/plan-workflow"
assert "codex plan-workflow is a symlink" \
  "[ -L '$REPO_ROOT/codex/skills/plan-workflow' ]"
assert_readlink "codex plan-workflow points at shared skill" \
  "$REPO_ROOT/codex/skills/plan-workflow" "../../shared/skills/plan-workflow"
assert "pi plan-workflow is a symlink" \
  "[ -L '$REPO_ROOT/pi/agent/skills/plan-workflow' ]"
assert_readlink "pi plan-workflow points at shared skill" \
  "$REPO_ROOT/pi/agent/skills/plan-workflow" "../../../shared/skills/plan-workflow"
assert "legacy codex planning path removed" \
  "[ ! -e '$legacy_codex_dir' ]"

echo "=== Stale reference cleanup ==="

legacy_path_one="codex/skills/plann""ing"
legacy_path_two="skills/plann""ing/"

assert "no stale legacy codex planning path references remain" \
  "! rg -n --fixed-strings \"$legacy_path_one\" '$REPO_ROOT' -g '!shared/skills/plan-workflow/tests/test-skill.sh' >/dev/null"
assert "no stale legacy planning template path references remain" \
  "! rg -n --fixed-strings \"$legacy_path_two\" '$REPO_ROOT' -g '!shared/skills/plan-workflow/tests/test-skill.sh' >/dev/null"

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
