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
2. **Does task require tests?** → invoke `/write-tests` FIRST
3. **Requirements unclear?** → Ask user
4. **Will this bloat into a large PR?** → Split into smaller tasks
5. **Locate PLAN.md** — Find the project's PLAN.md for checkbox updates later

State which items were checked before proceeding.

## Execution Flow

After passing the gate, execute continuously — **no stopping until PR is created**.

```
/write-tests (if needed) → implement → checkboxes → [code-critic + minimizer] → codex → /pre-pr-verification → commit → PR
```

### Step-by-Step

1. **Tests** — If task needs tests, invoke `/write-tests` first (RED phase via test-runner)
2. **Implement** — Write the code to make tests pass
3. **GREEN phase** — Run test-runner agent to verify tests pass
4. **Checkboxes** — Update both TASK*.md AND PLAN.md: `- [ ]` → `- [x]` (MANDATORY — both files)
5. **code-critic + minimizer** — MANDATORY after implementing. Run in parallel. Fix issues until both APPROVE. **After fixing any REQUEST_CHANGES, re-run BOTH critics** — even if only one requested changes. If either returns NEEDS_DISCUSSION, ask user for guidance. Do not proceed to codex until both return APPROVE in the same run.
6. **codex** — Invoke `~/.claude/skills/codex-cli/scripts/call_codex.sh` for combined code + architecture review
7. **Handle codex verdict:**
   - **APPROVE (no changes):** Run `~/.claude/skills/codex-cli/scripts/codex-verdict.sh approve`, proceed to Step 8.
   - **APPROVE (with changes):** Run `~/.claude/skills/codex-cli/scripts/codex-verdict.sh approve`, then apply codex's suggested fixes → re-run code-critic + minimizer (Step 5). Re-run codex (Step 6) only if logic or structural changes were made; if style-only, proceed directly to Step 8.
   - **REQUEST_CHANGES:** Fix the flagged issues and re-run code-critic + minimizer (Step 5), then re-run codex (Step 6).
   - **NEEDS_DISCUSSION:** Run `~/.claude/skills/codex-cli/scripts/codex-verdict.sh needs_discussion`, ask user for guidance before proceeding.
8. **PR Verification** — Invoke `/pre-pr-verification` (runs test-runner + check-runner internally)
9. **Commit & PR** — Create commit and draft PR

**Note:** Step 4 (Checkboxes) MUST include PLAN.md. Forgetting PLAN.md is a common violation.

**Important:** Always use test-runner agent for running tests, check-runner for lint/typecheck. This preserves context by isolating verbose output.

## Plan Conformance (Checkbox Enforcement)

When PLAN.md exists, enforce:

1. **Both files updated:** TASK*.md AND PLAN.md checkboxes must change `- [ ]` → `- [x]` after implementation.
2. **Dependency/order changes:** If task execution reveals the need to reorder or add tasks, update PLAN.md explicitly before proceeding.
3. **Commit together:** Checkbox updates go WITH implementation, not as separate commits.

Forgetting PLAN.md is the most common violation. Verify both files are updated before proceeding to code-critic.

## Codex Step

After both code-critic and minimizer APPROVE, invoke Codex directly for deep review:

**Review invocation:**
```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --review --base main --title "{PR title or change summary}"
```

**Non-review invocation (architecture, debugging):**
```bash
~/.claude/skills/codex-cli/scripts/call_codex.sh \
  --prompt "TASK: Code + Architecture Review. SCOPE: {changed files}. ITERATION: {N} of 5. PREVIOUS: {summary if N>1}. OUTPUT: Findings with file:line refs, then verdict."
```

After analyzing Codex output, signal verdict via a **separate** Bash call:
```bash
~/.claude/skills/codex-cli/scripts/codex-verdict.sh approve
```

The `codex-trace.sh` hook creates the "CODEX APPROVED" marker automatically when `codex-verdict.sh approve` runs.

**Iteration protocol:**
- Max 5 iterations, then NEEDS_DISCUSSION
- Do NOT re-run codex after convention/style fixes from critics — only after logic or structural changes

## Core Reference

See [execution-core.md](~/.claude/rules/execution-core.md) for:
- Decision matrix (when to continue vs pause)
- Sub-agent behavior rules
- Verification requirements
- PR gate requirements
