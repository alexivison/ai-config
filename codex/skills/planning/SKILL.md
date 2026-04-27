---
name: planning
description: >
  Feature planning from discovery through task breakdown. Produces design docs
  and implementation plans under `~/.ai-party/docs/research/`. Use when asked
  to plan a feature, create a design doc, break work into tasks, or produce
  plan or design docs.
---

# Planning Skill

Feature planning from discovery through task breakdown. Produces design docs and implementation plans in the canonical docs tree. Only create repo-tracked planning artifacts when the user explicitly asks for them.

## Modes

| Mode | Purpose | Output |
|------|---------|--------|
| **Discover** | Explore codebase, clarify requirements, map standards and integration points | Notes (internal) |
| **Design** | Write architecture and data flow | `YYYY-MM-DD-design-<slug>.md` |
| **Plan** | Break design into executable tasks | `YYYY-MM-DD-plan-<slug>.md` (+ optional `YYYY-MM-DD-task-...` docs) |

Start wherever the work requires. No hard entry gate — jump straight to Plan if the design is already clear.

## Readiness Gate (Before Plan Output)

Before generating the dated plan doc or related task docs, verify ALL of the following. If any are missing, go back and fill them — materialise them into the design doc if needed.

| Requirement | Evidence |
|-------------|----------|
| Existing standards referenced | `file:line` refs, not just file names |
| Data transformation points mapped | Every converter/adapter for each code path |
| Integration points identified | Where new code touches existing code |
| Acceptance criteria defined | Machine-verifiable, not vague |
| UI/component task design context captured | Each UI/component TASK includes a Figma node URL or image/screenshot link/path |

If design decisions were made inline during planning, auto-materialise them into the design doc before final plan output.

## Discover Mode

1. Read any existing specs, PRDs, or issue descriptions
2. Explore codebase to find existing patterns and abstractions
3. Map data transformation points (converters, adapters, params functions)
4. List integration points (handlers, layer boundaries, shared utilities)
5. Identify standards with `file:line` references

## Design Mode

1. Write the design doc at `~/.ai-party/docs/research/YYYY-MM-DD-design-<slug>.md`
2. Capture requirements and acceptance criteria in that design doc unless the user explicitly asks for a separate repo-tracked spec
3. All patterns must reference existing code with `file:line`
4. Include "Data Transformation Points" section mapping every shape change

## Plan Mode

1. Read the design doc and any external requirements source
2. Create the primary plan doc at `~/.ai-party/docs/research/YYYY-MM-DD-plan-<slug>.md` with task breakdown, dependencies, and verification commands
3. Create separate task docs only when a single-file plan would become unclear
   - Use flat sibling files: `~/.ai-party/docs/research/YYYY-MM-DD-task-<slug>-<n>.md`
   - For every task that creates or updates UI components, include a `Design References` section with at least one Figma node URL or image/screenshot link/path
4. Evaluate against planning checks (see below)
5. Refine until evaluation passes

## Planning Checks

1. Existing standards referenced with concrete `file:line` paths
2. Data transformation points mapped for schema/field changes
3. Tasks have explicit scope boundaries (in-scope / out-of-scope)
4. Dependencies and verification commands listed per task
5. Requirements reconciled against source inputs; mismatches documented
6. Whole-architecture coherence evaluated across full task sequence
7. UI/component tasks include design references (Figma node URL or image/screenshot link/path)

## Self-Evaluation

Before handing the plan off, record in the plan doc:

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
- [ ] UI/component tasks include design references
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
8. UI/component tasks include design references (Figma node URL or image/screenshot)

## Output

1. Write planning docs directly to `~/.ai-party/docs/research/` without asking the user for a path
2. Use these default filenames:
   - Plan: `YYYY-MM-DD-plan-<slug>.md` with frontmatter `type: plan`
   - Design: `YYYY-MM-DD-design-<slug>.md` with frontmatter `type: design`
   - Separate task plan doc: `YYYY-MM-DD-task-<slug>.md` (or `...-<n>.md` when multiple) with frontmatter `type: plan`
3. Only open a docs PR if the user explicitly wants repo-tracked planning artifacts

## Verification Principle

No claims without command output. If you state something about the codebase, show the evidence (file path, line number, command result).

## Templates

- `./templates/spec.md`
- `./templates/design.md`
- `./templates/plan.md`
- `./templates/task.md`
