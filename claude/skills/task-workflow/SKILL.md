---
name: task-workflow
description: Execute a task from TASK*.md with full workflow. Auto-invoked when implementing planned tasks.
user-invocable: true
---

# Task Workflow

Execute tasks from TASK*.md files with the full autonomous workflow.

## Pre-Implementation Gate

**STOP. Before writing ANY code:**

1. **Create worktree first** — `git worktree add ../repo-branch-name -b branch-name`
2. **Behavior change?** → invoke `/write-tests` FIRST and capture RED evidence (failing test + failure reason)
3. **Requirements unclear?** → Ask user
4. **Will this bloat into a large PR?** → Split into smaller tasks
5. **Locate PLAN.md** — Find the project's PLAN.md for checkbox updates later
6. **Extract scope boundaries** — Read the TASK file's "In Scope" and "Out of Scope" sections for use in all sub-agent prompts

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.
Use the canonical sequence in [execution-core.md](~/.claude/rules/execution-core.md#core-sequence).

### Step-by-Step

1. **Tests** — For any behavior-changing production code, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass (RED→GREEN evidence required for behavior changes)
4. **Checkboxes** — Update both TASK*.md AND PLAN.md: `- [ ]` → `- [x]` (MANDATORY — both files)
5. **Minimality + Scope Gate (blocking)** — Before critics:
   - Record a one-line "smallest possible fix" rationale.
   - Compare `git diff --name-only` against TASK "In Scope".
   - Any out-of-scope file touch requires explicit justification; otherwise stop with `NEEDS_DISCUSSION`.
   - Remove single-use abstractions, speculative code (YAGNI), and unjustified new dependencies.
6. **code-critic + minimizer** — Run in parallel with scope context and diff focus (see [Review Governance](#review-governance)).
   - Round 1: collect findings, fix only `[must]` in one batch.
   - **After fixing blocking items → re-run BOTH critics (one pass).** Do NOT proceed to codex without this re-run. Only when both return APPROVE (or only non-blocking findings remain) may you proceed.
   - Stop critic loop at 2 rounds. If blocking findings still remain, escalate `NEEDS_DISCUSSION`.
   - `[q]`/`[nit]` are opt-in only (explicit polish request) and should not trigger another critic round.
7. **codex** — Request codex review via tmux (non-blocking):
   ```bash
   ~/.claude/skills/codex-transport/scripts/tmux-codex.sh --review main "{PR title}" "$(pwd)"
   ```
   `work_dir` is required — pass the worktree/repo path. Continue with non-edit work while Codex reviews. Codex notifies via `[CODEX]` message when done.
8. **Triage codex findings** — When `[CODEX] Review complete` arrives: read findings, triage by severity.
   - **After fixing blocking items → use `--re-review` (NOT `--review-complete`).** Wait for the re-review findings before proceeding. `--review-complete` only records evidence — it does not re-validate.
   - Round 2: if blocking findings remain after re-review, escalate `--needs-discussion`.
   - Non-blocking findings: record with `--review-complete` and proceed.
9. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
   - **If you edit ANY implementation file after this step passes → re-run `/pre-pr-verification` before commit.** Even a JSDoc fix invalidates prior evidence.
10. **Commit & PR** — Create commit and draft PR

**Note:** Step 4 (Checkboxes) MUST include PLAN.md. Forgetting PLAN.md is a common violation.

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Review Governance

See [execution-core.md](~/.claude/rules/execution-core.md#review-governance) for full rules. Key points:

- **Every** sub-agent prompt MUST include scope boundaries from the TASK file
- Out-of-scope file touches are blocking unless explicitly justified
- Triage findings as **blocking** (fix + re-run), **non-blocking** (note only), or **out-of-scope** (reject)
- Only blocking findings continue the review loop
- Max 2 critic iterations and max 2 codex iterations for blocking, then NEEDS_DISCUSSION

## Plan Conformance (Checkbox Enforcement)

When PLAN.md exists, enforce:

1. **Both files updated:** TASK*.md AND PLAN.md checkboxes must change `- [ ]` → `- [x]` after implementation.
2. **Dependency/order changes:** If task execution reveals the need to reorder or add tasks, update PLAN.md explicitly before proceeding.
3. **Commit together:** Checkbox updates go WITH implementation, not as separate commits.

Forgetting PLAN.md is the most common violation. Verify both files are updated before proceeding to critics.

**Pre-filled checkbox prohibition:** Never write `- [x]` when creating new checklist items. All new items start as `- [ ]` and are only checked after the work is done and verified. Pre-filling checkboxes is falsifying evidence.

## Codex Step

See the `codex-transport` skill for full invocation details (`--review`, `--plan-review`, `--prompt`, `--review-complete`, `--approve`, `--re-review`, `--needs-discussion`).

Key points for task workflow:
- Invoke after critics have no remaining blocking findings
- Non-blocking — continue with non-edit work while Codex reviews
- **Timing constraint:** Do not dispatch Codex review while critic fixes are still pending. If you edit implementation files after dispatching Codex but before Codex returns, the review is stale — use `--re-review` instead of `--approve`.
- Max 2 iterations for blocking findings, then NEEDS_DISCUSSION
- Non-blocking codex findings do not trigger re-review

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for decision matrix, review governance, verification requirements, and PR gate.
