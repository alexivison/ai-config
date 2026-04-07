## Plan Revision Request

The user reviewed the plan at <plan_path> and has feedback:

<user's feedback, verbatim or faithfully paraphrased>

## Instructions
- Read current plan at <plan_path> and all TASK*.md files in tasks/ subfolder
- Apply requested changes to BOTH PLAN.md and affected TASK*.md files
- If feedback changes task boundaries, ordering, or scope: regenerate affected TASK*.md
- Follow canonical templates at ~/.codex/skills/planning/templates/
- Write updated plan to same path (overwrite)
- Preserve parts the user didn't comment on
- Keep PLAN.md checkbox-links and TASK*.md files in sync

## Response File Contract
Write to response file:
- STATUS: SUCCESS or FAILED with reason
- PLAN: <plan path>
- TASKS: list of all TASK*.md paths (created, updated, unchanged)
- CHANGED: list of files modified in this revision
