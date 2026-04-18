---
name: plan-workflow
description: >-
  Orchestrate plan creation by dispatching the companion (default: The Wizard /
  Codex CLI) to do deep research and produce a PLAN.md. The primary agent
  gathers context, dispatches the companion, presents findings, relays user
  feedback, and verifies the final plan. Use when the user wants to plan a
  feature, investigate a ticket, design an approach, create a PLAN.md, scope
  work, or says things like "plan this", "how should we approach", "let's
  think through", "create a plan for", or references a Linear ticket they want
  planned. Also use when task-workflow needs a plan that doesn't exist yet.
  This is NOT a skill for the primary agent to plan alone — the companion does
  the deep reasoning; the primary orchestrates.
user-invocable: true
---

# Plan Workflow

Orchestrate the companion to produce a PLAN.md. You are the Paladin — the default primary persona. Your role is context-gathering, dispatch, verification, and relay. The companion does the deep research and plan authoring.

## Phase 1 — Gather Context

Before dispatching the companion, assemble everything needed for good reasoning.

1. **Understand the ask** — What does the user want planned? A Linear ticket, a feature
   idea, a bug investigation, an architectural change? Extract the goal and constraints.
2. **Fetch external context** — If the user references a Linear ticket, fetch it via MCP.
   If they mention a Notion doc, fetch that. Gather all external inputs first.
3. **Read relevant code** — Identify the files, modules, or areas of the codebase that
   the plan will touch. Read them. The default companion can read files too, but pre-loading key context
   into the prompt reduces its search time and improves plan quality.
4. **Check for existing plans** — Look for `PLAN.md` or `plans/*.md` in the repo. If a
   plan already exists for this work, the user may want iteration rather than creation.
5. **Identify constraints** — Deadlines, dependencies, blocked-by items, scope limits.
   These go into the companion prompt so the plan accounts for them.

**Output of Phase 1:** A mental model of the work plus all context needed for the prompt.
Do NOT write a plan yourself. Proceed to dispatch.

## Phase 2 — Dispatch to the Companion

Compose a rich prompt and send it to the companion via the default transport skill (`agent-transport`, via `tmux-companion.sh --prompt`). The prompt quality directly
determines plan quality — invest here.

### Prompt Construction

Use the template at `templates/create-plan.md` — fill in `<goal description>`, `<context>`, and `<project-slug>`. Write to a temp file and dispatch:

```bash
PROMPT_FILE=$(mktemp /tmp/companion-plan-prompt-XXXXXX.md)
# Copy template, fill in goal/context/slug
cat > "$PROMPT_FILE" << 'PROMPT_EOF'
<filled template from templates/create-plan.md>
PROMPT_EOF

~/.claude/skills/agent-transport/scripts/tmux-companion.sh \
  --prompt "$(cat "$PROMPT_FILE")" <work_dir>
```

### Error Handling

Check the script's stdout for the default transport sentinel strings:
- `COMPANION_TASK_REQUESTED` — success, proceed to wait
- `COMPANION_TASK_DROPPED` — the default companion pane is busy. Wait briefly and retry, or inform the user.
- `COMPANION_NOT_AVAILABLE` — master session with no companion pane. Inform the user that planning
  requires a worker session with companion access.

### Choosing the Right Mode

| Situation | Mode | Why |
|-----------|------|-----|
| New plan from scratch | `--prompt "<task>" <work_dir>` | The companion creates the plan file and writes it |
| Review an existing plan | `--plan-review "<plan_path>" <work_dir>` | Uses the plan-review template (ungated), returns TOON findings |
| Iterate on the companion's draft | `--prompt "<feedback>" <work_dir>` | Send feedback, ask for revisions |

`--plan-review` is for evaluating a plan that already exists as a file. For initial
creation, use `--prompt` with explicit instructions to write the plan file.

Dispatch is non-blocking — verify file paths and prepare follow-up context while waiting. Do NOT poll.

## Phase 3 — Receive and Verify

When `[COMPANION] Task complete. Response at: <path>` arrives:

1. **Read the response file first** — The `<path>` from the notification is the companion's
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

If the user has feedback, use the template at `templates/revise-plan.md` — fill in `<plan_path>` and `<feedback>`, dispatch via `--prompt`. Repeat Phase 3–5 until the user approves.

**Add your own concerns too.** If you spotted issues in Phase 3, include them in the
revision prompt alongside the user's feedback. You are a reviewer, not just a relay.

## Phase 6 — Finalize

Once the user approves:

1. **Confirm plan location** — Ensure PLAN.md and TASK*.md files are at the expected
   paths (typically `PLAN.md` in the repo root plus `tasks/TASK-*.md`)
2. **Dispatch plan review (MANDATORY)** — Per CLAUDE.md contract, every created plan
   must go through `--plan-review`. This is not optional:
   ```bash
   ~/.claude/skills/agent-transport/scripts/tmux-companion.sh \
     --plan-review "<plan_path>" <work_dir>
   ```
   When `[COMPANION] Plan review complete. Findings at: <path>` arrives, triage findings
   per tmux-handler (blocking / non-blocking / out-of-scope). Present any blocking
   findings to the user and iterate if needed before proceeding.
3. **Signal readiness** — Tell the user the plan is ready for execution. If appropriate,
   suggest: "Shall I begin with `/task-workflow`?"

## Quick Reference

| Phase | Primary Agent's Job | Companion's Job |
|-------|---------------------|-----------------|
| Gather | Read code, fetch tickets, assemble context | — |
| Dispatch | Compose prompt, send via tmux-companion.sh | Research, write PLAN.md + TASK*.md (canonical templates) |
| Verify | Check paths, scope, completeness | — |
| Present | Summarize plan, flag concerns | — |
| Iterate | Relay feedback + own concerns | Revise plan |
| Finalize | Confirm location, mandatory plan-review | Formal plan review (always) |

## Anti-Patterns

- **Writing the plan yourself** — You are the primary agent, not the companion. Dispatch the work.
- **Thin prompts** — "Make a plan for X" wastes the companion's cycles. Rich context = better plans.
- **Silent corrections** — If the plan has issues, tell the user. Don't edit the companion's output.
- **Skipping verification** — File paths in plans go stale. Always verify against the codebase.
- **Polling the companion** — The dispatch is non-blocking. Work on verification prep, not `sleep`.

## Integration with Other Workflows

- **task-workflow** executes TASK*.md files. This skill produces both PLAN.md (overall plan)
  and TASK*.md files (executable tasks), so the output feeds directly into task-workflow.
- **party-dispatch** can parallelize tasks from the plan across worker sessions.
- **bugfix-workflow** may invoke this skill when investigation reveals the fix needs planning.
