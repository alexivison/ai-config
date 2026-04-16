# Task 9 — Update Docs and Workflow Skills

**Dependencies:** Tasks 2-6 (code changes must be stable)
**Branch:** `feature/multi-agent-planning`

## Goal

Update CLAUDE.md, AGENTS.md, execution-core.md, and workflow skill prompts to use role-based language ("the companion", "the primary agent") instead of hardcoded agent names ("Codex", "Claude"). Keep persona names as defaults but make clear they're configurable.

## Scope Boundary

**In scope:**
- `claude/CLAUDE.md` — Role-based references to companion
- `codex/AGENTS.md` — Role-based references to primary
- `claude/rules/execution-core.md` — Role-based language for review governance
- `claude/skills/codex-transport/SKILL.md` — Rename concept to companion-transport
- `claude/skills/tmux-handler/SKILL.md` — Handle companion messages (not just Codex)
- `claude/skills/party-dispatch/SKILL.md` — Agent-agnostic master mode
- `claude/skills/bugfix-workflow/SKILL.md` — References to Wizard/Codex review
- `claude/skills/task-workflow/SKILL.md` — References to Wizard/Codex dispatch
- `claude/skills/plan-workflow/SKILL.md` — References to Wizard plan review (and templates/)
- `claude/skills/openspec-workflow/SKILL.md` — References to Wizard/Codex
- `claude/skills/review-external-pr/SKILL.md` — References to Wizard (and references/)
- `claude/skills/quick-fix-workflow/SKILL.md` — References to Codex review
- `claude/skills/pre-pr-verification/SKILL.md` — References to Codex evidence
- `codex/skills/tmux-handler/SKILL.md` — References to Claude/Paladin
- `claude/skills/codex-transport/tests/test-templates.sh` — Test references
- `README.md` — Update architecture description, add `.party.toml` docs

**Out of scope:**
- Code changes (already done)
- Hook changes (Task 7)
- settings.json (Task 8)

## Reference Files

### CLAUDE.md

- `claude/CLAUDE.md` — **Read the entire file (110 lines).** Key references to change:
  - Lines 1-5: Party member table — add note that roles are configurable via `.party.toml`
  - Lines 7-8: Persona description — keep but note it's the default primary persona
  - Lines 59-62: "The Wizard" section — generalize to "The Companion"
  - Lines 63-66: "Dispatch The Wizard FIRST" — generalize to companion role
  - Lines 69-73: Transport section — reference companion-transport skill (or codex-transport with note)

### AGENTS.md

- `codex/AGENTS.md` — **Read the entire file (59 lines).** Key references:
  - Lines 1-5: Party member table — same configurable note
  - Lines 41-42: "Communicate with Claude via `tmux-claude.sh`" — generalize to primary agent

### Execution core

- `claude/rules/execution-core.md` — References to "Codex review" and "Wizard" in review governance. Must use role-based language.

### Skills

- `claude/skills/codex-transport/SKILL.md` — The entire skill is Codex-specific. Keep the skill name (since it's the default companion) but add a preamble explaining this is the companion transport layer and the companion is configurable.
- `claude/skills/tmux-handler/SKILL.md` — Handles `[CODEX]` messages. Should also handle `[COMPANION]` prefix.
- `claude/skills/party-dispatch/SKILL.md` — References "The Wizard", "Codex pane", `tmux-codex.sh`. Master mode section should use role-based language.

### README

- `README.md` — Architecture table shows fixed Claude/Codex. Add `.party.toml` configuration section.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `claude/CLAUDE.md` | Modify | Role-based companion references; note configurability |
| `codex/AGENTS.md` | Modify | Role-based primary references; note configurability |
| `claude/rules/execution-core.md` | Modify | "Codex review" → "companion review" |
| `claude/skills/codex-transport/SKILL.md` | Modify | Add companion-agnostic preamble |
| `claude/skills/tmux-handler/SKILL.md` | Modify | Handle `[COMPANION]` prefix alongside `[CODEX]` |
| `claude/skills/party-dispatch/SKILL.md` | Modify | Role-based language for master mode |
| `README.md` | Modify | Add `.party.toml` config section, update architecture table |

## Requirements

### CLAUDE.md Changes

The party member table keeps the default personas but notes configurability:

```markdown
| Member | Default Agent | Role |
|--------|--------------|------|
| **The User** | — | Commander and final authority |
| **Primary** | Claude Code (Warforged Paladin) | Implementation, testing, orchestration |
| **Companion** | Codex CLI (High Elf Wizard) | Deep reasoning, analysis, review |

> Agent assignments are configurable via `.party.toml`. The above are defaults.
```

"The Wizard" section becomes "The Companion":

```markdown
## The Companion

Communicate via the companion transport skill. Dispatch the companion FIRST,
then launch sub-agents — keep working in parallel while the companion thinks.
`[COMPANION]` messages are from the companion — handle per `tmux-handler` skill.
```

### AGENTS.md Changes

Similar role-based language. "Communicate with Claude via `tmux-claude.sh`" becomes:

```markdown
- Communicate with the primary agent via the transport script.
- File-based handoff is how agents exchange structured data.
```

### execution-core.md Changes

"Codex review" → "companion review". "Wizard approval" → "companion approval". Keep the review governance gates but make them companion-agnostic.

### README.md Additions

Add a "Configuration" section:

```markdown
## Configuration

Create a `.party.toml` in your repo root to customize agent assignments:

\```toml
# Use Codex as primary, Claude as companion
[agents.codex]
cli = "codex"

[agents.claude]
cli = "claude"

[roles]
  [roles.primary]
  agent = "codex"

  [roles.companion]
  agent = "claude"
  window = 0
\```

Without a `.party.toml`, the default configuration is used:
Claude as primary, Codex as companion.
```

## Acceptance Criteria

- [x] CLAUDE.md uses role-based language for companion references
- [x] AGENTS.md uses role-based language for primary references
- [x] execution-core.md says "companion review" not "Codex review"
- [x] Workflow skills reference roles, not specific agent names
- [x] README.md documents `.party.toml` configuration
- [x] Default persona names (Paladin, Wizard) preserved as defaults
