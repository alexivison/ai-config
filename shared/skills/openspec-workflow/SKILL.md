---
name: openspec-workflow
description: >-
  Two-phase workflow for repos with OpenSpec and CI-based review bots.
  Phase 1 creates spec artifacts and iterates with ai-spec-review.
  Phase 2 implements from approved specs and iterates with ai-pr-review.
  Skips local review cascade (no code-critic, minimizer, companion review) because
  CI handles review. Use when working in a repo that has OpenSpec structure
  and CI review labels (ai-spec-review, ai-pr-review).
user-invocable: true
---

# OpenSpec Workflow

Two-phase workflow for repos where CI-based review bots replace the local
review cascade. The PR gate runs in `ci-gate` tier (pr-verified +
test-runner + check-runner only) — the hook assigns this automatically
when this skill is invoked.

## Modes

Invoke with an optional phase argument:
- `/openspec-workflow spec` — Phase 1: create spec artifacts, get ai-spec-review approval
- `/openspec-workflow implement` — Phase 2: implement from approved specs, get ai-pr-review approval
- `/openspec-workflow` (no argument) — auto-detect phase (see below)

Each phase ends with a polling loop that iterates until every check is
green and every review is APPROVED, then STOPs. The session does not
proceed to the next phase or merge — report completion and wait.

### Auto-Detection

When no phase is given, determine it from the current state:

1. Look for an OpenSpec change in `openspec/changes/` (not `archive/`).
2. If a change exists and its PR has an approved `ai-spec-review`
   review → **implement**.
3. If a change exists but spec review is not yet approved → **spec**
   (continue iterating on the existing change).
4. If no change exists → **spec** (start fresh).

State the detected phase before proceeding so the user can correct if wrong.

---

## Phase 1 — Spec

Goal: produce OpenSpec artifacts and get them approved by the spec review bot.

### Steps

1. **Worktree** — create via `git worktree add` (or `gwta` if available).

2. **Artifacts** — create the OpenSpec change. Delegate to `/opsx:propose`
   or `/opsx:ff` for artifact generation, or create manually:
   - `.openspec.yaml`, `proposal.md`, `design.md`
   - `specs/<feature>/spec.md` (GIVEN/WHEN/THEN scenarios)
   - `tasks.md` (implementation checklist, all boxes unchecked)

3. **Commit and push** the spec artifacts.

4. **Pre-PR verification** — invoke `/pre-pr-verification`. The `pr-gate`
   hook requires CI-tier evidence (test-runner + check-runner) before
   `gh pr create` — this applies even to spec-only pushes with no source
   changes. Skipping this step will cause PR creation to be blocked.

5. **Create a draft PR** targeting `main`.

6. **Add the `ai-spec-review` label.**

7. **Poll and iterate** — enter the [Review Loop](#review-loop) with
   label `ai-spec-review`. Continue until all checks green + review APPROVED.

8. **STOP.** Report the PR URL and status. Do NOT begin implementation.

---

## Phase 2 — Implement

Goal: implement tasks from approved specs and get the PR approved by the
review bot.

Prerequisite: Phase 1 spec review is APPROVED and all checks are green.

### Steps

1. **Worktree** — reuse Phase 1 branch or create a new worktree.

2. **Extract scope** — from whatever context is available (user prompt,
   Linear ticket, OpenSpec artifacts, direct instructions). Identify:
   - **Scope boundaries** (in scope / out of scope)
   - **Requirements** (concrete, verifiable items)
   - **Goal** (one-line summary)

   Include scope boundaries in every sub-agent prompt.

3. **Tests first** — invoke `/write-tests` for behavior changes. Capture
   RED evidence (failing tests) before implementing. This is a blocking
   gate — no RED evidence for a behavior change is a workflow violation.

4. **Implement** — work through `tasks.md`. Mark checkboxes (`- [x]`) as
   each task is completed. Never pre-fill checkboxes.

5. **Verify** — run test-runner and check-runner in parallel via
   sub-agents. Never run tests or lint via Bash directly.

6. **Pre-PR verification** — invoke `/pre-pr-verification`.

7. **Commit** — create the commit before the PR.

8. **Archive** — move the OpenSpec change to archive so openspec-hygiene
   CI passes. Follow the repo's AGENTS.md archive instructions (move
   directory, copy co-located tests to maintained specs, fix paths,
   verify tests pass). Commit the archive in the same branch.

9. **Push and PR** — push the branch. If reusing Phase 1's draft PR, mark
   it ready for review. Otherwise create a new PR.

10. **Add the `ai-pr-review` label.**

11. **Poll and iterate** — enter the [Review Loop](#review-loop) with
    label `ai-pr-review`. Continue until all checks green + review APPROVED.

12. **STOP.** Report the PR URL and status. Do NOT merge.

---

## Review Loop

This is the shared polling loop used by both phases. It runs until every
CI check is green and every review is APPROVED.

The loop matters because CI review bots are asynchronous — they take
minutes to run. Sitting idle wastes time; polling lets the session react
as soon as results arrive.

### Procedure

1. Push changes and ensure the review label is present.

2. **Start `/loop 3m`** to poll every 3 minutes.

3. On each tick, check status:
   ```
   gh pr checks <PR_NUMBER>
   gh pr view <PR_NUMBER> --json reviews --jq '.reviews[-1]'
   ```

4. **If a review returns CHANGES_REQUESTED:**
   - Read the review comments: `gh api repos/{owner}/{repo}/pulls/{PR}/reviews/{REVIEW_ID}/comments`
   - Fix the issue in code, OR reply to the inline comment with justification
   - Push the fix
   - Dismiss the old review — **`REVIEW_ID` must be the numeric `databaseId`,
     not the GraphQL node ID**. `gh pr view --json reviews` returns node IDs
     (`PRR_kwDO...`) which the dismissal endpoint rejects with 404. Fetch
     numeric IDs via the REST endpoint:
     ```
     gh api repos/{owner}/{repo}/pulls/{PR}/reviews --jq '.[] | {id, state, user: .user.login}'
     gh api -X PUT repos/{owner}/{repo}/pulls/{PR}/reviews/{REVIEW_ID}/dismissals \
       -f message="Addressed feedback" -f event="DISMISS"
     ```
   - Remove and re-add the label to trigger a fresh review
   - Continue polling

5. **If CI checks are failing:**
   - Investigate the failure (read logs via `gh run view`)
   - **Superseded-run caveat**: a `fail` with suspiciously short duration
     (< 30s) right after a re-push is usually a concurrency-cancelled run
     from the previous push, not a real failure. Confirm via
     `gh run list --branch <branch>` before investigating — the newer run
     may still be in progress.
   - **Missing bootstrap**: if a push fails on pre-push hooks citing
     missing tooling or artifacts (browser binaries, generated build
     output, etc.), check the project's `AGENTS.md` / `CLAUDE.md` for
     required bootstrap steps before retrying. Bootstrap is typically a
     once-per-worktree step.
   - Fix and push
   - Continue polling

6. **If all checks green AND all reviews APPROVED:** exit the loop.

### Rules

- **Every check matters.** openspec-hygiene, spec-coverage, biome,
  traceability, i18n, spec-alignment — all are blocking. A PR with any
  red check is not done.
- **Never add bypass labels** (`skip-ai-pr-review`, etc.) without
  explicit user approval. When stuck, investigate and fix — or ask the
  user.
- **Never dismiss reviews preemptively** — only dismiss after addressing
  the feedback (fix or justified reply).
