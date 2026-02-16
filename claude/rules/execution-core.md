# Execution Core Reference

Shared execution sequence for all workflow skills.

## Core Sequence

```
/write-tests → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR
```

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Update checkboxes | NO |
| Checkboxes | Updated (TASK + PLAN) | Run code-critic | NO |
| code-critic | APPROVE | Run codex | NO |
| code-critic | REQUEST_CHANGES | Fix and re-run | NO |
| code-critic | NEEDS_DISCUSSION | Ask user | YES |
| code-critic | 3rd failure | Ask user | YES |
| codex | APPROVE (no changes) | Run /pre-pr-verification | NO |
| codex | APPROVE (with changes) | Re-run code-critic | NO |
| codex | REQUEST_CHANGES | Fix and re-run | NO |
| codex | NEEDS_DISCUSSION | Ask user | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| codex (plan) | APPROVE | Create plan PR | NO |
| codex (plan) | REQUEST_CHANGES | Fix and re-run | NO |
| codex (plan) | NEEDS_DISCUSSION | Ask user | YES |
| security-scanner | HIGH/CRITICAL | Ask user | YES |

## Valid Pause Conditions

1. **Investigation findings** — codex (debugging), gemini always require user review
2. **NEEDS_DISCUSSION** — From code-critic or codex
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Class | When to Pause | Show to User |
|-------|---------------|--------------|
| Investigation (codex debug, gemini) | Always | Full findings |
| Verification (test-runner, check-runner, security-scanner) | Never | Summary only |
| Iterative (code-critic, codex) | NEEDS_DISCUSSION or 3 failures | Verdict each iteration |

## Verification Principle

Evidence before claims. Never state success without fresh proof.

| Claim | Evidence |
|-------|----------|
| "Tests pass" | test-runner, zero failures |
| "Lint clean" | check-runner, zero errors |
| "Bug fixed" | Reproduce symptom, show it passes |
| "Ready for PR" | /pre-pr-verification, all checks pass |

**Red flags:** Tentative language ("should work"), planning commit without checks, relying on previous runs.

## PR Gate

Before `gh pr create`: /pre-pr-verification invoked THIS session, all checks passed, codex APPROVE, verification summary in PR description. See `autonomous-flow.md` for marker details.
