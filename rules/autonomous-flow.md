# Autonomous Flow Reference

Detailed rules for continuous execution during TASK*.md implementation. See CLAUDE.md for summary.

## Core Principle

When executing a task from TASK*.md, **do not stop until PR is created** (or a valid pause condition is met).

## The Flow

```
/write-tests → implement → checkboxes → code-critic → architecture-critic → verification → commit → PR
```

## Decision Matrix: Continue or Pause?

| Current Step | Outcome | Next Action | Pause? |
|--------------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Update checkboxes | NO |
| Checkboxes | Updated | Run code-critic | NO |
| code-critic | APPROVE | Run architecture-critic | NO |
| code-critic | REQUEST_CHANGES | Fix and re-run | NO |
| code-critic | NEEDS_DISCUSSION | Show findings, ask user | YES |
| code-critic | 3rd failure | Document attempts, ask user | YES |
| architecture-critic | APPROVE/SKIP | Run verification | NO |
| architecture-critic | REQUEST_CHANGES | Note for future task, continue | NO |
| architecture-critic | NEEDS_DISCUSSION | Show findings, ask user | YES |
| test-runner | PASS | Continue to check-runner | NO |
| test-runner | FAIL | Fix and re-run | NO |
| check-runner | PASS/CLEAN | Run security-scanner | NO |
| check-runner | FAIL | Fix and re-run | NO |
| security-scanner | CLEAN | Run /pre-pr-verification | NO |
| security-scanner | ISSUES (LOW/MEDIUM) | Continue, note in PR | NO |
| security-scanner | ISSUES (HIGH/CRITICAL) | Ask user for approval | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| debug-investigator | Any | Show findings, ask user | YES |
| log-analyzer | Any | Show findings, ask user | YES |

## Valid Pause Conditions

Only pause for:
1. **Investigation findings** - debug-investigator, log-analyzer always require user review
2. **NEEDS_DISCUSSION** - From code-critic or architecture-critic
3. **3 strikes** - 3 failed fix attempts on same issue
4. **Security issues** - HIGH/CRITICAL findings need user approval
5. **Explicit blockers** - Missing dependencies, unclear requirements

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
