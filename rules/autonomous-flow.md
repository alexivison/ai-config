# Autonomous Flow Reference

Detailed rules for continuous execution during TASK*.md implementation. See CLAUDE.md for summary.

## Core Principle

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

**Code workflow (task-workflow, bugfix-workflow):**
```
/write-tests → implement → GREEN → checkboxes → /pre-pr-verification → commit → PR
```

**Note:** Code review and arch review are now part of `/pre-pr-verification`, not separate steps. This is faster because reviews run once at the end.

**Plan workflow (plan-workflow):**
```
cli-orchestrator (plan creation) → cli-orchestrator (plan review) → plan PR
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
| "Tests pass. GREEN phase complete." [stop] | Didn't continue to checkboxes |
| "Checkboxes updated." [stop] | Didn't continue to /pre-pr-verification |
| "All checks pass." [stop] | Didn't continue to commit/PR |
| "Ready to create PR." [stop] | Should just create it |
| "Should I continue?" | Just continue |
| "Would you like me to..." | Just do it |

## Enforcement

**Code PRs** require markers from:
- `/pre-pr-verification` completion
- `security-scanner` completion
- `cli-orchestrator (review)` APPROVE verdict
- `test-runner` PASS verdict
- `check-runner` PASS/CLEAN verdict

**Plan PRs** (branch suffix `-plan`) require:
- `cli-orchestrator (plan review)` APPROVE verdict

Missing markers → `gh pr create` blocked.

## Checkpoint Markers

Created automatically by `agent-trace.sh`:

| Agent | Verdict | Marker |
|-------|---------|--------|
| cli-orchestrator (review) | APPROVE | `/tmp/claude-code-critic-{session}` |
| cli-orchestrator (arch) | Any | `/tmp/claude-architecture-reviewed-{session}` |
| cli-orchestrator (plan review) | APPROVE | `/tmp/claude-plan-reviewer-{session}` |
| test-runner | PASS | `/tmp/claude-tests-passed-{session}` |
| check-runner | PASS/CLEAN | `/tmp/claude-checks-passed-{session}` |
| security-scanner | Any | `/tmp/claude-security-scanned-{session}` |
| /pre-pr-verification | Any | `/tmp/claude-pr-verified-{session}` |

**Plan PRs** (branch suffix `-plan`) only require plan review marker. Code PRs require all other markers.
