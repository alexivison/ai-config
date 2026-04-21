# Source-Agnostic Workflow

> **Goal:** Make the execution pipeline (task-workflow, requirements-auditor, execution-core) work regardless of where work was planned — TASK files, OpenSpec, or any other planning source — without touching external tool configs.
>
> **Approach:** Remove hardcoded TASK*.md assumptions from the execution pipeline. The pipeline needs scope, requirements, and a goal as text. Where that text came from is the caller's problem, not the engine's.

## Tasks

- [ ] [Task 1](./tasks/TASK1-source-agnostic-task-workflow.md) — Make task-workflow accept scope, requirements, and goal from any source (deps: none)
- [ ] [Task 2](./tasks/TASK2-format-blind-scribe.md) — Make the requirements-auditor receive requirements as text instead of reading planning files (deps: Task 1)
- [ ] [Task 3](./tasks/TASK3-update-claude-md-and-execution-core.md) — Update CLAUDE.md and execution-core to source-agnostic language (deps: Task 1, Task 2)

## Dependency Graph

```
Task 1 ───┬───> Task 3
Task 2 ───┘
```

Task 1 and Task 2 are independent of each other but both must land before Task 3.

## Definition of Done

- [ ] task-workflow description and preflight do not mention TASK*.md as the only valid input
- [ ] task-workflow still works with classic TASK files (backward compatible)
- [ ] requirements-auditor receives requirements and scope as text in its prompt
- [ ] execution-core uses source-agnostic language throughout
- [ ] CLAUDE.md states all implementation follows execution-core regardless of entry point
- [ ] No OpenSpec-specific or any other tool-specific code added to this repo
