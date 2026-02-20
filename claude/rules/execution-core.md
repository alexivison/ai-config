# Execution Core Reference

Shared execution sequence for all workflow skills. Bugfix-workflow omits the checkboxes step (no PLAN.md for bugfixes).

## Core Sequence

```
/write-tests → implement → checkboxes → self-review → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

## Self-Review

Before invoking external reviewers, the main agent performs a self-review to catch obvious issues cheaply. This prevents wasting sub-agent resources on code that clearly needs more work.

### Checklist

1. **Acceptance criteria met?** — Re-read TASK file acceptance criteria. Does the implementation satisfy each one?
2. **Tests cover acceptance criteria?** — Each acceptance criterion has at least one test exercising it.
3. **No debug artifacts?** — No `console.log`, `TODO: remove`, commented-out code, or hardcoded test values.
4. **Diff matches intent?** — Run `git diff` and verify every changed line is intentional and in-scope.
5. **No obvious bugs?** — Null checks, off-by-one, missing error handling at system boundaries.

### Output Format

```
## Self-Review
- [x] Acceptance criteria met (list each: criterion → evidence)
- [x] Tests cover acceptance criteria
- [x] No debug artifacts
- [x] Diff matches intent
- [x] No obvious bugs
PASS — proceeding to critics
```

If any check fails, fix before proceeding. Do not invoke critics on code you know is incomplete.

## Marker Invalidation

The `marker-invalidate.sh` hook automatically deletes review markers when implementation files are edited. This prevents stale approvals from surviving code changes.

### How It Works

- **Trigger:** PostToolUse on Edit|Write
- **Skips:** `.md`, `/tmp/`, `.log`, `.jsonl` files (non-implementation)
- **Deletes:** code-critic, minimizer, codex, codex-ran, tests-passed, checks-passed, pr-verified, security-scanned markers
- **Effect:** After any implementation edit, all review steps must be re-run

### Implications

- Editing code after codex approval invalidates the approval — you must re-run the review cascade
- Fixing a critic finding and re-running critics is the normal flow (markers deleted, then re-created)
- Checkpoint markers are evidence of review — they cannot be manually created or faked

## Review Governance

The review loop is the most expensive part of the workflow. These rules prevent waste from oscillation, scope creep, and unbounded iteration.

### Finding Severity Classification

The main agent classifies every critic/codex finding before acting:

| Severity | Definition | Loop Behavior |
|----------|-----------|---------------|
| **Blocking** | Correctness bug, crash path, security HIGH/CRITICAL | Fix and re-run |
| **Non-blocking** | Style, consistency, "could be simpler", defensive edge cases | Note in issue ledger, do NOT re-run loop |
| **Out-of-scope** | Pre-existing code not touched by diff, requirements not in TASK file | Reject — log as backlog item if genuinely useful |

**Only blocking findings continue the review loop.** Non-blocking findings are noted and may be fixed in the same pass, but do not trigger a re-run of critics or codex.

### Issue Ledger

The main agent maintains a mental ledger of all findings across iterations. Each finding has: source (critic/minimizer/codex), file:line, claim, status (open/fixed/rejected), resolution.

**Rules:**
- A closed finding cannot be re-raised without new evidence (new code that wasn't there before).
- If a critic re-raises a closed finding, the main agent rejects it and proceeds.
- If a critic reverses its own prior feedback (e.g., "remove X" then "add X back"), that is **oscillation** — auto-escalate to the main agent's judgment. Do not chase the cycle.

### Iteration Caps (per severity tier)

| Finding Tier | Max Critic Iterations | Max Codex Iterations | Then |
|-------------|----------------------|----------------------|------|
| Blocking (correctness/security) | 3 | 3 | NEEDS_DISCUSSION |
| Non-blocking (style/nit) | 1 | 1 | Accept or drop |

### Tiered Re-Review After Codex Fixes

Not every codex fix requires the full cascade. The main agent classifies the semantic impact:

| Fix Type | Example | Re-Review Required |
|----------|---------|-------------------|
| Targeted one-symbol swap | `in` → `Object.hasOwn`, typo fix | test-runner only |
| Logic change within function | Restructured control flow, added guard | test-runner + critics (diff-scoped) |
| New export, changed signature, security path | Added public API, modified auth | Full cascade (critics + codex) |

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
| Checkboxes | Updated (TASK + PLAN) | Run self-review | NO |
| Self-review | PASS | Run code-critic + minimizer (parallel) | NO |
| Self-review | FAIL | Fix issues, re-run self-review | NO |
| code-critic | APPROVE | Wait for minimizer | NO |
| code-critic | REQUEST_CHANGES (blocking) | Fix and re-run both critics | NO |
| code-critic | REQUEST_CHANGES (non-blocking only) | Note findings, wait for minimizer | NO |
| code-critic | NEEDS_DISCUSSION / oscillation / cap hit | Ask user | YES |
| minimizer | APPROVE | Wait for code-critic | NO |
| minimizer | REQUEST_CHANGES (blocking) | Fix and re-run both critics | NO |
| minimizer | REQUEST_CHANGES (non-blocking only) | Note findings, wait for code-critic | NO |
| minimizer | NEEDS_DISCUSSION / oscillation / cap hit | Ask user | YES |
| code-critic + minimizer | No blocking findings remain (both APPROVE, or all remaining findings are non-blocking) | Run codex | NO |
| codex | APPROVE (no changes) | Run /pre-pr-verification | NO |
| codex | APPROVE (with changes) | Classify fix impact → tiered re-review | NO |
| codex | REQUEST_CHANGES (blocking) | Fix → tiered re-review → re-run codex | NO |
| codex | REQUEST_CHANGES (non-blocking only) | Note findings, proceed to /pre-pr-verification | NO |
| codex | NEEDS_DISCUSSION | Ask user | YES |
| /pre-pr-verification | All pass | Create commit and PR | NO |
| /pre-pr-verification | Failures | Fix and re-run | NO |
| security-scanner | HIGH/CRITICAL | Ask user | YES |
| Edit/Write (impl file) | Markers invalidated (hook) | Re-run invalidated steps before PR | NO |
| codex-verdict.sh approve | No codex-ran marker | Approval blocked — run call_codex.sh first | NO |

## Valid Pause Conditions

1. **Investigation findings** — codex (debugging) always requires user review
2. **NEEDS_DISCUSSION** — From code-critic, minimizer, or codex
3. **3 strikes** — 3 failed fix attempts on same issue
4. **Oscillation detected** — Critic reverses its own prior feedback
5. **Iteration cap hit** — Per severity tier (see above)
6. **Explicit blockers** — Missing dependencies, unclear requirements

## Sub-Agent Behavior

| Class | When to Pause | Show to User |
|-------|---------------|--------------|
| Investigation (codex debug) | Always | Full findings |
| Verification (test-runner, check-runner, security-scanner) | Never | Summary only |
| Iterative (code-critic, minimizer, codex) | NEEDS_DISCUSSION, oscillation, or cap hit | Verdict each iteration |

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
