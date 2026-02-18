# Planning Skill

Feature planning from discovery through task breakdown. Produces design docs and implementation plans, then submits a draft PR for Claude to review.

## Modes

| Mode | Purpose | Output |
|------|---------|--------|
| **Discover** | Explore codebase, clarify requirements, map standards and integration points | Notes (internal) |
| **Design** | Write architecture and data flow | SPEC.md + DESIGN.md |
| **Plan** | Break design into executable tasks | PLAN.md + TASK*.md |

Start wherever the work requires. No hard entry gate — jump straight to Plan if the design is already clear.

## Readiness Gate (Before Plan Output)

Before generating PLAN.md or TASK*.md, verify ALL of the following. If any are missing, go back and fill them — materialise into DESIGN.md if needed.

| Requirement | Evidence |
|-------------|----------|
| Existing standards referenced | `file:line` refs, not just file names |
| Data transformation points mapped | Every converter/adapter for each code path |
| Integration points identified | Where new code touches existing code |
| Acceptance criteria defined | Machine-verifiable, not vague |

If design decisions were made inline during planning, auto-materialise them into DESIGN.md before final plan output.

## Discover Mode

1. Read any existing specs, PRDs, or issue descriptions
2. Explore codebase to find existing patterns and abstractions
3. Map data transformation points (converters, adapters, params functions)
4. List integration points (handlers, layer boundaries, shared utilities)
5. Identify standards with `file:line` references

## Design Mode

1. Write SPEC.md — requirements and acceptance criteria (skip if external spec provided)
2. Write DESIGN.md — architecture, data flow, transformation points, integration points
3. All patterns must reference existing code with `file:line`
4. Include "Data Transformation Points" section mapping every shape change

## Plan Mode

1. Read DESIGN.md and SPEC.md
2. Create PLAN.md with task breakdown, dependencies, verification commands
3. Create `tasks/TASK*.md` — small, independently executable tasks (~200 LOC each)
4. Evaluate against planning checks (see below)
5. Refine until evaluation passes

## Planning Checks

1. Existing standards referenced with concrete `file:line` paths
2. Data transformation points mapped for schema/field changes
3. Tasks have explicit scope boundaries (in-scope / out-of-scope)
4. Dependencies and verification commands listed per task
5. Requirements reconciled against source inputs; mismatches documented
6. Whole-architecture coherence evaluated across full task sequence

## Self-Evaluation

Before creating PR, record in PLAN.md:

```
## Plan Evaluation Record

PLAN_EVALUATION_VERDICT: PASS | FAIL

Evidence:
- [ ] Existing standards referenced with concrete paths
- [ ] Data transformation points mapped
- [ ] Tasks have explicit scope boundaries
- [ ] Dependencies and verification commands listed per task
- [ ] Requirements reconciled against source inputs
- [ ] Whole-architecture coherence evaluated
```

If FAIL: fix blocking gaps, re-evaluate.

## Review Checklist

1. Requirements are measurable
2. Existing code patterns referenced with file paths
3. Data transformation points mapped
4. Task boundaries clear with in-scope/out-of-scope
5. Risks and dependencies called out
6. Source conflicts called out explicitly
7. Combined end-state architecture is coherent

## Output

1. Create branch with `-plan` suffix (e.g., `ENG-123-feature-plan`)
2. Submit draft docs-only PR containing SPEC.md, DESIGN.md, PLAN.md, TASK*.md
3. Stop at PR — Claude reviews

## Verification Principle

No claims without command output. If you state something about the codebase, show the evidence (file path, line number, command result).

## Templates

- `./templates/spec.md`
- `./templates/design.md`
- `./templates/plan.md`
- `./templates/task.md`
