---
name: plan-workflow
description: >-
  Orchestrate plan creation by dispatching The Wizard (Codex CLI) to do deep research
  and produce a PLAN.md. Claude gathers context, dispatches The Wizard, presents findings,
  relays user feedback, and verifies the final plan. Use when the user wants to plan
  a feature, investigate a ticket, design an approach, create a PLAN.md, scope work,
  or says things like "plan this", "how should we approach", "let's think through",
  "create a plan for", or references a Linear ticket they want planned. Also use when
  task-workflow needs a plan that doesn't exist yet. This is NOT a skill for Claude
  to plan alone — The Wizard does the deep reasoning; Claude orchestrates.
user-invocable: true
---

# Plan Workflow

Orchestrate The Wizard (Codex CLI) to produce a PLAN.md. You are the Paladin — your role
is context-gathering, dispatch, verification, and relay. The Wizard does the deep research
and plan authoring.

## Phase 1 — Gather Context

Before dispatching The Wizard, assemble everything needed for good reasoning.

1. **Understand the ask** — What does the user want planned? A Linear ticket, a feature
   idea, a bug investigation, an architectural change? Extract the goal and constraints.
2. **Fetch external context** — If the user references a Linear ticket, fetch it via MCP.
   If they mention a Notion doc, fetch that. Gather all external inputs first.
3. **Read relevant code** — Identify the files, modules, or areas of the codebase that
   the plan will touch. Read them. Codex can read files too, but pre-loading key context
   into the prompt reduces Codex's search time and improves plan quality.
4. **Check for existing plans** — Look for `PLAN.md` or `plans/*.md` in the repo. If a
   plan already exists for this work, the user may want iteration rather than creation.
5. **Identify constraints** — Deadlines, dependencies, blocked-by items, scope limits.
   These go into the Codex prompt so the plan accounts for them.

**Output of Phase 1:** A mental model of the work plus all context needed for the prompt.
Do NOT write a plan yourself. Proceed to dispatch.

## Phase 2 — Dispatch to Codex

Compose a rich prompt and send it to Codex via `transport prompt`. The prompt quality directly
determines plan quality — invest here.

### Prompt Construction

Write the prompt to a temp file (prompts with quotes and backticks break inline shell):

```bash
PROMPT_FILE=$(mktemp /tmp/codex-plan-prompt-XXXXXX.md)
cat > "$PROMPT_FILE" << 'PROMPT_EOF'
## Task
Create a PLAN.md for: <goal description>

## Context
<paste or summarize the gathered context: ticket details, relevant code excerpts,
existing architecture, constraints, user preferences>

## Requirements
- Use the canonical planning templates at `~/.codex/skills/planning/templates/` — do NOT
  invent a parallel schema. Specifically:
  - `plan.md` template for PLAN.md (includes checkbox-links, dependency graph, coverage matrix)
  - `task.md` template for each TASK*.md (includes scope boundary, reference, design refs,
    data transformation checklist, files to create/modify, tests, acceptance criteria)
- Create BOTH a PLAN.md AND individual TASK*.md files
- All plan artifacts go in `docs/projects/<project-slug>/`:
  - `docs/projects/<project-slug>/PLAN.md`
  - `docs/projects/<project-slug>/SPEC.md`
  - `docs/projects/<project-slug>/DESIGN.md`
  - `docs/projects/<project-slug>/tasks/TASK<N>-<kebab-case-title>.md`
  - Any diagrams/assets alongside PLAN.md
- PLAN.md Tasks section MUST use checkbox-link form:
  `- [ ] [Task 1](./tasks/TASK1-short-title.md) — Description (deps: none)`
- Keep it concise — a plan is a map, not a novel

## Output
Write the plan to: docs/projects/<project-slug>/PLAN.md
Write task files to: docs/projects/<project-slug>/tasks/TASK<N>-<kebab-case-title>.md (one per discrete task)

## Response File Contract
After writing all files, write a summary to the response file (<response_path>) containing:
- `STATUS: SUCCESS` or `STATUS: FAILED` with reason
- `PLAN: <actual plan path>`
- `TASKS:` followed by one path per line for each TASK*.md created
- Any warnings or assumptions made
PROMPT_EOF

party-cli transport \
  prompt "$(cat "$PROMPT_FILE")" <work_dir>
```

### Error Handling

Check the script's stdout for sentinel strings:
- `CODEX_TASK_REQUESTED` — success, proceed to wait
- `CODEX_TASK_DROPPED` — Codex pane is busy. Wait briefly and retry, or inform the user.
- `CODEX_NOT_AVAILABLE` — master session with no Codex pane. Inform the user that planning
  requires a worker session with Codex access.

### Choosing the Right Mode

| Situation | Mode | Why |
|-----------|------|-----|
| New plan from scratch | `transport prompt "<task>" <work_dir>` | Codex creates the plan file and writes it |
| Review an existing plan | `transport plan-review "<plan_path>" <work_dir>` | Uses the plan-review template (ungated), returns TOON findings |
| Iterate on Codex's draft | `transport prompt "<feedback>" <work_dir>` | Send feedback, ask for revisions |

`transport plan-review` is for evaluating a plan that already exists as a file. For initial
creation, use `transport prompt` with explicit instructions to write the plan file.

### While Codex Works

Codex dispatch is non-blocking. You are NOT idle:

