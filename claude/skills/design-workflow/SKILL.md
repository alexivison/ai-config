---
name: design-workflow
description: Design-first planning phase. Creates SPEC.md and DESIGN.md with codex architecture validation. For task breakdown from an existing DESIGN.md, use plan-workflow instead.
user-invocable: true
---

# Design Workflow

Create SPEC.md and DESIGN.md for a feature, validate architecture via codex, and submit as a draft PR. Task breakdown happens separately via plan-workflow.

## Purpose

This is **Phase 1** of a two-phase planning flow:
1. **design-workflow** (this skill) — Produce SPEC.md + DESIGN.md, validate architecture
2. **plan-workflow** — Take approved DESIGN.md, produce PLAN.md + TASKs

Splitting design from task breakdown means architecture mistakes are caught early, before investing effort in task files that would be thrown away.

## Entry Phase

Before planning, determine the starting point:

1. **External spec provided?** (Notion doc, PRD, requirements doc, etc.) -> Skip SPEC.md, proceed to setup. The external spec IS the spec — only DESIGN.md will be created.
2. **Requirements unclear?** -> Invoke `/brainstorm` -> `[wait for user]`
3. **Requirements clear, no external spec** -> Proceed to setup (create both SPEC.md and DESIGN.md)

`[wait]` = Show findings, use AskUserQuestion, wait for user input.

## Setup Phase

1. **Create worktree** with `-plan` suffix (preserves Linear convention):
   ```bash
   # With issue ID:
   git worktree add ../<repo>-<ISSUE-ID>-<feature>-plan -b <ISSUE-ID>-<feature>-plan
   # Without issue ID:
   git worktree add ../<repo>-<feature>-plan -b <feature>-plan
   ```

2. **Create project directory**:
   ```bash
   mkdir -p doc/projects/<feature-name>
   ```

## Design Phase (CRITICAL)

### Step 1: Deep Codebase Exploration

**Before writing anything**, explore thoroughly:

1. **Find existing standards** — Search for similar patterns in the codebase
   - How is similar data already handled?
   - Are there existing abstractions to extend?
   - What naming conventions are used?

2. **Map data transformation points** — Identify ALL places where data changes shape
   - Proto -> Domain converters
   - Params conversion functions (e.g., `convertToParams`, `adaptRequest`)
   - Adapter patterns between layers

3. **List integration points** — Where will new code touch existing code?
   - Entry points (handlers, routes)
   - Layer boundaries (handler -> usecase -> domain)
   - Shared utilities or helpers

### Step 2: Write SPEC.md (skip if external spec provided)

If the user provided an external spec (Notion, PRD, etc.), skip this step — the external document serves as the spec. Reference it in DESIGN.md instead.

Otherwise, write SPEC.md with requirements and acceptance criteria only. Keep high-level — no implementation details.

### Step 3: Write DESIGN.md

Architecture document covering:
- File structure and new/modified files
- Data flow with ALL transformation points (with `file:line` references)
- API contracts and interfaces
- Integration points with existing code
- Patterns being followed (referenced from codebase, not generic)
- All code path variants explicitly listed

**DESIGN.md must include a "Data Flow" section** that maps every place data changes shape. This prevents silent field drops in converters and adapters.

### Step 4: Wait for User Review

Show the user SPEC.md and DESIGN.md. Wait for feedback before proceeding to validation.

## Validation Phase

Execute continuously — **no stopping until PR is created**.

```
codex (iteration loop) -> PR
```

### Step-by-Step

1. **Run codex agent** (MANDATORY)
   - Architecture-focused review (NOT task scoping — that's plan-workflow's job)
   - Returns APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION

   **Prompt template:**
   ```
   Review this feature design for architectural soundness.

   **Task:** Architecture Review
   **Iteration:** {N} of 3
   **Previous feedback:** {summary if iteration > 1}

   Evaluate:
   - Are the requirements clear and measurable?
   - Is the design architecturally sound?
   - Does the design follow existing codebase patterns?
   - Are ALL data transformation points identified?
   - Are integration points complete (no missing touchpoints)?
   - Are there missing edge cases or risks?

   **CRITICAL CHECKS (Data Flow):**
   - [ ] Data Transformation Points: Are ALL converter functions listed in DESIGN.md?
   - [ ] If a field is added to proto, does it appear in EVERY converter (including params adapters)?
   - [ ] Existing Standards: Are patterns referenced with file:line (not generic)?
   - [ ] Silent Drop Risk: Could any field be lost in convertToParams() or similar adapters?
   - [ ] Integration Completeness: Are ALL places where new code touches existing code listed?

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

3. **Create PR** with design docs only:
   ```bash
   git add doc/projects/<feature-name>/
   git commit -m "docs: add design for <feature-name>"
   gh pr create --draft --title "Design: <feature-name>" --body "..."
   ```

## Branch Naming

Always use `-plan` suffix (e.g., `ENG-123-auth-plan` or `auth-feature-plan`). This:
- Preserves Linear issue ID convention (`<ISSUE-ID>-<description>`)
- Triggers plan-specific PR gate path (requires codex marker only)

## When to Use This Workflow

- User asks to "add", "create", "build", or "implement" something new
- User describes a new feature or capability
- Planning substantial changes (3+ files)
- User does NOT reference an existing DESIGN.md

## When NOT to Use

- User references a DESIGN.md -> use `plan-workflow` (task breakdown)
- Bug fixes -> use `bugfix-workflow`
- Implementing planned tasks -> use `task-workflow`
- Small changes (<50 lines) -> implement directly

## Core Reference

See [execution-core.md](../../rules/execution-core.md) for:
- codex iteration rules
- Pause conditions
