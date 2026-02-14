---
name: plan-workflow
description: Task breakdown from an existing DESIGN.md. Creates PLAN.md and TASK*.md files with codex validation. For design-first planning (no DESIGN.md yet), use design-workflow instead.
user-invocable: true
---

# Plan Workflow

Take an existing DESIGN.md and break it down into PLAN.md and TASK*.md files. Submit as a documentation-only PR for review.

## Purpose

This is **Phase 2** of a two-phase planning flow:
1. **design-workflow** — Produce SPEC.md + DESIGN.md, validate architecture
2. **plan-workflow** (this skill) — Take approved DESIGN.md, produce PLAN.md + TASKs

The DESIGN.md referenced in the user's prompt is the input. Architecture decisions are already validated — this skill focuses on task scoping, coverage, and dependency ordering.

## Entry Phase

1. **Read the referenced DESIGN.md** and its associated SPEC.md (same directory)
2. **Verify design completeness** — DESIGN.md must contain:
   - File structure / modified files
   - Data flow with transformation points
   - Integration points
3. **If DESIGN.md is incomplete** -> Flag gaps, ask user whether to proceed or fix first

## Setup Phase

1. **Check if worktree exists** — If a `-plan` worktree already exists from design-workflow, use it. Otherwise create one:
   ```bash
   # With issue ID:
   git worktree add ../<repo>-<ISSUE-ID>-<feature>-plan -b <ISSUE-ID>-<feature>-plan
   # Without issue ID:
   git worktree add ../<repo>-<feature>-plan -b <feature>-plan
   ```

2. **Create tasks directory** (if not present):
   ```bash
   mkdir -p doc/projects/<feature-name>/tasks
   ```

## Planning Phase

1. **Invoke `/plan-implementation`** to create task documents:
   - PLAN.md - Task breakdown with dependencies and Coverage Matrix
   - tasks/TASK*.md - Individual implementation tasks

   The SPEC.md and DESIGN.md already exist — `/plan-implementation` reads them as input and produces only the task breakdown files.

2. **Wait for user review** of task breakdown

## Validation Phase

Execute continuously — **no stopping until PR is created**.

```
codex (iteration loop) -> PR
```

### Step-by-Step

1. **Run codex agent** (MANDATORY)
   - Task-scoping focused review (architecture already validated in design-workflow)
   - Returns APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION

   **Prompt template:**
   ```
   Review this task breakdown for an already-approved design.

   **Task:** Plan Review
   **Iteration:** {N} of 3
   **Previous feedback:** {summary if iteration > 1}

   The DESIGN.md has already been architecturally validated. Focus on:
   - Are task scopes appropriate (~200 LOC)?
   - Is the dependency ordering correct?
   - Are there missing edge cases in task definitions?
   - Do tasks have clear acceptance criteria?

   **CRITICAL CHECKS (Scope & Coverage):**
   - [ ] Cross-Task Scope: If TASK1 adds X to endpoints A and B, do tasks exist for BOTH?
   - [ ] Coverage Matrix: Does PLAN.md show which tasks handle which new fields/endpoints?
   - [ ] Task Independence: Can each task be executed without assuming agent remembers previous tasks?
   - [ ] Verification Commands: Does every task include type check, tests, lint commands?
   - [ ] Scope Boundaries: Does every task state what IS and ISN'T in scope?

   Return structured verdict. On approval, include "CODEX APPROVED" token:

   ### Verdict
   **APPROVE** — CODEX APPROVED
   {reason}
   ```

2. **Handle codex verdict:**
   | Verdict | Action |
   |---------|--------|
   | APPROVE | Continue to PR |
   | REQUEST_CHANGES | Fix issues, re-run codex |
   | NEEDS_DISCUSSION | Show findings, ask user |
   | 3rd iteration fails | Show findings, ask user |

3. **Create PR** with plan files only:
   ```bash
   git add doc/projects/<feature-name>/
   git commit -m "docs: add implementation plan for <feature-name>"
   gh pr create --draft --title "Plan: <feature-name>" --body "..."
   ```

## Branch Naming

Always use `-plan` suffix (e.g., `ENG-123-auth-plan` or `auth-feature-plan`). This:
- Preserves Linear issue ID convention (`<ISSUE-ID>-<description>`)
- Triggers plan-specific PR gate path (requires codex marker only)

## When to Use This Workflow

- User references a DESIGN.md in their prompt
- Design phase is complete, ready for task breakdown

## When NOT to Use

- No DESIGN.md exists yet -> use `design-workflow`
- Bug fixes -> use `bugfix-workflow`
- Implementing planned tasks -> use `task-workflow`
- Small changes (<50 lines) -> implement directly

## Post-PR

After plan PR is merged, implementation proceeds via `task-workflow`:

```
user: implement @doc/projects/<feature>/tasks/TASK0.md
-> task-workflow executes with full code verification
```

## Core Reference

See [execution-core.md](../../rules/execution-core.md) for:
- codex iteration rules
- Pause conditions
