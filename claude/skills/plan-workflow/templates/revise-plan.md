## Plan Revision Request

The user reviewed the plan at <plan_path> and has feedback:

<user's feedback, verbatim or faithfully paraphrased>

## Instructions
- Read the current plan at <plan_path> and any related `YYYY-MM-DD-task-*.md` sibling files
- Apply requested changes to the plan and any affected task docs
- If feedback changes task boundaries, ordering, or scope: regenerate the affected task docs
- Follow canonical templates at ~/.codex/skills/planning/templates/
- Write updated plan to same path (overwrite)
- Preserve parts the user didn't comment on
- Keep flat-file links and related task docs in sync

## Response File Contract
Write to response file:
- STATUS: SUCCESS or FAILED with reason
- PLAN: <plan path>
- TASKS: list of all related task doc paths (created, updated, unchanged)
- CHANGED: list of files modified in this revision
