# PLAN.md Template

**Answers:** "In what order do we build it?"

## Prerequisites

- A dated design doc exists with acceptance criteria and technical details

## Structure

```markdown
# <Feature Name> Implementation Plan

> **Goal:** [One sentence — what this achieves for users/system]
>
> **Architecture:** [2-3 sentences — key technical approach, main components]
>
> **Tech Stack:** [Languages, frameworks, libraries involved]
>
> **Design:** [<design-filename>](./<design-filename>) | **Related:** <free-text refs>

## Scope

What this plan covers. If multi-service, note the order.

## Task Granularity

- [ ] **Standard** — ~200 lines of implementation (tests excluded), split if >5 files (default)
- [ ] **Atomic** — 2-5 minute steps with checkpoints (for high-risk: auth, payments, migrations)

## Tasks

- [ ] [Task 1](./<task-1-filename>.md) — <Description> (deps: none)
- [ ] [Task 2](./<task-2-filename>.md) — <Description> (deps: Task 1)
- [ ] [Task 3](./<task-3-filename>.md) — <Description> (deps: Task 1)
- [ ] [Task 4](./<task-4-filename>.md) — <Description> (deps: Task 2, Task 3)

If a task creates or updates UI/components, that task file must include a `Design References` section with a Figma node URL or image/screenshot link/path.

## Coverage Matrix (REQUIRED for new fields/endpoints)

**Purpose:** Verify that every new field/endpoint added in one task is handled in all related tasks.

| New Field/Endpoint | Added In | Code Paths Affected | Handled By | Converter Functions |
|--------------------|----------|---------------------|------------|---------------------|
| `user_context` | Task 1 (schema) | Path A, Path B | Task 2 (A), Task 3 (B) | `fromProto()`, `convertParams()` |

**Validation:** Each row must have complete coverage.

## Dependency Graph

```
Task 1 ───┬───> Task 2 ───┐
          │               │
          └───> Task 3 ───┼───> Task 4
```

## Task Handoff State

| After Task | State |
|------------|-------|
| Task 1 | Types exist, no runtime code |
| Task 2 | Feature A works, tests pass |
| Task 4 | Full integration, all tests pass |

## External Dependencies

| Dependency | Status | Blocking |
|------------|--------|----------|
| Backend API | In progress | Task 3 |

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

Source reconciliation: [References or "None"]

## Definition of Done

- [ ] All task checkboxes complete
- [ ] All verification commands pass
- [ ] Design doc acceptance criteria satisfied
```

## Notes

- Target ~200 lines per task (standard) or 2-5 min steps (atomic)
- Write the plan to `~/.ai-party/docs/research/YYYY-MM-DD-plan-<slug>.md`
- Related design docs and optional task docs live as flat sibling files in the same directory
- Use ASCII for dependency graph (not Mermaid)
- Each task = one PR, independently mergeable
