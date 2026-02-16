---
name: design-workflow
description: Design-first planning phase. Creates SPEC.md and DESIGN.md with codex architecture validation. For task breakdown from an existing DESIGN.md, use plan-workflow instead.
user-invocable: true
---

# Design Workflow

Create SPEC.md + DESIGN.md, validate architecture via codex, submit as draft PR. This is **Phase 1** of two-phase planning.

## Routing

| Condition | Workflow |
|-----------|----------|
| No DESIGN.md for this feature | **design-workflow** (this) |
| DESIGN.md exists for this feature | plan-workflow (task breakdown) |
| Bug/error | bugfix-workflow |
| TASK*.md referenced | task-workflow |

**Discovery convention:** Check `doc/projects/<feature>/DESIGN.md` or user-provided path. The hook (`skill-eval.sh`) uses keyword-only heuristics — this skill's entry gate owns the actual routing decision based on filesystem state.

## Entry Gate

Check `doc/projects/<feature>/DESIGN.md` or user-provided path:

- **DESIGN.md exists → STOP. Redirect:** "DESIGN.md already exists. Run `/plan-workflow` to create task breakdown."
- **No DESIGN.md → proceed to Entry Phase below.**

## Entry Phase

1. **External spec provided?** (Notion, PRD, etc.) → skip SPEC.md, create DESIGN.md only
2. **Requirements unclear?** → `/brainstorm` → wait for user
3. **Requirements clear** → proceed

## Setup

1. Create worktree with `-plan` suffix: `git worktree add ../<repo>-<feature>-plan -b <feature>-plan`
2. Create `doc/projects/<feature-name>/`

## Design Phase

### Step 1: Deep Codebase Exploration (CRITICAL)

Before writing anything:
1. Find existing standards and abstractions to extend
2. Map ALL data transformation points (converters, adapters, params functions)
3. List integration points (handlers, layer boundaries, shared utilities)

### Step 2: Write SPEC.md (skip if external spec)

Requirements and acceptance criteria only. No implementation details.

### Step 3: Write DESIGN.md

- File structure, new/modified files
- Data flow with ALL transformation points (`file:line` references)
- API contracts and interfaces
- Integration points with existing code
- Patterns referenced from codebase (not generic)

**Must include "Data Flow" section** mapping every shape change.

### Step 4: Wait for User Review

## Validation Phase

Run continuously until PR created.

1. **Codex agent** (MANDATORY) — architecture review, not task scoping
2. Handle verdict: APPROVE → PR, REQUEST_CHANGES → fix/rerun, NEEDS_DISCUSSION → ask user
3. Create draft PR with design docs only

## Branch Naming

Always `-plan` suffix. Triggers plan-specific PR gate (codex marker only).

## Templates

Use `../plan-workflow/templates/spec.md` and `../plan-workflow/templates/design.md`.

## Core Reference

See `../../rules/execution-core.md`.
