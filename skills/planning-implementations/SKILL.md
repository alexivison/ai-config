---
name: planning-implementations
description: Plans features and projects for agentic implementation. Creates SPEC.md, DESIGN.md, PLAN.md, and TASK*.md files that agents can execute autonomously. Use when starting a new feature, planning implementation tasks, breaking down large changes, or when the user mentions planning, specs, or task breakdown.
---

# Planning Implementations

Break down features and projects into structured, agent-executable implementation plans.

## Quick Start

For a new feature:
1. Create `doc/projects/<feature-name>/`
2. Write SPEC.md (what should it do?)
3. Write DESIGN.md (how will it work?)
4. Write PLAN.md + TASK*.md (implementation steps)

## When to Use

| Scenario | Files Created |
|----------|---------------|
| Small change | SPEC.md only |
| New feature | SPEC.md + DESIGN.md |
| Migration | LEGACY_DESIGN.md + DESIGN.md + SPEC.md |
| Ready to implement | Add PLAN.md + TASK*.md |

**Don't use for**: Bug fixes, quick refactors, or changes under ~50 lines.

## Output Location

`doc/projects/<project-name>/`

## Workflow

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
| TASK*.md | Step-by-step implementation | [task.md](./templates/task.md) |

## Agent-Optimized Guidelines

### Task Sizing
- Target ~200 lines per task
- Each task fits in single agent context window
- If task touches >5 files, split it

### Every Task Must Include
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
