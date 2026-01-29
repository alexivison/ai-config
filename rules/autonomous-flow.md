# Autonomous Flow Reference

Detailed rules for continuous execution during TASK*.md implementation. See CLAUDE.md for summary.

## Core Principle

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

```
/write-tests → implement → checkboxes → code-critic → architecture-critic → verification → commit → PR
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
| "Code-critic approved." [stop] | Didn't continue to architecture-critic |
| "All checks pass." [stop] | Didn't continue to commit/PR |
| "Ready to create PR." [stop] | Should just create it |
| "Should I continue?" | Just continue |
| "Would you like me to..." | Just do it |

## Enforcement

PR gate requires markers from:
- `/pre-pr-verification` completion
- `security-scanner` completion
- `code-critic` APPROVE verdict
- `test-runner` PASS verdict
- `check-runner` PASS/CLEAN verdict

Missing markers → `gh pr create` blocked.

## Checkpoint Markers

Created automatically by `agent-trace.sh`:

| Agent | Verdict | Marker |
|-------|---------|--------|
| code-critic | APPROVE | `/tmp/claude-code-critic-{session}` |
| test-runner | PASS | `/tmp/claude-tests-passed-{session}` |
| check-runner | PASS/CLEAN | `/tmp/claude-checks-passed-{session}` |
| security-scanner | Any | `/tmp/claude-security-scanned-{session}` |
| /pre-pr-verification | Any | `/tmp/claude-pr-verified-{session}` |
