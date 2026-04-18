#!/usr/bin/env bash
# Tests for agent-transport, the shared role-based transport skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRANSPORT_SCRIPT="$SCRIPT_DIR/../scripts/tmux-companion.sh"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_grep() {
  local desc="$1" file="$2" pattern="$3" negate="${4:-}"
  if [[ "$negate" == "!" ]]; then
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
      PASS=$((PASS + 1)); echo "  [PASS] $desc"
    else
      FAIL=$((FAIL + 1)); echo "  [FAIL] $desc"
    fi
  else
    if grep -q "$pattern" "$file" 2>/dev/null; then
      PASS=$((PASS + 1)); echo "  [PASS] $desc"
    else
      FAIL=$((FAIL + 1)); echo "  [FAIL] $desc"
    fi
  fi
}

assert() {
  local desc="$1"
  if eval "$2"; then
    PASS=$((PASS + 1)); echo "  [PASS] $desc"
  else
    FAIL=$((FAIL + 1)); echo "  [FAIL] $desc"
  fi
}

# Source the render function directly (avoid party-lib dependency)
_render_template() {
  local template_file="$1"; shift
  local content
  content=$(cat "$template_file")
  local key val
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    content="${content//\{\{$key\}\}/$val}"
  done
  echo "$content" | grep -v '^{{.*}}$'
}

# ── Template file existence ──────────────────────────────────────────

echo "=== Template file existence ==="

assert "review.md template exists" \
  "[ -f '$TEMPLATE_DIR/review.md' ]"

assert "plan-review.md template exists" \
  "[ -f '$TEMPLATE_DIR/plan-review.md' ]"

# ── Review template rendering (basic, no conditional sections) ───────

echo "=== Review template rendering ==="

_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=main" \
  "TITLE=Test PR" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=" \
  "DISPUTE_SECTION=" \
  "REREVEW_SECTION=" > "$TMPDIR_TEST/review-basic.txt"

assert_grep "review: contains work_dir" "$TMPDIR_TEST/review-basic.txt" "/tmp/test-repo"
assert_grep "review: contains base branch" "$TMPDIR_TEST/review-basic.txt" "against main"
assert_grep "review: contains title" "$TMPDIR_TEST/review-basic.txt" "Test PR"
assert_grep "review: contains findings file path" "$TMPDIR_TEST/review-basic.txt" "/tmp/findings.toon"
assert_grep "review: contains VERDICT instruction" "$TMPDIR_TEST/review-basic.txt" "VERDICT: APPROVED"
assert_grep "review: contains notify command" "$TMPDIR_TEST/review-basic.txt" "echo done"
assert_grep "review: no unreplaced placeholders" "$TMPDIR_TEST/review-basic.txt" "{{" "!"
assert_grep "review: empty scope section stripped" "$TMPDIR_TEST/review-basic.txt" "^## Scope$" "!"

# ── Review template with scope section ───────────────────────────────

echo "=== Review template with scope ==="

_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=main" \
  "TITLE=Scoped review" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=## Scope -- Only review auth module changes." \
  "DISPUTE_SECTION=" \
  "REREVEW_SECTION=" > "$TMPDIR_TEST/review-scope.txt"

assert_grep "review+scope: contains scope header" "$TMPDIR_TEST/review-scope.txt" "## Scope"
assert_grep "review+scope: contains scope content" "$TMPDIR_TEST/review-scope.txt" "auth module"

# ── Review template with dispute section ─────────────────────────────

echo "=== Review template with dispute ==="

_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=main" \
  "TITLE=Dispute review" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=" \
  "DISPUTE_SECTION=## Dispute Context -- Read dismissed findings from: /tmp/dispute.md" \
  "REREVEW_SECTION=" > "$TMPDIR_TEST/review-dispute.txt"

assert_grep "review+dispute: contains dispute section" "$TMPDIR_TEST/review-dispute.txt" "Dispute Context"
assert_grep "review+dispute: contains dispute file reference" "$TMPDIR_TEST/review-dispute.txt" "/tmp/dispute.md"

