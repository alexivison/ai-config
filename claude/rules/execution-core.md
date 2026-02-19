# Execution Core Reference

Shared execution sequence for all workflow skills. Bugfix-workflow omits the checkboxes step (no PLAN.md for bugfixes).

## Core Sequence

```
/write-tests → implement → checkboxes → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Update checkboxes | NO |
| Checkboxes | Updated (TASK + PLAN) | Run code-critic + minimizer (parallel) | NO |
| code-critic | APPROVE | Wait for minimizer | NO |
| code-critic | REQUEST_CHANGES | Fix and re-run both critics | NO |
| code-critic | NEEDS_DISCUSSION / 5th iteration | Ask user | YES |
| minimizer | APPROVE | Wait for code-critic | NO |
| minimizer | REQUEST_CHANGES | Fix and re-run both critics | NO |
| minimizer | NEEDS_DISCUSSION / 5th iteration | Ask user | YES |
| code-critic + minimizer | Both APPROVE | Run codex | NO |
| codex | APPROVE (no changes) | Run /pre-pr-verification | NO |
| codex | APPROVE (with changes) | Re-run code-critic + minimizer; re-run codex unless changes were style-only | NO |
| codex | REQUEST_CHANGES | Fix, re-run code-critic + minimizer, then codex | NO |
| codex | NEEDS_DISCUSSION | Ask user | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| security-scanner | HIGH/CRITICAL | Ask user | YES |

## Valid Pause Conditions

1. **Investigation findings** — codex (debugging) always requires user review
2. **NEEDS_DISCUSSION** — From code-critic, minimizer, or codex
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Class | When to Pause | Show to User |
|-------|---------------|--------------|
| Investigation (codex debug) | Always | Full findings |
| Verification (test-runner, check-runner, security-scanner) | Never | Summary only |
| Iterative (code-critic, minimizer, codex) | NEEDS_DISCUSSION or 5th iteration | Verdict each iteration |

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

Before `gh pr create`: /pre-pr-verification invoked THIS session, all checks passed, codex APPROVE (via `codex-verdict.sh`), verification summary in PR description. See `autonomous-flow.md` for marker details.
