---
name: orchestrate-plan
description: >-
  Orchestrate Codex to plan a feature. Claude dispatches Codex for deep research
  and plan creation, relays user feedback, and reviews/double-checks the output.
  Use when the user asks to plan a feature, design a system, or break work into
  tasks. Claude does NOT create plans directly — Codex does the planning, Claude
  orchestrates and quality-checks.
user-invocable: true
---

# Orchestrate Plan — Direct the Wizard's Planning

You are the orchestrator. Codex is the planner. Your job is to dispatch Codex,
relay user feedback, and review what Codex produces. **Do NOT create SPEC.md,
DESIGN.md, PLAN.md, or TASK*.md yourself.**

## When This Skill Applies

- User asks to plan a feature, design a system, or break work into tasks
- User wants to iterate on an existing plan with feedback
- User wants a plan reviewed or double-checked

## Phase 1: Gather Context

Before dispatching Codex, collect what the Wizard needs:

1. **Clarify requirements** — Ask the user for anything ambiguous. Codex works
   best with clear inputs. Don't send Codex on a quest with vague directions.
2. **Locate existing artifacts** — Check for PRDs, specs, issues, or prior
   plans. Gather file paths and links.
3. **Identify the target repo and working directory** — Codex needs `work_dir`.
4. **Determine mode** — Does Codex need to Discover, Design, Plan, or all three?
   Match to the user's request:
   - "I have an idea but no spec" → Discover + Design + Plan
   - "Here's a spec, plan it" → Design + Plan (or just Plan if design is clear)
   - "Break this design into tasks" → Plan only

## Phase 2: Dispatch Codex

Compose a prompt and send it to Codex via transport:

```bash
cat > /tmp/codex-plan-prompt.md << 'PROMPT_EOF'
## Planning Request

**Mode:** [Discover | Design | Plan | Full (all three)]

### Context
[Summarize the feature, link to PRD/spec/issue, and any constraints the user mentioned]

### Requirements
[Bullet list of what the user wants — be specific]

### Existing Artifacts
[List file paths to any existing specs, designs, or prior plans]

### User Guidance
[Any preferences, constraints, or direction from the user]

Invoke your `/planning` skill. Follow its modes and readiness gate.
PROMPT_EOF

~/.claude/skills/codex-transport/scripts/tmux-codex.sh --prompt "$(cat /tmp/codex-plan-prompt.md)" <work_dir>
```

**This is non-blocking.** Continue to Phase 3 while Codex works.

## Phase 3: While Codex Works

Use this time productively:

- Answer any `[CODEX] Question:` messages — investigate the codebase and write
  responses to the path Codex provides (per `tmux-handler` skill)
- Do NOT start implementation. Planning must finish first.
- Inform the user that Codex is working and what to expect

## Phase 4: Review Codex Output

When Codex notifies completion (typically `[CODEX] Task complete. Response at: <path>`
or creates a draft PR with plan artifacts):

### 4a. Read Everything

Read ALL plan artifacts Codex produced:
- SPEC.md — Are requirements measurable and complete?
- DESIGN.md — Are patterns referenced with `file:line`? Data transformation
  points mapped? Integration points identified?
- PLAN.md — Are tasks small (~200 LOC)? Dependencies clear? Verification
  commands listed?
- TASK*.md — Do scope boundaries exist? Are acceptance criteria machine-verifiable?

### 4b. Run the Planning Checks

Evaluate against the same 7-point checklist Codex uses:

| # | Check | Status |
|---|-------|--------|
| 1 | Existing standards referenced with concrete `file:line` paths | |
| 2 | Data transformation points mapped for schema/field changes | |
| 3 | Tasks have explicit scope boundaries (in-scope / out-of-scope) | |
| 4 | Dependencies and verification commands listed per task | |
| 5 | Requirements reconciled against source inputs; mismatches documented | |
| 6 | Whole-architecture coherence evaluated across full task sequence | |
| 7 | UI/component tasks include design references | |

### 4c. Cross-Check Against User Requirements

- Compare what the user asked for against what the plan delivers
- Flag any requirements that are missing, misinterpreted, or over-scoped
- Flag any scope creep — things Codex added that the user didn't ask for

### 4d. Verify Codebase Assumptions

Spot-check key claims Codex makes about the codebase:
- Pick 2-3 `file:line` references and verify they exist and say what Codex claims
- Verify integration points actually exist at the referenced locations
- Check that named patterns/abstractions are real, not hallucinated

### 4e. Report to User

Present a concise summary:
1. **What Codex planned** — one-paragraph overview
2. **Planning checks** — the 7-point table with PASS/FAIL
3. **Issues found** — blocking problems, if any
4. **Recommendations** — suggested changes before approving

## Phase 5: Iterate on Feedback

When the user has comments on the plan:

1. **Translate feedback into specific instructions** — Don't just forward raw
   comments. Interpret what the user means and compose clear, actionable
   direction for Codex.
2. **Dispatch Codex with revision prompt:**
   ```bash
   cat > /tmp/codex-revision-prompt.md << 'PROMPT_EOF'
   ## Plan Revision Request

   ### Changes Requested
   [Specific, actionable items — not vague "make it better"]

   ### Files to Update
   [List which plan artifacts need changes]

   ### Context
   [Why the user wants these changes — helps Codex make better decisions]

   Update the plan artifacts accordingly. Keep existing good work intact.
   PROMPT_EOF

   ~/.claude/skills/codex-transport/scripts/tmux-codex.sh --prompt "$(cat /tmp/codex-revision-prompt.md)" <work_dir>
   ```
3. **Review again** — Repeat Phase 4 on the updated artifacts
4. **Max 3 revision rounds** — If the plan still doesn't meet requirements
   after 3 rounds, escalate to the user with a summary of what's stuck

## Phase 6: Plan Approval

When the plan passes all checks and the user is satisfied:

1. Confirm with the user that the plan is approved
2. If Codex created a draft PR, note its URL for the user
3. The plan is now ready for execution via `/task-workflow`

## Anti-Patterns

- **Do NOT write plan artifacts yourself.** Codex is the planner. You orchestrate.
- **Do NOT rubber-stamp.** Always run the planning checks. Always spot-check
  codebase references. Codex is good but not infallible.
- **Do NOT forward user feedback verbatim.** Translate it into clear instructions.
  You are a translator between human intent and Wizard-speak.
- **Do NOT block on Codex.** The dispatch is non-blocking. Stay responsive to
  the user and answer Codex's questions promptly.
- **Do NOT start implementation before the plan is approved.** Planning and
  implementation are separate phases.