# ── Review template with re-review section ───────────────────────────

echo "=== Review template with re-review ==="

_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=main" \
  "TITLE=Re-review" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=" \
  "DISPUTE_SECTION=" \
  "REREVEW_SECTION=## Re-review -- Prior findings at: /tmp/prior.toon" > "$TMPDIR_TEST/review-rerev.txt"

assert_grep "review+re-review: contains re-review section" "$TMPDIR_TEST/review-rerev.txt" "Re-review"
assert_grep "review+re-review: contains prior findings path" "$TMPDIR_TEST/review-rerev.txt" "/tmp/prior.toon"

# ── Review template with all sections ────────────────────────────────

echo "=== Review template with all sections ==="

_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=develop" \
  "TITLE=Full review" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=## Scope -- Auth module only." \
  "DISPUTE_SECTION=## Dispute Context -- F2 dismissed as out-of-scope." \
  "REREVEW_SECTION=## Re-review -- Prior at /tmp/p.toon" > "$TMPDIR_TEST/review-all.txt"

assert_grep "review+all: scope present" "$TMPDIR_TEST/review-all.txt" "Auth module"
assert_grep "review+all: dispute present" "$TMPDIR_TEST/review-all.txt" "F2 dismissed"
assert_grep "review+all: re-review present" "$TMPDIR_TEST/review-all.txt" "Prior at"
assert_grep "review+all: base=develop" "$TMPDIR_TEST/review-all.txt" "against develop"
assert_grep "review+all: no unreplaced placeholders" "$TMPDIR_TEST/review-all.txt" "{{" "!"

# ── Plan review template rendering ──────────────────────────────────

echo "=== Plan review template rendering ==="

_render_template "$TEMPLATE_DIR/plan-review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "PLAN_PATH=/tmp/PLAN.md" \
  "FINDINGS_FILE=/tmp/plan-findings.toon" \
  "NOTIFY_CMD=echo plan-done" > "$TMPDIR_TEST/plan-review.txt"

assert_grep "plan-review: contains work_dir" "$TMPDIR_TEST/plan-review.txt" "/tmp/test-repo"
assert_grep "plan-review: contains plan path" "$TMPDIR_TEST/plan-review.txt" "/tmp/PLAN.md"
assert_grep "plan-review: contains findings file" "$TMPDIR_TEST/plan-review.txt" "/tmp/plan-findings.toon"
assert_grep "plan-review: contains notify command" "$TMPDIR_TEST/plan-review.txt" "plan-done"
assert_grep "plan-review: contains evaluation criteria" "$TMPDIR_TEST/plan-review.txt" "Feasibility"
assert_grep "plan-review: no unreplaced placeholders" "$TMPDIR_TEST/plan-review.txt" "{{" "!"

# ── Multiline conditional sections (F2 regression) ──────────────────

echo "=== Multiline conditional sections ==="

# Build a scope section using printf (same as tmux-companion.sh does).
MULTILINE_SCOPE=$(printf '## Scope\n\nOnly review auth module changes.\nFindings outside this scope should be omitted.')
_render_template "$TEMPLATE_DIR/review.md" \
  "WORK_DIR=/tmp/test-repo" \
  "BASE=main" \
  "TITLE=Multiline test" \
  "FINDINGS_FILE=/tmp/findings.toon" \
  "NOTIFY_CMD=echo done" \
  "SCOPE_SECTION=$MULTILINE_SCOPE" \
  "DISPUTE_SECTION=" \
  "REREVEW_SECTION=" > "$TMPDIR_TEST/review-multiline.txt"

# The scope section should span multiple lines (real newlines, not literal \n)
assert_grep "multiline: scope header on own line" "$TMPDIR_TEST/review-multiline.txt" "^## Scope$"
assert_grep "multiline: scope body on separate line" "$TMPDIR_TEST/review-multiline.txt" "^Only review auth module"
assert_grep "multiline: no literal backslash-n" "$TMPDIR_TEST/review-multiline.txt" '\\n' "!"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
