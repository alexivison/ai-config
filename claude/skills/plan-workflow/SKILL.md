---
name: plan-workflow
description: Create PLAN.md and TASK*.md from an approved DESIGN.md. Phase 2 of two-phase planning. For design creation, use design-workflow instead.
user-invocable: true
---

# Plan Workflow

Create task breakdown (PLAN.md + TASK*.md) from an approved DESIGN.md. This is **Phase 2** of two-phase planning.

## Entry Gate (STRICT)

**DESIGN.md must exist.** Check `doc/projects/<feature>/DESIGN.md` or user-provided path.

- DESIGN.md found → proceed to setup
- **No DESIGN.md → STOP. Redirect:** "No DESIGN.md found. Run `/design-workflow` first to create SPEC.md and DESIGN.md."

This boundary is non-negotiable. Plan-workflow does NOT create SPEC.md or DESIGN.md.

## Setup

1. Create worktree with `-plan` suffix: `git worktree add ../<repo>-<ISSUE-ID>-<feature>-plan -b <ISSUE-ID>-<feature>-plan`
2. Locate project directory (where DESIGN.md lives)

## Process

1. Read DESIGN.md and SPEC.md (if present) for requirements and architecture.
2. Explore codebase to validate integration points listed in DESIGN.md.
3. Create PLAN.md with task breakdown, dependencies, and verification commands.
4. Create `tasks/TASK*.md` — small, independently executable tasks (~200 LOC each).
5. Evaluate plan against Required Planning Checks and Review Checklist.
6. Refine docs and re-evaluate until PLAN_EVALUATION_VERDICT: PASS.
7. Run codex for plan review (MANDATORY).
8. Create draft docs-only PR.

## Outputs

- `PLAN.md` — Task breakdown with dependencies and progress checkboxes
- `tasks/TASK*.md` — Individual implementation tasks

## Plan Header (Required)

```markdown
# <Feature Name> Implementation Plan

> **Goal:** [One sentence]
> **Architecture:** [2-3 sentences]
> **Tech Stack:** [Technologies]
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)
```

## Task Granularity

**Standard** (default): ~200 LOC, single context window, ≤5 files per task.

**Atomic** (complex/risky): 2-5 minute TDD steps. Use for auth, payments, data migrations, or unfamiliar codebases.

## Every Task Must Include

- **Issue:** Link or descriptive slug
- **Required context**: Files to read first
- **Files to modify**: Exact paths
- **Verification commands**: Typecheck, tests, lint
- **Acceptance criteria**: Machine-verifiable
- **Scope boundary**: What IS and ISN'T in scope

## Required Planning Checks

1. Existing standards referenced with concrete paths.
2. Data transformation points mapped for schema/field changes.
3. Tasks have explicit scope boundaries.
4. Dependencies and verification commands listed per task.
5. Requirements reconciled against source inputs; mismatches documented.
6. Whole-architecture coherence evaluated across full task sequence.

## Plan Evaluation Record (Required before PR)

Record in `PLAN.md` under `## Plan Evaluation Record`:

```
PLAN_EVALUATION_VERDICT: PASS | FAIL
CODEX_VERDICT: APPROVE | REQUEST_CHANGES | NEEDS_DISCUSSION
```

Include:
- Checklist evidence for Required Planning Checks and Review Checklist
- Source reconciliation with references (or explicit "None")
- If FAIL: blocking gaps listed, docs revised, evaluation rerun

## Codex Review (MANDATORY)

After evaluation passes, run codex agent:

```
Review this implementation plan for architectural soundness and feasibility.

**Task:** Plan Review
**Iteration:** {N} of 3

Evaluate: requirements clarity, design soundness, task scopes (~200 LOC),
edge cases, dependency ordering, data flow integrity, cross-task coverage.

Return structured verdict. On approval: "CODEX APPROVED"
```

| Verdict | Action |
|---------|--------|
| APPROVE | Create PR |
| REQUEST_CHANGES | Fix, re-run |
| NEEDS_DISCUSSION | Ask user |

## Review Checklist

1. Requirements are measurable.
2. Existing code patterns referenced with file paths.
3. Data transformation points mapped.
4. Task boundaries clear with in-scope/out-of-scope.
5. Risks and dependencies called out.
6. Source conflicts called out explicitly.
7. Combined end-state architecture is coherent.

## Branch Naming

Always `-plan` suffix (e.g., `ENG-123-auth-plan`). Triggers plan-specific PR gate (codex marker only).

## Templates

- `./templates/plan.md`
- `./templates/task.md`

## Core Reference

See `../../rules/execution-core.md`.
