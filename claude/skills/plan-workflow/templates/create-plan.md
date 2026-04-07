## Task
Create a PLAN.md for: <goal description>

## Context
<paste or summarize: ticket details, relevant code excerpts, existing architecture, constraints, user preferences>

## Requirements
- Use canonical planning templates at `~/.codex/skills/planning/templates/` — do NOT invent parallel schema
  - `plan.md` template for PLAN.md (checkbox-links, dependency graph, coverage matrix)
  - `task.md` template for each TASK*.md (scope boundary, reference, design refs, data transformation checklist, files, tests, acceptance criteria)
- Create BOTH PLAN.md AND individual TASK*.md files
- All artifacts in `docs/projects/<project-slug>/`:
  - `PLAN.md`, `SPEC.md`, `DESIGN.md`
  - `tasks/TASK<N>-<kebab-case-title>.md`
- PLAN.md Tasks section: `- [ ] [Task 1](./tasks/TASK1-short-title.md) — Description (deps: none)`
- Keep it concise — a plan is a map, not a novel

## Output
Write plan to: docs/projects/<project-slug>/PLAN.md
Write tasks to: docs/projects/<project-slug>/tasks/TASK<N>-<kebab-case-title>.md

## Response File Contract
After writing all files, write summary to response file (<response_path>):
- `STATUS: SUCCESS` or `STATUS: FAILED` with reason
- `PLAN: <actual plan path>`
- `TASKS:` followed by one path per line
- Any warnings or assumptions made
