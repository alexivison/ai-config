# PLAN.md Template

**Answers:** "In what order do we build it?"

## Prerequisites

- SPEC.md exists with acceptance criteria
- DESIGN.md exists with technical details

## Structure

```markdown
# <Feature Name> Implementation Plan

> **Specification:** [SPEC.md](./SPEC.md)
>
> **Design:** [DESIGN.md](./DESIGN.md)

## Scope

What this plan covers. If multi-service, note the order.

## Agent Execution Strategy

- [ ] **Sequential** — Tasks in order (default)
- [ ] **Parallel** — Some tasks concurrent (see graph)

After each task: run verification, commit, update checkbox here.

## Tasks

- [ ] [Task 1](./TASK1.md) — <Description> (deps: none)
- [ ] [Task 2](./TASK2.md) — <Description> (deps: Task 1)
- [ ] [Task 3](./TASK3.md) — <Description> (deps: Task 1)
- [ ] [Task 4](./TASK4.md) — <Description> (deps: Task 2, Task 3)

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

- Target ~200 lines per task
- Use ASCII for dependency graph (not Mermaid)
- Each task = one PR, independently mergeable
