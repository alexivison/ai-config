---
name: plan-workflow
description: Create planning documents and a documentation-only PR. Auto-invoked for new features. Implementation happens separately via task-workflow.
user-invocable: false
---

# Plan Workflow

Create planning documents (SPEC.md, DESIGN.md, PLAN.md, TASK*.md) and submit them as a documentation-only PR for review.

## Purpose

This workflow produces **planning documentation only**. No implementation code.

After the plan PR is merged, use `task-workflow` to implement each task.

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
plan-reviewer (iteration loop) -> PR
```

### Step-by-Step

1. **Run plan-reviewer agent** (MANDATORY)
   - Reviews all documents against plan-review guidelines
   - Returns APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION

2. **Handle verdict:**
   | Verdict | Action |
   |---------|--------|
   | APPROVE | Continue to PR |
   | REQUEST_CHANGES | Fix issues, re-run plan-reviewer |
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
```

## Branch Naming

Always use `-plan` suffix (e.g., `ENG-123-auth-plan` or `auth-feature-plan`). This:
- Preserves Linear issue ID convention (`<ISSUE-ID>-<description>`)
- Triggers plan-specific PR gate path (only requires plan-reviewer marker)

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

See [execution-core.md](/Users/aleksituominen/.claude/rules/execution-core.md) for:
- plan-reviewer iteration rules
- Pause conditions
