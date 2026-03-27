# Execution Core

Shared rules for all workflow skills. Bugfix-workflow omits checkboxes (no PLAN.md).

## Core Sequence

This section is the single source of truth for execution order across workflow docs.

```
/write-tests → implement → checkboxes → [code-critic + minimizer (+ scribe if TASK file)] → codex [+ sentinel] → /pre-pr-verification → commit → PR
```

Workflow skills enforce the critic-before-Codex ordering. Hooks only record evidence and block self-approval — they do not gate sequencing. Sentinel runs after critics pass. Advisory only — no gating markers.

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

## Evidence System

Evidence is stored in a per-session JSONL log (`/tmp/claude-evidence-{session_id}.jsonl`). Each entry records a `diff_hash` — SHA-256 of the branch diff from merge-base. Gate hooks compute the current diff_hash and only accept evidence with a matching hash. Editing code after approval automatically invalidates prior evidence (different hash) — no invalidation hook needed.

`codex-gate.sh` only blocks `tmux-codex.sh --approve` (self-approval). All other Codex commands (`--review`, `--prompt`, `--plan-review`, `--review-complete`) pass through freely. Workflow skills are responsible for running critics before dispatching Codex review. `--approve` is hard-blocked; approval flows through `--review-complete` reading the verdict Codex wrote.

`agent-trace-stop.sh` tracks all critic verdicts (APPROVED and REQUEST_CHANGES) via `{type}-run` evidence entries and detects oscillation in two modes:
- **Same-hash alternation** (all critics including scribe): when 3 alternating verdicts are detected at the same hash (e.g., RC→A→RC), an auto-triage-override is recorded.
- **Cross-hash repeated findings** (minimizer only): when the same normalized REQUEST_CHANGES body appears across 3+ distinct hashes, an auto-triage-override is recorded. Code-critic is exempt — correctness bugs legitimately persist across fix attempts.

## Tiered Execution

- **Full tier** (default): current sequence unchanged (`/write-tests → implement → ... → PR`). Gate-enforced evidence: pr-verified, code-critic, minimizer, codex, test-runner, check-runner. Scribe is workflow-enforced by task-workflow (not gate-enforced) — it runs when a TASK file exists but bugfix-workflow has no TASK file, so scribe cannot be a universal gate requirement.
- **Quick tier**: requires explicit `quick-tier` evidence from the quick-fix-workflow skill (size alone is insufficient). For non-behavioral changes only (config, deps, typos, CI). Sequence: `implement → code-critic → test-runner → check-runner → PR`. Required evidence: quick-tier, code-critic, test-runner, check-runner. Size limit: ≤30 changed lines (additions + deletions), ≤3 files, 0 new files. Explicitly forbidden for: new features, bug fixes, logic changes, API changes, security-relevant changes.

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
- Critics should return `APPROVE` when only non-blocking findings remain.

**Caps:** Blocking: max 3 critic iterations + 3 codex iterations. When cap is reached, enter dispute resolution (2 rounds) before escalating to user. Non-blocking: max 1 round → accept or drop.

**Tiered re-review:** One-symbol swap → test-runner only. Logic change → test-runner + critics. New export/signature/security path → full cascade.

**Scope enforcement:** Every sub-agent prompt MUST include TASK file scope boundaries. Critics review the diff, not the codebase. Pre-existing code is non-blocking unless newly reachable.

## Decision Matrix

