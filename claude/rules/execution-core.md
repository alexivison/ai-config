# Execution Core

Shared rules for all workflow skills. Applies to all implementation regardless of planning source. Bugfix-workflow omits source-file updates (no tracking files).

## Core Sequence

This section is the single source of truth for execution order across workflow docs.

```
/write-tests → implement → source-file updates → [code-critic + minimizer (+ scribe when requirements provided)] → codex [+ sentinel] → /pre-pr-verification → commit → PR
```

Workflow skills enforce the critic-before-Codex ordering. Hooks only record evidence and block self-approval — they do not gate sequencing. Sentinel runs after critics pass. Advisory only — no gating markers.

## Pre-Implementation Gate

**Before writing ANY code:**

1. **Create worktree** — `git worktree add ../repo-branch-name -b branch-name` (or `gwta` if available). One session per worktree; never `git checkout` in shared repos.
2. **Extract scope, requirements, and goal** from whatever triggered the work:
   - **Scope boundaries** (in scope / out of scope) — included in every sub-agent prompt
   - **Requirements** — concrete, verifiable items for scribe validation
   - **Goal** — one-line summary for review context

   Sources may include TASK files, external planning tool artifacts, or direct user instructions. Read the relevant source and extract the same three items regardless of format.
3. **Note tracking files** — If the work source has completion tracking (checkboxes, status markers), note the file locations for source-file updates later.
4. **Behavior change?** → Invoke `/write-tests` FIRST and capture RED evidence before implementing.
5. **Requirements unclear?** → Ask user.

State which items were checked before proceeding.

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
4. Compare `git diff --name-only` against the provided scope boundaries; out-of-scope touches require explicit justification

Out-of-scope touches without justification are blocking and require `NEEDS_DISCUSSION`.

## Scribe Contract

When requirements are provided (from any planning source), scribe runs alongside code-critic and minimizer. Pass scribe:

- **Requirements** — the extracted list of concrete, verifiable items (text)
- **Scope boundaries** — in-scope and out-of-scope boundaries (text)
- **Diff command** — so scribe can inspect what changed
- **Test file paths** — so scribe can verify each requirement has corresponding test coverage

Scribe verifies every requirement is implemented and tested. It is workflow-enforced (runs when requirements exist) rather than gate-enforced — bugfix-workflow has no requirements source, so scribe cannot be a universal gate requirement.

## Source-File Updates

After implementation, if the work source has tracking files, keep them in sync:

1. **Files with checkboxes** (TASK*.md, PLAN.md, etc.): Update `- [ ]` → `- [x]` after implementation. Commit together with implementation.
2. **External tool tracking files**: Update completion markers per that tool's conventions. Commit together with implementation.
3. **No tracking files**: Skip this step entirely.

If task execution reveals the need to reorder or add tasks, update the tracking file explicitly before proceeding.

**Pre-filled checkbox prohibition:** Never write `- [x]` when creating new checklist items. All new items start as `- [ ]` and are only checked after the work is done and verified. Pre-filling checkboxes is falsifying evidence.

## Commit and PR Ordering

Create the commit before running `/pre-pr-verification`. The PR gate checks evidence against the committed diff_hash, so all evidence must be recorded after the commit exists.

**Re-run rule:** If you edit ANY implementation file after `/pre-pr-verification` passes, re-run before PR. Even a comment fix invalidates prior evidence (different diff_hash). Critics and Codex evidence must also be fresh at the committed hash — if the commit changed the hash, re-run the cascade: critics → codex → `/pre-pr-verification`.

## Evidence System

Per-session JSONL log at `/tmp/claude-evidence-{session_id}.jsonl`. Each entry records a `diff_hash` (SHA-256 of branch diff from merge-base). Gates only accept evidence with matching hash — editing code auto-invalidates prior evidence.

`codex-gate.sh` blocks only `--approve` (self-approval); all other Codex commands pass freely. Approval flows through `--review-complete`.

**Oscillation detection** (`agent-trace-stop.sh`): Same-hash alternation (3 alternating verdicts → auto-triage-override). Cross-hash repeated findings (minimizer only, 3+ hashes → override; code-critic exempt).

## Review Metrics

Metrics are tracked via hooks in `~/.claude/logs/review-metrics/`. See `~/.claude/reference/review-metrics.md` for events, CLI commands, and querying.

## Tiered Execution

| Tier | Scope | Sequence | Gate Evidence | Limits |
|------|-------|----------|--------------|--------|
| **Full** (default) | All code changes | `/write-tests → implement → critics → codex → PR` | pr-verified, code-critic, minimizer, codex, test-runner, check-runner | Scribe workflow-enforced when requirements provided |
| **Quick** | Non-behavioral only (config, deps, typos, CI) | `implement → code-critic → test-runner → check-runner → PR` | quick-tier, code-critic, test-runner, check-runner | ≤30 lines, ≤3 files, 0 new files |
| **Spec** | Spec/design docs only (no production code) | `draft → spec-review → plan-review → iterate → PR` | spec-tier, spec-review, plan-review | No src/ or test files |

Quick tier requires explicit `quick-tier` evidence from quick-fix-workflow. Forbidden for: features, bug fixes, logic/API/security changes.

Spec-review checks: atomicity, normative language (SHALL/MUST), testable scenarios (GIVEN/WHEN/THEN), non-overlapping requirements. Plan-review checks: architecture coherence, feasibility, completeness. Both follow review governance rules.

## Review Governance

Classify every finding before acting:

| Severity | Definition | Action |
|----------|-----------|--------|
| **Blocking** | Correctness bug, crash, security HIGH/CRITICAL | Fix + re-run |
| **Non-blocking** | Style, "could be simpler", defensive edge cases | Note only, do NOT re-run |
| **Out-of-scope** | Pre-existing untouched code, requirements not in scope | Reject |

