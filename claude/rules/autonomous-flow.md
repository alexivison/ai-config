# Autonomous Flow Reference

Detailed rules for continuous execution during TASK*.md implementation. See CLAUDE.md for summary.

## Core Principle

When executing a task from TASK*.md, **do not stop until PR is created**.

- **task-workflow:** No pause conditions. Handle NEEDS_DISCUSSION and HIGH/CRITICAL findings inline. See task-workflow/SKILL.md § No-Pause Rule.
- **bugfix-workflow:** May pause for investigation findings, NEEDS_DISCUSSION, or explicit blockers.

## The Flow

**Code workflow (task-workflow, bugfix-workflow):**
```
/write-tests → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

**Plan workflow (plan-workflow):**
```
/brainstorm (if needed) → /plan-implementation → codex → plan PR
```

## Decision Matrix

See [execution-core.md](execution-core.md) for the complete decision matrix including:
- When to continue vs pause (workflow-dependent — task-workflow never pauses)
- Valid pause conditions (bugfix-workflow and ad-hoc only)
- Sub-agent behavior rules

## Violation Patterns

These patterns indicate flow violation:

| Pattern | Why It's Wrong |
|---------|----------------|
| "Tests pass. GREEN phase complete." [stop] | Didn't continue to checkboxes/critics |
| "Code-critic approved." [stop] | Didn't continue to codex |
| "All checks pass." [stop] | Didn't continue to commit/PR |
| "Ready to create PR." [stop] | Should just create it |
| "Should I continue?" | Just continue |
| "Would you like me to..." | Just do it |

## Enforcement

**Code PRs** require markers from:
- `/pre-pr-verification` completion
- `code-critic` APPROVE verdict
- `codex` APPROVE verdict
- `test-runner` PASS verdict
- `check-runner` PASS/CLEAN verdict
- `security-scanner` completion (via /pre-pr-verification)

**Plan PRs** (branch suffix `-plan`) require:
- `codex` APPROVE verdict

Missing markers → `gh pr create` blocked.

## Checkpoint Markers

Created automatically by `agent-trace.sh`:

| Agent | Verdict | Marker |
|-------|---------|--------|
| code-critic | APPROVE | `/tmp/claude-code-critic-{session}` |
| codex | APPROVE | `/tmp/claude-codex-{session}` |
| test-runner | PASS | `/tmp/claude-tests-passed-{session}` |
| check-runner | PASS/CLEAN | `/tmp/claude-checks-passed-{session}` |
| /pre-pr-verification | Any | `/tmp/claude-pr-verified-{session}` |
| security-scanner | Any | `/tmp/claude-security-scanned-{session}` |

**Plan PRs** (branch suffix `-plan`) require `codex` marker only. Code PRs require all other markers.

## Post-PR Changes

If changes are needed after PR creation (e.g., user points out missing PLAN.md update):

**Option A — Same scope (recommended for small fixes):**
1. Make changes in same branch
2. Re-run `/pre-pr-verification` — MANDATORY, no exceptions
3. Amend commit with `--no-edit`
4. Force-push with `--force-with-lease`
5. PR auto-updates; verification evidence refreshed

**Option B — New scope (for substantial additions):**
1. Create new issue/task
2. Create new worktree/branch
3. Execute full workflow sequence
4. Create separate PR with cross-reference

**Rule:** No post-PR changes without re-verification. The claim "all checks pass" becomes false the moment unverified code is added.

**Violation pattern:**
```
User: "You forgot to update PLAN.md"
WRONG: Update PLAN.md → amend → push (no re-verification)
RIGHT: Update PLAN.md → /pre-pr-verification → amend → push
```
