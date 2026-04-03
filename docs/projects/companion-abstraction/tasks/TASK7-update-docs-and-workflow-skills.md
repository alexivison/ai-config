# Task 7 — Update Docs and Workflow Skills

**Dependencies:** Task 2, Task 3, Task 4

## Goal

Update all human-readable docs and workflow skill prompts to use role-based language. "Codex" becomes the default companion persona ("The Wizard"), and all plumbing references use generic companion terminology. Natural language like "ask the Wizard" continues to work.

## Scope Boundary

**In scope:**
- `claude/CLAUDE.md` — replace plumbing references (`tmux-codex.sh` → `tmux-companion.sh`, "Codex review" → "companion review") while keeping persona flavor ("The Wizard")
- `claude/rules/execution-core.md` — replace `codex` in sequence descriptions with `companion` (e.g., "critics → companion → pre-pr-verification")
- Workflow skills: `task-workflow`, `bugfix-workflow`, `plan-workflow` — update transport invocations and companion references
- `codex/AGENTS.md` — add note that Codex is one companion adapter; its role conventions apply to any analyzer companion
- `claude/skills/companion-transport/SKILL.md` — final pass to ensure all examples use `--to <name>` syntax

**Out of scope:**
- Changing execution-core logic or sequence (just wording)
- Changing sub-agent prompts (critic, minimizer, scribe, sentinel — they don't reference Codex)
- Adding OpenSpec-specific language
- `quick-fix-workflow` (already skips companion review, no Codex references in its plumbing)

**Design References:** N/A (non-UI task)

**Note:** If `source-agnostic-workflow` Task 3 has already landed, coordinate with its CLAUDE.md and execution-core changes to avoid conflicts.

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/CLAUDE.md` | Modify — role-based plumbing language |
| `claude/rules/execution-core.md` | Modify — generic companion in sequence |
| `claude/skills/task-workflow/SKILL.md` | Modify — companion transport references |
| `claude/skills/bugfix-workflow/SKILL.md` | Modify — companion transport references |
| `claude/skills/plan-workflow/SKILL.md` | Modify — companion transport references |
| `claude/skills/companion-transport/SKILL.md` | Modify — final consistency pass |
| `codex/AGENTS.md` | Modify — note companion adapter context |

## Requirements

**Functionality:**
- CLAUDE.md persona section: Keep "The Wizard" as the default companion persona. Add a mapping block:
  ```
  ## Your Companions
  - **The Wizard** (analyzer) — code review, planning, investigation
    Default CLI: Codex. Configured via `.party.toml`.
  Invoke via `/companion-transport --to wizard`.
  ```
- CLAUDE.md plumbing rules: Replace `tmux-codex.sh --review` → `tmux-companion.sh --to wizard --review` (or just `--review` when default is obvious). Replace "Codex review" → "companion review" in gate descriptions.
- execution-core.md: In the canonical sequence, replace `codex` with `companion`. In the tiered table, replace "codex" evidence with "companion". Keep the non-negotiable rules (no iteration cap, VERDICT: APPROVED required) — they apply to any companion.
- Workflow skills: Replace `codex-transport` invocations with `companion-transport`. Replace "dispatch to Codex" → "dispatch to companion" or "dispatch to The Wizard".
- AGENTS.md: Add a brief note at the top explaining that Codex operates as a companion adapter within the party harness, and its review conventions (TOON, verdicts) are the standard all companions follow.

**Key gotchas:**
- "The Wizard" is a persona Claude understands from CLAUDE.md context. It should NOT be removed — it's how the user talks to Claude about the companion. The persona maps to a companion name in the registry.
- Don't over-genericize the prose. "Ask the Wizard to review this" is better UX than "ask the companion with the analyzer role to review this." Keep the flavor, genericize the plumbing.
- Sub-agents (critic, minimizer, scribe, sentinel) don't reference Codex — they reference "scope", "findings", "verdict". No changes needed there.

## Tests

- CLAUDE.md contains no `tmux-codex.sh` references (only `tmux-companion.sh`)
- CLAUDE.md still contains "The Wizard" as persona
- execution-core.md canonical sequence uses "companion" not "codex"
- Workflow SKILL.md files reference `/companion-transport` not `/codex-transport`
- AGENTS.md mentions companion adapter role

## Acceptance Criteria

- [ ] CLAUDE.md uses `companion-transport` for all plumbing references
- [ ] CLAUDE.md preserves "The Wizard" persona for natural language interaction
- [ ] execution-core.md sequence and evidence references are companion-generic
- [ ] All workflow skills dispatch via `companion-transport`, not `codex-transport`
- [ ] AGENTS.md contextualizes Codex as a companion adapter
- [ ] No sub-agent files changed (they're already generic)