| Step | Outcome | Next | Pause? |
|------|---------|------|--------|
| /write-tests | Written (RED) | Implement | NO |
| Implement | Done | Checkboxes | NO |
| Minimality + Scope Gate | PASS | Critics | NO |
| Minimality + Scope Gate | Scope violation w/o justification | NEEDS_DISCUSSION | YES |
| code-critic, minimizer, or scribe | APPROVE | Wait for others / codex | NO |
| code-critic, minimizer, or scribe | REQUEST_CHANGES (blocking) | Fix in one batch + one re-run of all three | NO |
| code-critic, minimizer, or scribe | REQUEST_CHANGES (non-blocking) | Record and treat as effective APPROVE (LLM misclassified) | NO |
| code-critic, minimizer, or scribe | NEEDS_DISCUSSION / oscillation / cap | Dispute resolution: re-run with context explaining dismissed findings (2 rounds) → escalate to user if unresolved | NO (until dispute cap) |
| All three critics done, no blocking | — | Run codex | NO |
| codex | APPROVE | /pre-pr-verification | NO |
| codex | REQUEST_CHANGES (blocking) | Fix in one batch + commit + re-run critics + new `--review` → `--review-complete` | NO |
| codex | REQUEST_CHANGES (non-blocking) | Record and proceed to /pre-pr-verification | NO |
| codex | REQUEST_CHANGES with out-of-scope findings | Dismiss with rationale in dispute context file → re-review (2 dispute rounds) → escalate if unresolved | NO (until dispute cap) |
| codex | NEEDS_DISCUSSION | Debate via `--prompt` (2 rounds) → escalate to user if unresolved | NO (until dispute cap) |
| sentinel | Any findings | Paladin triages (advisory, no gating markers) | NO |
| sentinel | Timeout | Proceed with Codex findings only | NO |
| /pre-pr-verification | Pass/Fail | PR / fix | NO |
| Edit/Write (impl) | Evidence stale (diff_hash changed) | Re-run cascade | NO |

## Dispute Resolution

When critics or Codex return NEEDS_DISCUSSION or raise out-of-scope findings, agents resolve the disagreement before escalating to the user.

**Critic disputes:** Re-run the critic with updated prompt context explaining which findings are out-of-scope and why. The critic sees the rationale and either accepts (APPROVE) or raises new evidence. Max 2 dispute rounds per critic.

**Codex out-of-scope disputes:** Write a dispute context file listing dismissed finding IDs and rationales. Pass via `--dispute <file>` to `--review`. Codex reads the file, accepts valid dismissals, challenges invalid ones with file:line evidence. Max 2 dispute rounds.

**Codex NEEDS_DISCUSSION:** Formulate a position (concede, counter-argue, or propose compromise) and send via `--prompt`. Codex responds with evidence-based reasoning. Max 2 prompt exchanges.

**After successful dispute resolution:** If the dispute concludes that the work should proceed, dispatch a fresh `--review` → `--review-complete` to satisfy the gate evidence requirements.

**Escalation criteria (user involvement):**
- 2 dispute rounds fail to resolve
- Security-critical finding is disputed
- Both agents explicitly agree they need human input

## Valid Pause Conditions

Investigation findings, dispute cap reached (2 rounds unresolved), security-critical disagreement, oscillation, explicit blockers.

## Sub-Agent Behavior

Investigation (codex debug): always pause, show full findings. Verification (test/check): never pause, summary only. Iterative (critics, codex): enter dispute resolution on NEEDS_DISCUSSION/cap; pause only on dispute cap reached, oscillation, or security-critical disagreement.

## Verification Principle

Evidence before claims. No assertions without proof (test output, file:line, grep result). Code edits invalidate prior evidence — rerun. Red flags: "should work", commit without checks, stale evidence.

**Always use sub-agents for verification.** Use `test-runner` for tests and `check-runner` for lint/typecheck. Never run partial checks via Bash directly — sub-agents discover and run the full suite. Run `check-runner` before every push.

## PR Gate

Code PRs require all evidence at the current diff_hash. The PR gate (`pr-gate.sh`) is the single enforcement point — no other hook gates sequencing. Full tier: pr-verified, code-critic, minimizer, codex, test-runner, check-runner (scribe is enforced by task-workflow when a TASK file exists, not by the gate — bugfix-workflow has no TASK file). Quick tier (requires explicit quick-tier evidence + size limits): quick-tier, code-critic, test-runner, check-runner. Evidence created by `agent-trace-stop.sh`, `codex-trace.sh`, `skill-marker.sh`, and workflow skills (e.g., `quick-fix-workflow` writes `quick-tier`).

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
| Edit after approval, then PR | Evidence stale (diff_hash changed) — re-run |
| Create evidence outside authorized paths | Forbidden — only hooks and workflow skills write evidence via `append_evidence` |
| Fourth critic or codex round on same diff | Enter dispute resolution (2 rounds) → escalate to user if unresolved |
| Run lint/typecheck via Bash instead of check-runner | Always delegate to sub-agents — they run the full suite |
| Push without running check-runner | Run check-runner before every push, no exceptions |
| Add dependency without committing lockfile | Stage lockfile in same commit as package.json change |
