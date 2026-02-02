# Execution Core Reference

Shared execution sequence for all workflow skills. This is loaded on-demand by workflow skills.

## Core Sequence

```
/write-tests → implement → GREEN → checkboxes → /pre-pr-verification → commit → PR
```

**Note:** Code review and architecture review are now part of `/pre-pr-verification`, not separate steps.

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Run test-runner (GREEN) | NO |
| test-runner (GREEN) | PASS | Update checkboxes | NO |
| test-runner (GREEN) | FAIL | Fix and re-run | NO |
| Checkboxes | Updated | Run /pre-pr-verification | NO |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Code review REQUEST_CHANGES | Fix and re-run | NO |
| /pre-pr-verification | Code review NEEDS_DISCUSSION | Show findings, ask user | YES |
| /pre-pr-verification | Code review 3rd failure | Document attempts, ask user | YES |
| /pre-pr-verification | Arch review REQUEST_CHANGES | Note for future task, continue | NO |
| /pre-pr-verification | Arch review NEEDS_DISCUSSION | Show findings, ask user | YES |
| /pre-pr-verification | test-runner FAIL | Fix and re-run | NO |
| /pre-pr-verification | check-runner FAIL | Fix and re-run | NO |
| /pre-pr-verification | security HIGH/CRITICAL | Ask user for approval | YES |
| cli-orchestrator (plan review) | APPROVE | Create plan PR | NO |
| cli-orchestrator (plan review) | REQUEST_CHANGES | Fix and re-run | NO |
| cli-orchestrator (plan review) | NEEDS_DISCUSSION | Show findings, ask user | YES |

## Valid Pause Conditions

Only pause for:
1. **Investigation findings** — cli-orchestrator (investigate), log-analyzer always require user review
2. **NEEDS_DISCUSSION** — From cli-orchestrator review/arch/plan modes
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Security issues** — HIGH/CRITICAL findings need user approval
5. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Agent Class | Examples | When to Pause | Show to User |
|-------------|----------|---------------|--------------|
| Investigation | cli-orchestrator (investigate), log-analyzer | Always | Full findings, then AskUserQuestion |
| Verification | test-runner, check-runner, security-scanner | Never (fix failures directly) | Summary only |
| Iterative | cli-orchestrator (review), cli-orchestrator (plan review) | NEEDS_DISCUSSION or 3 failures | Verdict each iteration |
| Advisory | cli-orchestrator (arch) | NEEDS_DISCUSSION only | Key findings (metrics, concerns) |

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