- **Verify file paths** mentioned in your context-gathering — do they still exist?
- **Prepare follow-up context** — if the user mentioned related work, gather that too
- **Draft verification questions** — what should you check when the plan arrives?

Do NOT poll Codex. Wait for the `[CODEX]` notification.

## Phase 3 — Receive and Verify

When `[CODEX] Task complete. Response at: <path>` arrives:

1. **Read the response file first** — The `<path>` from the notification is Codex's
   authoritative result channel. Check `STATUS:` line — if FAILED, report to user.
   Extract `PLAN:` and `TASKS:` paths. Note any warnings.
2. **Read the plan and task files** — Open PLAN.md and each TASK*.md at the paths from
   the response file. If paths differ from your prompt, use the response file's paths.
3. **Verify completeness:**
   - Does it cover all requirements from the user's ask?
   - Are file paths real? (`Glob` or `Grep` to confirm)
   - Are scope boundaries clear (In Scope / Out of Scope)?
   - Are tasks ordered correctly (dependencies respected)?
   - Is the scope reasonable — not too ambitious, not too narrow?
4. **Cross-check against code** — If the plan references specific functions, classes,
   or APIs, verify they exist and behave as the plan assumes
5. **Flag concerns** — Note anything questionable but do NOT silently fix the plan.
   Your concerns go to the user, not into the file.

## Phase 4 — Present to User

Present the plan with your verification notes:

1. **Show the plan** — Summarize key sections, or show in full if short
2. **Highlight your concerns** — If file paths were wrong, scope seems off, or tasks
   are missing, say so clearly
3. **Invite feedback** — Ask the user if they want changes, have questions, or approve

Keep your presentation concise. The plan speaks for itself — add only what the user
needs to make a decision.

## Phase 5 — Iterate

If the user has feedback, relay it to Codex:

```bash
REVISION_FILE=$(mktemp /tmp/codex-plan-revision-XXXXXX.md)
cat > "$REVISION_FILE" << 'PROMPT_EOF'
## Plan Revision Request

The user reviewed the plan at <plan_path> and has feedback:

<user's feedback, verbatim or faithfully paraphrased>

## Instructions
- Read the current plan at <plan_path> and all TASK*.md files in the tasks/ subfolder
- Apply the requested changes to BOTH PLAN.md and any affected TASK*.md files
- If feedback changes task boundaries, ordering, or scope: regenerate affected TASK*.md files
- Follow the canonical templates at ~/.codex/skills/planning/templates/
- Write the updated plan to the same path (overwrite)
- Preserve parts the user didn't comment on
- Keep PLAN.md checkbox-links and TASK*.md files in sync

## Response File Contract
Write to the response file:
- STATUS: SUCCESS or FAILED with reason
- PLAN: <plan path>
- TASKS: list of all TASK*.md paths (created, updated, or unchanged)
- CHANGED: list of files that were modified in this revision
PROMPT_EOF

party-cli transport \
  prompt "$(cat "$REVISION_FILE")" <work_dir>
```

Repeat Phase 3–5 until the user approves.

**Add your own concerns too.** If you spotted issues in Phase 3, include them in the
revision prompt alongside the user's feedback. You are a reviewer, not just a relay.

## Phase 6 — Finalize

Once the user approves:

1. **Confirm plan location** — Ensure PLAN.md and TASK*.md files are at the expected
   paths (typically `PLAN.md` in the repo root plus `tasks/TASK-*.md`)
2. **Dispatch plan review (MANDATORY)** — Per CLAUDE.md contract, every created plan
   must go through `transport plan-review`. This is not optional:
   ```bash
   party-cli transport \
     plan-review "<plan_path>" <work_dir>
   ```
   When `[CODEX] Plan review complete. Findings at: <path>` arrives, triage findings
   per tmux-handler (blocking / non-blocking / out-of-scope). Present any blocking
   findings to the user and iterate if needed before proceeding.
3. **Signal readiness** — Tell the user the plan is ready for execution. If appropriate,
   suggest: "Shall I begin with `/task-workflow`?"

## Quick Reference

| Phase | Paladin's Job | Codex's Job |
|-------|---------------|-------------|
| Gather | Read code, fetch tickets, assemble context | — |
| Dispatch | Compose prompt, send via party-cli transport | Research, write PLAN.md + TASK*.md (canonical templates) |
| Verify | Check paths, scope, completeness | — |
| Present | Summarize plan, flag concerns | — |
| Iterate | Relay feedback + own concerns | Revise plan |
| Finalize | Confirm location, mandatory plan-review | Formal plan review (always) |

## Anti-Patterns

- **Writing the plan yourself** — You are the Paladin, not the Wizard. Dispatch to Codex.
- **Thin prompts** — "Make a plan for X" wastes Codex's cycles. Rich context = better plans.
- **Silent corrections** — If the plan has issues, tell the user. Don't edit Codex's output.
- **Skipping verification** — File paths in plans go stale. Always verify against the codebase.
- **Polling Codex** — The dispatch is non-blocking. Work on verification prep, not `sleep`.

## Integration with Other Workflows

- **task-workflow** executes TASK*.md files. This skill produces both PLAN.md (overall plan)
  and TASK*.md files (executable tasks), so the output feeds directly into task-workflow.
- **party-dispatch** can parallelize tasks from the plan across worker sessions.
- **bugfix-workflow** may invoke this skill when investigation reveals the fix needs planning.
