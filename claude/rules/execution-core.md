# Execution Core

Shared rules for all workflow skills. Bugfix-workflow omits checkboxes (no PLAN.md).

## Core Sequence

This section is the single source of truth for execution order across workflow docs.

```
/write-tests → implement → checkboxes → [code-critic + minimizer] → codex [+ adversarial reviewer] → /pre-pr-verification → commit → PR
```

Adversarial reviewer runs after critics pass. Advisory only — no gating markers.

## RED Evidence Gate

For behavior-changing production code, tests are mandatory and must show RED→GREEN:

1. RED: failing test that demonstrates missing/incorrect behavior
2. GREEN: same test passing after implementation

No RED evidence for a behavior change is a blocking workflow violation.

## Feature Flag Gate

For behavior behind a feature flag, tests must prove both gate paths:

1. Flag ON: new behavior works as intended
2. Flag OFF: pre-implementation behavior remains unchanged

Missing OFF-path parity evidence is a blocking workflow violation.

## Minimality Gate

Before critics:

1. Record the "smallest possible fix" rationale (one line)
2. Remove speculative code and single-use abstractions without clear value
3. Avoid new dependencies unless strictly needed and justified
4. Compare `git diff --name-only` against TASK scope; out-of-scope touches require explicit justification

Out-of-scope touches without justification are blocking and require `NEEDS_DISCUSSION`.

## Marker System

`marker-invalidate.sh` deletes all review markers on Edit|Write of implementation files (skips `.md`, `/tmp/`, `.log`, `.jsonl`). Editing code after approval invalidates it — re-run the cascade. Markers are hook-created evidence; never create manually.

`codex-gate.sh` blocks `--review` without critic APPROVE markers, blocks `--approve` without codex-ran marker. If critics returned REQUEST_CHANGES, you MUST re-run them after fixing — the gate enforces this.

## Review Governance

Classify every finding before acting:

| Severity | Definition | Action |
|----------|-----------|--------|
| **Blocking** | Correctness bug, crash, security HIGH/CRITICAL | Fix + re-run |
| **Non-blocking** | Style, "could be simpler", defensive edge cases | Note only, do NOT re-run |
| **Out-of-scope** | Pre-existing untouched code, requirements not in TASK | Reject |

**Issue ledger:** Track findings across iterations. Closed findings cannot be re-raised without new evidence. Critic reversing own feedback = oscillation — use own judgment, proceed.

**Lean loop default:**
- Critics run in two-pass mode: initial pass, then one re-review pass after fixing blocking items.
- Codex runs in two-pass mode: initial pass, then one re-review pass after fixing blocking items.
- `[q]` and `[nit]` are opt-in (only when explicitly requested). By default, suppress them.
- Critics should return `APPROVE` when only non-blocking findings remain, so codex-gate markers stay aligned with policy.

**Caps:** Blocking: max 2 critic + 2 codex iterations → NEEDS_DISCUSSION. Non-blocking: max 1 round → accept or drop.

**Tiered re-review:** One-symbol swap → test-runner only. Logic change → test-runner + critics. New export/signature/security path → full cascade.

**Scope enforcement:** Every sub-agent prompt MUST include TASK file scope boundaries. Critics review the diff, not the codebase. Pre-existing code is non-blocking unless newly reachable.

## Decision Matrix

| Step | Outcome | Next | Pause? |
|------|---------|------|--------|
| /write-tests | Written (RED) | Implement | NO |
| Implement | Done | Checkboxes | NO |
| Minimality + Scope Gate | PASS | Critics | NO |
| Minimality + Scope Gate | Scope violation w/o justification | NEEDS_DISCUSSION | YES |
| code-critic or minimizer | APPROVE | Wait for other / codex | NO |
| code-critic or minimizer | REQUEST_CHANGES (blocking) | Fix in one batch + one re-run of both critics | NO |
| code-critic or minimizer | REQUEST_CHANGES (non-blocking) | Record and treat as effective APPROVE (LLM misclassified) | NO |
| code-critic or minimizer | NEEDS_DISCUSSION / oscillation / cap | Ask user | YES |
| Both critics done, no blocking | — | Run codex | NO |
| codex | APPROVE | /pre-pr-verification | NO |
| codex | REQUEST_CHANGES (blocking) | Fix in one batch + re-run critics + new `--review` | NO |
| codex | REQUEST_CHANGES (non-blocking) | Record and proceed to /pre-pr-verification | NO |
| codex | NEEDS_DISCUSSION | Ask user | YES |
| adversarial reviewer | Any findings | Paladin triages (advisory, no gating markers) | NO |
| adversarial reviewer | Timeout | Proceed with Codex findings only | NO |
| /pre-pr-verification | Pass/Fail | PR / fix | NO |
| Edit/Write (impl) | Markers invalidated | Re-run cascade | NO |

## Valid Pause Conditions

Investigation findings, NEEDS_DISCUSSION, 2-strike cap reached, oscillation, explicit blockers.

## Sub-Agent Behavior

Investigation (codex debug): always pause, show full findings. Verification (test/check): never pause, summary only. Iterative (critics, codex): pause on NEEDS_DISCUSSION/oscillation/cap.

## Verification Principle

Evidence before claims. No assertions without proof (test output, file:line, grep result). Code edits invalidate prior evidence — rerun. Red flags: "should work", commit without checks, stale evidence.

**Always use sub-agents for verification.** Use `test-runner` for tests and `check-runner` for lint/typecheck. Never run partial checks via Bash directly — sub-agents discover and run the full suite. Run `check-runner` before every push.

## PR Gate

Code PRs require all markers: pre-pr-verification, code-critic, minimizer, codex, test-runner, check-runner. Markers created by `agent-trace-stop.sh` and `codex-trace.sh`.

**Post-PR:** Changes in same branch → re-run /pre-pr-verification → amend + force-push with `--force-with-lease`.

## Violation Patterns

| Pattern | Action |
|---------|--------|
| Behavior change without RED evidence | Block; add RED test first |
| Feature-flag change without ON/OFF gate tests (including OFF-path parity) | Block; add gate tests first |
| Out-of-scope file changes without rationale | Stop with NEEDS_DISCUSSION |
| Add abstraction used once without clear gain | Remove or justify |
| Stop after partial completion | Continue — don't ask "should I continue?" |
| Chase non-blocking nits 2+ rounds | Triage, note, move on |
| Implement every finding without triage | Classify blocking/non-blocking/out-of-scope first |
| Full cascade after one-line fix | Tiered re-review |
| Approve without --review-complete | Gate blocks — run review first |
| Edit after approval, then PR | Markers invalidated — re-run |
| Create markers manually | Forbidden — hooks create evidence |
| Call codex without re-running critics | Gate blocks — re-run critics |
| Third critic/codex round on same diff | Stop and escalate with NEEDS_DISCUSSION |
| Run lint/typecheck via Bash instead of check-runner | Always delegate to sub-agents — they run the full suite |
| Push without running check-runner | Run check-runner before every push, no exceptions |
| Add dependency without committing lockfile | Stage lockfile in same commit as package.json change |
