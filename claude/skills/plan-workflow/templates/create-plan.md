## Task
Create a dated plan doc for: <goal description>

## Context
<paste or summarize: ticket details, relevant code excerpts, existing architecture, constraints, user preferences>

## Requirements
- Use canonical planning templates at `~/.codex/skills/planning/templates/` — do NOT invent parallel schema
  - `plan.md` template for the primary plan doc (checkbox-links, dependency graph, coverage matrix)
  - `task.md` template for any separate task doc that is genuinely needed
- Write the primary plan doc to `~/.ai-party/docs/research/YYYY-MM-DD-plan-<project-slug>.md`
- Add required frontmatter to the plan doc:
  - `title`
  - `date`
  - `agent: codex`
  - `type: plan`
  - `related`
  - `status: draft`
- Default to a single-file plan. Only create separate task docs when the work is too large for one file.
- If separate task docs are needed, keep them flat in the same directory:
  - `~/.ai-party/docs/research/YYYY-MM-DD-task-<project-slug>-<n>.md`
- Plan task links must point at flat sibling files, not a `tasks/` subdirectory.
- Keep it concise — a plan is a map, not a novel

## Output
Write plan to: `~/.ai-party/docs/research/YYYY-MM-DD-plan-<project-slug>.md`
Write any separate task docs to: `~/.ai-party/docs/research/YYYY-MM-DD-task-<project-slug>-<n>.md`

## Response File Contract
After writing all files, write summary to response file (<response_path>):
- `STATUS: SUCCESS` or `STATUS: FAILED` with reason
- `PLAN: <actual plan path>`
- `TASKS:` followed by one path per line (omit if none)
- Any warnings or assumptions made