**Issue ledger:** Track findings across iterations. Closed findings cannot be re-raised without new evidence. Critic reversing own feedback = oscillation — use own judgment, proceed.

**Lean loop:** Critics: two-pass mode (initial + one re-review). Codex happy-path: two passes, but continue until `VERDICT: APPROVED` regardless. `[q]`/`[nit]` are opt-in. Critics APPROVE when only non-blocking remain.

**Caps:** Critics: max 3 iterations → dispute (2 rounds) → escalate. **Codex: NO cap** — continue until APPROVED. Dispute with evidence if you disagree; never bypass. Non-blocking: 1 round → accept or drop.

**Tiered re-review:** One-symbol swap → test-runner only. Logic change → test-runner + critics. New export/signature/security path → full cascade.

**Scope enforcement:** Every sub-agent prompt MUST include the provided scope boundaries. Critics review the diff, not the codebase. Pre-existing code is non-blocking unless newly reachable.

## Decision Matrix

| Step | Outcome | Next |
|------|---------|------|
| /write-tests | Written (RED) | Implement |
| Implement | Done | Source-file updates |
| Minimality + Scope Gate | PASS / Scope violation | Critics / **PAUSE** (NEEDS_DISCUSSION) |
| Critics (code-critic, minimizer, scribe) | APPROVE or non-blocking only | Wait for others → codex |
| Critics | REQUEST_CHANGES (blocking) | Fix batch + one re-run of all three |
| Critics | NEEDS_DISCUSSION / oscillation / cap | Dispute resolution (2 rounds) → escalate |
| All critics pass | — | Run codex |
| Codex | APPROVE | /pre-pr-verification |
| Codex | REQUEST_CHANGES (blocking) | Fix + commit + re-run critics + `--review` → `--review-complete`. **Repeat until APPROVED.** |
| Codex | REQUEST_CHANGES (non-blocking) | Record, proceed to /pre-pr-verification |
| Codex | Out-of-scope or NEEDS_DISCUSSION | Dispute per § Dispute Resolution. **No cap — continue until resolved.** |
| Sentinel | Any | Advisory only — Paladin triages |
| Spec-review / Plan-review | Same pattern as critics | See § Tiered Execution |
| /pre-pr-verification | Pass/Fail | PR / fix |
| Edit/Write after approval | Evidence stale | Re-run cascade |

**Codex review is never a pause condition.** See § Pause Conditions for the full list of valid pause triggers.

## Dispute Resolution

**Critic disputes:** Re-run with context explaining dismissed findings. Max 2 dispute rounds per critic.

**Codex disputes:** Write dispute context file (finding IDs + rationales), pass via `--dispute <file>`. No round cap — continue until Codex accepts or you concede. For NEEDS_DISCUSSION: debate via `--prompt` with evidence-based reasoning until genuine agreement.

**After resolution:** Dispatch fresh `--review` → `--review-complete` for gate evidence.

**Escalation to user:** Security-critical dispute, both agents agree human input needed, or genuinely circular (same arguments 3+ times, no new evidence).

## Pause Conditions & Sub-Agent Behavior

**Valid pause conditions:** Investigation findings, critic dispute cap (2 rounds), security-critical disagreement, oscillation, explicit blockers. Codex review is NEVER a pause condition.

**Sub-agent modes:** Investigation → always pause with findings. Verification (test/check) → never pause, summary only. Critics → dispute resolution on cap/NEEDS_DISCUSSION. Codex → no cap, continue until APPROVED.

## Verification Principle

Evidence before claims. No assertions without proof (test output, file:line, grep result). Code edits invalidate prior evidence — rerun. Red flags: "should work", commit without checks, stale evidence.

**Always use sub-agents for verification.** Use `test-runner` for tests and `check-runner` for lint/typecheck. Never run partial checks via Bash directly — sub-agents discover and run the full suite. Run `check-runner` before every push.

## PR Gate

`pr-gate.sh` is the single enforcement point — requires all tier-specific evidence at current diff_hash (see § Tiered Execution for per-tier requirements). Evidence created by `agent-trace-stop.sh`, `codex-trace.sh`, `skill-marker.sh`, and workflow skills.

**Post-PR:** Changes in same branch → re-run /pre-pr-verification → amend + force-push with `--force-with-lease`.

## Violation Patterns

| Pattern | Action |
|---------|--------|
| Behavior change without RED evidence | Block; add RED test first |
| Feature-flag without ON/OFF gate tests | Block; add gate tests first |
| Out-of-scope file changes without rationale | NEEDS_DISCUSSION |
| Add abstraction used once without clear gain | Remove or justify |
| Implement every finding without triage | Classify blocking/non-blocking/out-of-scope first |
| Stop after partial completion | Continue — never ask "should I continue?" |
| Chase non-blocking nits 2+ rounds | Triage, note, move on |
| Edit after approval, then PR | Evidence stale — re-run cascade |
| Approve without `--review-complete` | Gate blocks — run review first |
| Evidence created outside authorized paths | Forbidden — only hooks/workflow skills write evidence |
| Codex review bypassed or declared "done" without APPROVED | FORBIDDEN — no iteration cap |
| Lint/typecheck via Bash instead of check-runner | Always delegate to sub-agents |
| Push without check-runner | Run check-runner before every push |
| Dependency added without lockfile | Stage lockfile in same commit |
| Spec PR without spec-review + plan-review | Block; run spec tier cascade first |
| Spec tier PR containing production code | Block; use Full tier instead |
