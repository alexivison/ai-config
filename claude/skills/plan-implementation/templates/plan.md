# PLAN.md Template

**Answers:** "In what order do we build it?"

## Prerequisites

- SPEC.md exists with acceptance criteria
- DESIGN.md exists with technical details

## Structure

```markdown
# <Feature Name> Implementation Plan

> **Goal:** [One sentence — what this achieves for users/system]
>
> **Architecture:** [2-3 sentences — key technical approach, main components]
>
> **Tech Stack:** [Languages, frameworks, libraries involved]
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Scope

What this plan covers. If multi-service, note the order.

## Task Granularity

- [ ] **Standard** — ~200 lines of implementation (tests excluded), split if >5 files (default)
- [ ] **Atomic** — 2-5 minute steps with checkpoints (for high-risk: auth, payments, migrations)

## Agent Execution Strategy

- [ ] **Sequential** — Tasks in order (default)
- [ ] **Parallel** — Some tasks concurrent (see graph)

After each task: run verification, commit, update checkbox here.

## Tasks

- [ ] [Task 1](./tasks/TASK1-short-title.md) — <Description> (deps: none)
- [ ] [Task 2](./tasks/TASK2-short-title.md) — <Description> (deps: Task 1)
- [ ] [Task 3](./tasks/TASK3-short-title.md) — <Description> (deps: Task 1)
- [ ] [Task 4](./tasks/TASK4-short-title.md) — <Description> (deps: Task 2, Task 3)

## Coverage Matrix (REQUIRED for new fields/endpoints)

**Purpose:** Verify that every new field/endpoint added in one task is handled in all related tasks.

| New Field/Endpoint | Added In | Code Paths Affected | Handled By | Converter Functions |
|--------------------|----------|---------------------|------------|---------------------|
| `user_context` | Task 1 (schema) | Path A, Path B | Task 2 (A), Task 3 (B) | `fromProto()`, `convertParams()` |
| `new_endpoint` | Task 1 | v1, v2 | Task 4 (both) | `translatorV1()`, `translatorV2()` |

**Validation:** Each row must have complete coverage. If Task 1 adds something affecting paths A and B, tasks must exist for BOTH.

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

## Definition of Done

- [ ] All task checkboxes complete
- [ ] All verification commands pass
- [ ] SPEC.md acceptance criteria satisfied
```

## Notes

- Target ~200 lines per task (standard) or 2-5 min steps (atomic)
- Task files go in `tasks/` folder with naming: `TASK<N>-<kebab-case-title>.md`
- Use ASCII for dependency graph (not Mermaid)
- Each task = one PR, independently mergeable
- Reference skills with `@skill-name` syntax (e.g., `@write-tests`)
