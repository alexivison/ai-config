# Execution Core Reference

Shared execution sequence for all workflow skills. This is loaded on-demand by workflow skills.

## Core Sequence

```
/write-tests → implement → checkboxes → code-critic → architecture-critic → verification → commit → PR
```

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
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
| security-scanner | LOW/MEDIUM | Continue, note in PR | NO |
| security-scanner | HIGH/CRITICAL | Ask user for approval | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| plan-reviewer | APPROVE | Create plan PR | NO |
| plan-reviewer | REQUEST_CHANGES | Fix and re-run | NO |
| plan-reviewer | NEEDS_DISCUSSION | Show findings, ask user | YES |

## Valid Pause Conditions

Only pause for:
1. **Investigation findings** — debug-investigator, log-analyzer always require user review
2. **NEEDS_DISCUSSION** — From code-critic or architecture-critic
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Security issues** — HIGH/CRITICAL findings need user approval
5. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Agent Class | Examples | When to Pause | Show to User |
|-------------|----------|---------------|--------------|
| Investigation | debug-investigator, log-analyzer | Always | Full findings, then AskUserQuestion |
| Verification | test-runner, check-runner, security-scanner | Never (fix failures directly) | Summary only |
| Iterative | code-critic, plan-reviewer | NEEDS_DISCUSSION or 3 failures | Verdict each iteration |
| Advisory | architecture-critic | NEEDS_DISCUSSION only | Key findings (metrics, concerns) |

**Advisory behavior**: On REQUEST_CHANGES, check existing TASK*.md for duplicates. If covered, note and skip. Otherwise ask about creating a task. PR proceeds regardless.

## Verification Principle

Evidence before claims. Never state success without fresh proof.

| Claim | Required Evidence |
|-------|-------------------|
| "Tests pass" | Run test suite, show zero failures |
| "Lint clean" | Run linter, show zero errors |
| "Build succeeds" | Run build, show exit 0 |
| "Bug fixed" | Reproduce original symptom, show it passes |
| "Ready for PR" | Run /pre-pr-verification, show all checks pass |

**Red flags:** Tentative language ("should work"), planning commit/PR without checks, relying on previous runs.

## PR Gate Requirements

Before `gh pr create`:
- `/pre-pr-verification` invoked THIS session
- All checks passed with evidence
- security-scanner shows no CRITICAL/HIGH (or user approved)
- Verification summary in PR description

**Enforcement:** PR gate requires markers. Missing markers → blocked. See `~/.claude/rules/autonomous-flow.md` for marker details.
