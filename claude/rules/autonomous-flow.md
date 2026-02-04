# Autonomous Flow Reference

Detailed rules for continuous execution during TASK*.md implementation. See CLAUDE.md for summary.

## Core Principle

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

**Code workflow (task-workflow, bugfix-workflow):**
```
/write-tests → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

**Plan workflow (plan-workflow):**
```
/brainstorm (if needed) → /plan-implementation → plan-reviewer → codex → plan PR
```

## Decision Matrix

See [execution-core.md](execution-core.md) for the complete decision matrix including:
- When to continue vs pause
- Valid pause conditions
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
<!-- - `security-scanner` completion  # Codex covers basic security -->

**Plan PRs** (branch suffix `-plan`) require:
- `plan-reviewer` APPROVE verdict
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
| plan-reviewer | APPROVE | `/tmp/claude-plan-reviewer-{session}` |
<!-- | security-scanner | Any | `/tmp/claude-security-scanned-{session}` |  # Codex covers basic security -->

**Plan PRs** (branch suffix `-plan`) require `plan-reviewer` + `codex` markers. Code PRs require all other markers.
