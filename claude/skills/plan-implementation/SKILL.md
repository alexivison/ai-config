---
name: plan-implementation
description: Plans features and projects for agentic implementation. Creates SPEC.md, DESIGN.md, PLAN.md, and TASK*.md files that agents can execute autonomously. Use when starting a new feature, planning implementation tasks, breaking down large changes, or when the user mentions planning, specs, or task breakdown.
user-invocable: true
---

# Planning Implementations

Break down features and projects into structured, agent-executable implementation plans.

## Quick Start

For a new feature:
1. Create worktree: `git worktree add ../<repo>-<branch> -b <branch>`
2. Create `doc/projects/<feature-name>/`
3. Write SPEC.md (what should it do?)
4. Write DESIGN.md (how will it work?)
5. Write PLAN.md + tasks/TASK*.md (implementation steps)

## When to Use

| Scenario | Files Created |
|----------|---------------|
| Small change | SPEC.md only |
| New feature | SPEC.md + DESIGN.md |
| Migration | LEGACY_DESIGN.md + DESIGN.md + SPEC.md |
| Ready to implement | Add PLAN.md + tasks/TASK*.md |

**Don't use for**: Bug fixes, quick refactors, or changes under ~50 lines.

## Output Location

`doc/projects/<project-name>/`

## Workflow

### Step 0: Setup Worktree (if new branch needed)

```bash
git worktree add ../<repo>-<feature-name> -b <branch-name>
cd ../<repo>-<feature-name>
```

See `~/.claude/rules/development.md` for branch naming conventions.

### Step 1: Determine Scope

Ask the user (if not clear):
- What are we building/changing?
- Is this a migration from existing functionality?
- Do SPEC.md/DESIGN.md already exist?

### Step 2: Create Documentation

| Document | Purpose | Template |
|----------|---------|----------|
| SPEC.md | Requirements, acceptance criteria | [spec.md](./templates/spec.md) |
| DESIGN.md | Architecture, file structure, APIs | [design.md](./templates/design.md) |
| LEGACY_DESIGN.md | Current system (migrations only) | [legacy-design.md](./templates/legacy-design.md) |
| PLAN.md | Task order, dependencies | [plan.md](./templates/plan.md) |
| tasks/TASK*.md | Step-by-step implementation | [task.md](./templates/task.md) |

---

## Plan Header (Required)

Every PLAN.md must start with:

```markdown
# <Feature Name> Implementation Plan

> **Goal:** [One sentence — what this achieves]
>
> **Architecture:** [2-3 sentences — key technical approach]
>
> **Tech Stack:** [Relevant technologies]
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)
```

This ensures any agent (or human) can understand the plan without reading other docs first.

---

## Task Granularity

Choose based on complexity:

### Standard Mode (default)

- ~200 lines of implementation code (tests excluded from count)
- Each task fits in single agent context window
- If task touches >5 files, split it

### Atomic Mode (for complex/risky changes)

Break tasks into 2-5 minute steps:

```markdown
## Steps

1. [ ] Write failing test for [specific behavior]
2. [ ] Run test, verify it fails
3. [ ] Implement minimal code to pass
4. [ ] Run test, verify it passes
5. [ ] Commit: "[type]: [description]"
```

Use atomic mode when:
- High-risk changes (auth, payments, data migrations)
- Unfamiliar codebase or technology
- Complex state management
- User explicitly requests granular breakdown

---

## Agent-Optimized Guidelines

### Testing in Tasks

- Include tests in the same task/PR as implementation
- Each task should have its own test requirements
- Reference `@write-tests` skill for methodology

### Every Task Must Include

- **Issue:** Link to issue tracker (e.g., `ENG-123`) or descriptive slug
- **Required context**: Files agent reads first
- **Files to modify**: Exact paths with actions
- **Verification commands**: Type check, tests, lint
- **Acceptance criteria**: Machine-verifiable

### Explicit Over Implicit

- Exact file paths, not patterns
- Before/after code, not descriptions
- Line numbers when modifying existing code

### Context Independence

- Each task independently executable
- Don't assume agent remembers previous tasks
- List all dependencies explicitly

### Documentation Verbosity

- **SPEC.md / PLAN.md / DESIGN.md**: High-level requirements only. Avoid implementation code examples.
- **TASK files**: Include implementation details needed for execution (function signatures, type definitions, patterns). Keep focused on *what* to build, not full consumer integration examples.
- Link between documents rather than duplicating content (e.g., "See TASK6.md for details")

### Requirements Over Implementation

- Focus on requirements, references, and key gotchas
- Reference existing implementations rather than duplicating code
- Don't provide near-complete code implementations in tasks
- List test cases as bullet points, not detailed test code
- Trust implementer agents to handle detailed implementation decisions

---

## Skill References

Reference other skills inline using `@skill-name`:

| Reference | Meaning |
|-----------|---------|
| `@write-tests` | Use Testing Trophy methodology |
| `@code-review` | Run code review before PR |
| `@minimize` | Check for bloat before finalizing |
| `@brainstorm` | Use if requirements unclear |

Example in task: "Write tests following `@write-tests` methodology."

---

## Post-Planning Handoff

After plan is complete, offer:

1. **Implement now** — Start with Task 1
2. **Review first** — User reviews plan before implementation
3. **Parallel tasks** — Identify which tasks can run concurrently

Always wait for user confirmation before starting implementation.
