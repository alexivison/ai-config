---
name: task-workflow
description: >-
  Execute planned work with full autonomous workflow including tests,
  implementation, critic review, Codex review, and PR creation. Works with
  any planning source that provides scope, requirements, and a goal — TASK
  files, external planning tools, or direct user instructions. Covers the
  entire cycle from worktree creation to draft PR.
user-invocable: true
---

# Task Workflow

Execute planned work with the full autonomous workflow.

## Pre-Implementation Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Behavior change?** → invoke `/write-tests` FIRST and capture RED evidence (failing test + failure reason)
3. **Requirements unclear?** → Ask user
4. **Extract scope and requirements** — Identify the source of work and extract:
   - **Scope boundaries** (in scope / out of scope) for use in all sub-agent prompts
   - **Requirements** as a list of concrete, verifiable items for scribe
   - **Goal** as a one-line summary for review context

   Sources may include:
   - A TASK*.md file (read "In Scope", "Out of Scope", and acceptance criteria sections)
   - An external planning tool's artifacts (read the relevant files to extract the same information)
   - Direct user instructions (use the user's description as scope and requirements)

   If a PLAN.md or equivalent tracking file exists, note its location for checkbox updates later.

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.
Use the canonical sequence in [execution-core.md](~/.claude/rules/execution-core.md#core-sequence).

### Step-by-Step

1. **Tests** — For any behavior-changing production code, invoke `/write-tests` first (RED phase via test-runner)
   - **Feature flags:** Add gate tests for both states. Flag ON must validate new behavior; flag OFF must assert pre-implementation behavior remains unchanged.
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass (RED→GREEN evidence required for behavior changes)
4. **Source-file updates** — If the work source has checkboxes or completion tracking (e.g., TASK*.md + PLAN.md, or an external tool's tasks file), update them: `- [ ]` → `- [x]`. If no tracking files exist, skip this step.
5. **Minimality + Scope Gate (blocking)** — Before critics:
   - Record a one-line "smallest possible fix" rationale.
   - Compare `git diff --name-only` against the extracted scope boundaries.
   - Any out-of-scope file touch requires explicit justification; otherwise stop with `NEEDS_DISCUSSION`.
   - Remove single-use abstractions, speculative code (YAGNI), and unjustified new dependencies.
6. **code-critic + minimizer + scribe** — Run all three in parallel with scope context and diff focus (see [Review Governance](#review-governance)).
   - **scribe** gets the extracted requirements as text, scope boundaries as text, the diff command, and test file paths. It verifies every requirement is implemented and tested.
   - Round 1: collect findings from all three, fix only `[must]` in one batch.
   - **After fixing blocking items → re-run all three (one pass).** Do NOT proceed to codex without this re-run. Only when all return APPROVE (or only non-blocking findings remain) may you proceed.
   - Stop critic loop at 3 rounds. If blocking findings still remain, enter dispute resolution (2 rounds) per execution-core, then escalate to user if unresolved.
   - `[q]`/`[nit]` are opt-in only (explicit polish request) and should not trigger another critic round.
7. **Dispatch Codex review** (non-blocking):
      ```bash
      party-cli transport review main "{PR title}" "$(pwd)"
      ```
      `work_dir` is required — pass the worktree/repo path. Codex notifies via `[CODEX]` message when done.
8. **Sentinel review** — Immediately after dispatching Codex, launch the `sentinel` sub-agent in the background. Pass the merge-base diff, scope boundaries, and a short PR goal context.
      - **BARRIER:** no code edits until both Codex AND Sentinel return.
      - Sentinel findings are advisory (no gating markers). Paladin triages.
9. **Triage findings** — When `[CODEX] Review complete` arrives: read findings, triage by severity. Triage the UNION of Codex + Sentinel findings.
   - **Blocking in-scope findings:** fix code → commit → re-run critics → dispatch new `review` → `review-complete`.
   - **Out-of-scope / NEEDS_DISCUSSION:** follow [execution-core.md § Dispute Resolution](~/.claude/rules/execution-core.md#dispute-resolution).
   - Non-blocking / approved: `review-complete` reads the verdict from the findings file. Do NOT call `approve` directly.
10. **Commit** — Create the commit first. The PR gate checks evidence against the committed diff_hash, so all evidence must be recorded after the commit exists.
11. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
   - **If you edit ANY implementation file after this step passes → re-run `/pre-pr-verification` before PR.** Even a JSDoc fix invalidates prior evidence.
   - Critics and Codex evidence must also be fresh at the committed hash. If the commit changed the hash (it always does), re-run the cascade: critics → codex → `/pre-pr-verification`.
12. **PR** — Create draft PR

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Review Governance

See [execution-core.md](~/.claude/rules/execution-core.md#review-governance) for full rules. Key points:

- **Every** sub-agent prompt MUST include the extracted scope boundaries
- Out-of-scope file touches are blocking unless explicitly justified
- Triage findings as **blocking** (fix + re-run), **non-blocking** (note only), or **out-of-scope** (reject)
- Only blocking findings continue the review loop
- Max 3 critic iterations for blocking, then dispute resolution (2 rounds) before escalating to user
- **Codex has NO iteration cap** — continue the fix/dispute loop until Codex writes `VERDICT: APPROVED`. Do not decide the review phase is done prematurely.

## Source-File Updates

When the work source has tracking files, keep them in sync:

1. **TASK*.md + PLAN.md:** Update checkboxes in both files: `- [ ]` → `- [x]` after implementation. Commit together with implementation.
2. **External tool's tracking files:** Update completion markers per that tool's conventions after implementation. Commit together with implementation.
3. **No tracking files:** Skip this step entirely.

If task execution reveals the need to reorder or add tasks, update the tracking file explicitly before proceeding.

**Pre-filled checkbox prohibition:** Never write `- [x]` when creating new checklist items. All new items start as `- [ ]` and are only checked after the work is done and verified. Pre-filling checkboxes is falsifying evidence.

## Codex Step

See the `codex-transport` skill for full invocation details (`review`, `plan-review`, `prompt`, `review-complete`, `needs-discussion`).

Key points for task workflow:
- Invoke after critics have no remaining blocking findings
- Non-blocking — continue with non-edit work while Codex reviews
- **Timing constraint:** Do not dispatch Codex review while critic fixes are still pending. If you edit implementation files after dispatching Codex but before Codex returns, the review is stale — discard it, re-run critics, and dispatch a fresh `review`.
- **No iteration cap for Codex** — keep fixing and re-reviewing until `VERDICT: APPROVED`. Dispute with evidence if you disagree, but never bypass.
- Approval flows through `review-complete`, which reads the `VERDICT:` line Codex wrote in the findings file. Do NOT call `approve` directly.

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for decision matrix, review governance, verification requirements, and PR gate.
