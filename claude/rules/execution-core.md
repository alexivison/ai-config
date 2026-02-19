# Execution Core Reference

Shared execution sequence for all workflow skills. Bugfix-workflow omits the checkboxes step (no PLAN.md for bugfixes).

## Core Sequence

```
/write-tests → implement → checkboxes → [code-critic + minimizer] → wizard → /pre-pr-verification → commit → PR
```

## Review Governance

The review loop is the most expensive part of the workflow. These rules prevent waste from oscillation, scope creep, and unbounded iteration.

### Finding Severity Classification

The main agent classifies every critic/wizard finding before acting:

| Severity | Definition | Loop Behavior |
|----------|-----------|---------------|
| **Blocking** | Correctness bug, crash path, security HIGH/CRITICAL | Fix and re-run |
| **Non-blocking** | Style, consistency, "could be simpler", defensive edge cases | Note in issue ledger, do NOT re-run loop |
| **Out-of-scope** | Pre-existing code not touched by diff, requirements not in TASK file | Reject — log as backlog item if genuinely useful |

**Only blocking findings continue the review loop.** Non-blocking findings are noted and may be fixed in the same pass, but do not trigger a re-run of critics or wizard.

### Issue Ledger

The main agent maintains a mental ledger of all findings across iterations. Each finding has: source (critic/minimizer/wizard), file:line, claim, status (open/fixed/rejected), resolution.

**Rules:**
- A closed finding cannot be re-raised without new evidence (new code that wasn't there before).
- If a critic re-raises a closed finding, the main agent rejects it and proceeds.
- If a critic reverses its own prior feedback (e.g., "remove X" then "add X back"), that is **oscillation** — auto-escalate to the main agent's judgment. Do not chase the cycle.

### Iteration Caps (per severity tier)

| Finding Tier | Max Critic Iterations | Max Wizard Iterations | Then |
|-------------|----------------------|----------------------|------|
| Blocking (correctness/security) | 3 | 3 | NEEDS_DISCUSSION |
| Non-blocking (style/nit) | 1 | 1 | Accept or drop |

### Tiered Re-Review After Wizard Fixes

Not every wizard fix requires the full cascade. The main agent classifies the semantic impact:

| Fix Type | Example | Re-Review Required |
|----------|---------|-------------------|
| Targeted one-symbol swap | `in` → `Object.hasOwn`, typo fix | test-runner only |
| Logic change within function | Restructured control flow, added guard | test-runner + critics (diff-scoped) |
| New export, changed signature, security path | Added public API, modified auth | Full cascade (critics + wizard) |

### Scope Enforcement

Every sub-agent prompt MUST include scope boundaries from the TASK file:

```
SCOPE BOUNDARIES:
- IN SCOPE: {from TASK file}
- OUT OF SCOPE: {from TASK file}
- NON-GOALS: {from SPEC.md if available}
Findings on out-of-scope code are automatically rejected.
```

Pre-existing code not touched by the diff is non-blocking unless the change creates a new interaction with it.

### Diff-Scoped Reviews

Critics review the **diff**, not the entire codebase. Context files may be read for understanding, but findings must be on code that was added or modified in this task. Exceptions: security issues where existing code is newly reachable through the diff.

## Decision Matrix

| Step | Outcome | Next Action | Pause? |
|------|---------|-------------|--------|
| /write-tests | Tests written (RED) | Implement code | NO |
| Implement | Code written | Update checkboxes | NO |
| Checkboxes | Updated (TASK + PLAN) | Run code-critic + minimizer (parallel) | NO |
| code-critic | APPROVE | Wait for minimizer | NO |
| code-critic | REQUEST_CHANGES (blocking) | Fix and re-run both critics | NO |
| code-critic | REQUEST_CHANGES (non-blocking only) | Note findings, wait for minimizer | NO |
| code-critic | NEEDS_DISCUSSION / oscillation / cap hit | Ask user | YES |
| minimizer | APPROVE | Wait for code-critic | NO |
| minimizer | REQUEST_CHANGES (blocking) | Fix and re-run both critics | NO |
| minimizer | REQUEST_CHANGES (non-blocking only) | Note findings, wait for code-critic | NO |
| minimizer | NEEDS_DISCUSSION / oscillation / cap hit | Ask user | YES |
| code-critic + minimizer | No blocking findings remain (both APPROVE, or all remaining findings are non-blocking) | Run wizard | NO |
| wizard | APPROVE (no changes) | Run /pre-pr-verification | NO |
| wizard | APPROVE (with changes) | Classify fix impact → tiered re-review | NO |
| wizard | REQUEST_CHANGES (blocking) | Fix → tiered re-review → re-run wizard | NO |
| wizard | REQUEST_CHANGES (non-blocking only) | Note findings, proceed to /pre-pr-verification | NO |
| wizard | NEEDS_DISCUSSION | Ask user | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| security-scanner | HIGH/CRITICAL | Ask user | YES |

## Valid Pause Conditions

1. **Investigation findings** — wizard (debugging) always requires user review
2. **NEEDS_DISCUSSION** — From code-critic, minimizer, or wizard
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Oscillation detected** — Critic reverses its own prior feedback
5. **Iteration cap hit** — Per severity tier (see above)
6. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Class | When to Pause | Show to User |
|-------|---------------|--------------|
| Investigation (wizard debug) | Always | Full findings |
| Verification (test-runner, check-runner, security-scanner) | Never | Summary only |
| Iterative (code-critic, minimizer, wizard) | NEEDS_DISCUSSION, oscillation, or cap hit | Verdict each iteration |

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

Before `gh pr create`: /pre-pr-verification invoked THIS session, all checks passed, wizard APPROVE, verification summary in PR description. See `autonomous-flow.md` for marker details.
