---
name: plan-workflow
description: Create planning documents and a documentation-only PR. Auto-invoked for new features. Implementation happens separately via task-workflow.
user-invocable: false
---

# Plan Workflow

Create planning documents (SPEC.md, DESIGN.md, PLAN.md, TASK*.md) and submit them as a documentation-only PR for review.

## Purpose

This workflow produces **planning documentation only**. No implementation code.

## Entry Phase

Before planning, clarify requirements:

1. **Requirements unclear?** -> Invoke `/brainstorm` -> `[wait for user]`
2. **Requirements clear** -> Proceed to setup

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
   mkdir -p doc/projects/<feature-name>/tasks
   ```

## Planning Phase

1. **Invoke `/plan-implementation`** to create documents:
   - SPEC.md - Requirements and acceptance criteria
   - DESIGN.md - Architecture and approach
   - PLAN.md - Task breakdown with dependencies
   - tasks/TASK*.md - Individual implementation tasks

2. **Wait for planning to complete** - User reviews documents

## Validation Phase

Execute continuously - **no stopping until PR is created**.

```
codex (iteration loop) -> PR
```

### Step-by-Step

1. **Run codex agent** (MANDATORY)
   - Deep reasoning review for architectural soundness, feasibility, risks
   - Returns APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION

   **Prompt template:**
   ```
   Review this implementation plan for architectural soundness and feasibility.

   **Task:** Plan Review
   **Iteration:** {N} of 3
   **Previous feedback:** {summary if iteration > 1}

   Evaluate:
   - Are the requirements clear and measurable?
   - Is the design architecturally sound?
   - Are task scopes appropriate (~200 LOC)?
   - Are there missing edge cases or risks?
   - Is the dependency ordering correct?

   **CRITICAL CHECKS (Data Flow & Scope):**
   - [ ] Data Transformation Points: Are ALL converter functions listed in DESIGN.md?
   - [ ] If a field is added to proto, does it appear in EVERY converter (including params adapters)?
   - [ ] Existing Standards: Are patterns referenced with file:line (not generic)?
   - [ ] Cross-Task Scope: If TASK1 adds X to endpoints A and B, do tasks exist for BOTH?
   - [ ] Coverage Matrix: Does PLAN.md show which tasks handle which new fields/endpoints?
   - [ ] Silent Drop Risk: Could any field be lost in convertToParams() or similar adapters?

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

## PR Template

```markdown
## Summary
Planning documents for <feature-name>.

## Documents
- [SPEC.md](./doc/projects/<feature>/SPEC.md) - Requirements
- [DESIGN.md](./doc/projects/<feature>/DESIGN.md) - Architecture
- [PLAN.md](./doc/projects/<feature>/PLAN.md) - Task breakdown

## Implementation
After this PR is merged, implement via:
```
implement @doc/projects/<feature>/tasks/TASK0.md
```

## Review Checklist
- [ ] Requirements are clear and measurable
- [ ] Design follows codebase patterns
- [ ] Tasks are scoped appropriately (~200 LOC each)
- [ ] No circular dependencies between tasks
- [ ] Coverage Matrix populated for all new fields/endpoints
- [ ] All transformation points have file:line references
- [ ] All code path variants explicitly listed in DESIGN.md
```

## Branch Naming

Always use `-plan` suffix (e.g., `ENG-123-auth-plan` or `auth-feature-plan`). This:
- Preserves Linear issue ID convention (`<ISSUE-ID>-<description>`)
- Triggers plan-specific PR gate path (requires codex marker)

## When to Use This Workflow

- User asks to "add", "create", "build", or "implement" something new
- User describes a new feature or capability
- Planning substantial changes (3+ files)

## When NOT to Use

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
