# Execution Core Reference

Shared execution sequence for all workflow skills. This is loaded on-demand by workflow skills.

## Core Sequence

```
/write-tests → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Update checkboxes | NO |
| Checkboxes | Updated | Run code-critic | NO |
| code-critic | APPROVE | Run codex | NO |
| code-critic | REQUEST_CHANGES | Fix and re-run | NO |
| code-critic | NEEDS_DISCUSSION | Show findings, ask user | YES |
| code-critic | 3rd failure | Document attempts, ask user | YES |
| codex | APPROVE (no changes) | Run /pre-pr-verification | NO |
| codex | APPROVE (with changes) | Re-run code-critic | NO |
| codex | REQUEST_CHANGES | Fix and re-run | NO |
| codex | NEEDS_DISCUSSION | Ask user | YES |
| code-critic (post-codex) | REQUEST_CHANGES | Fix conventions, proceed | NO |
| test-runner | PASS | Continue to check-runner | NO |
| test-runner | FAIL | Fix and re-run | NO |
| check-runner | PASS/CLEAN | (handled by /pre-pr-verification) | NO |
| check-runner | FAIL | Fix and re-run | NO |
<!-- | security-scanner | CLEAN | Run /pre-pr-verification | NO | -->
<!-- | security-scanner | LOW/MEDIUM | Continue, note in PR | NO | -->
<!-- | security-scanner | HIGH/CRITICAL | Ask user for approval | YES | -->
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| plan-reviewer | APPROVE | Run codex (plan review) | NO |
| plan-reviewer | REQUEST_CHANGES | Fix and re-run | NO |
| plan-reviewer | NEEDS_DISCUSSION | Show findings, ask user | YES |
| codex (plan) | APPROVE | Create plan PR | NO |
| codex (plan) | REQUEST_CHANGES | Fix and re-run | NO |
| codex (plan) | NEEDS_DISCUSSION | Show findings, ask user | YES |

## Valid Pause Conditions

Only pause for:
1. **Investigation findings** — debug-investigator, log-analyzer always require user review
2. **NEEDS_DISCUSSION** — From code-critic or codex
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Agent Class | Examples | When to Pause | Show to User |
|-------------|----------|---------------|--------------|
| Investigation | debug-investigator, log-analyzer | Always | Full findings, then AskUserQuestion |
| Verification | test-runner, check-runner | Never (fix failures directly) | Summary only |
| Iterative | code-critic, codex, plan-reviewer | NEEDS_DISCUSSION or 3 failures | Verdict each iteration |

<!-- security-scanner moved to optional; Codex covers basic security review -->

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
- codex APPROVE verdict
- Verification summary in PR description

**Enforcement:** PR gate requires markers. Missing markers → blocked. See `~/.claude/rules/autonomous-flow.md` for marker details.
