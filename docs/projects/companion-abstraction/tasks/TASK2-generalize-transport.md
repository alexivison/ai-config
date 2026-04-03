# Task 2 — Generalize Transport Layer

**Dependencies:** Task 1

## Goal

Replace the Codex-specific transport skill with a companion-generic router. The skill `codex-transport` becomes `companion-transport`, and `tmux-codex.sh` becomes `tmux-companion.sh` which dispatches to the appropriate adapter via the registry.

## Scope Boundary

**In scope:**
- Rename `claude/skills/codex-transport/` → `claude/skills/companion-transport/`
- Rename `tmux-codex.sh` → `tmux-companion.sh` with routing logic
- Update SKILL.md to use `--to <name>` addressing and role-based language
- Update `toon-transport.sh` symlink if needed
- Update Codex-side transport (`codex/skills/claude-transport/`) to use companion naming conventions in its status file writes

**Out of scope:**
- Hook renames (Task 3)
- Session/manifest changes (Task 4)
- settings.json permission updates (Task 5)
- Workflow skill prompt updates (Task 7)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/skills/codex-transport/` | Rename to `claude/skills/companion-transport/` |
| `claude/skills/companion-transport/SKILL.md` | Modify — role-based language, `--to` flag |
| `claude/skills/companion-transport/scripts/tmux-companion.sh` | Rename + modify from `tmux-codex.sh` — add registry routing |
| `codex/skills/claude-transport/scripts/tmux-claude.sh` | Modify — write `companion-status-wizard.json` instead of `codex-status.json` |

## Requirements

**Functionality:**
- `tmux-companion.sh` accepts `--to <name>` as first argument (default: first companion with `review` capability)
- Routes to correct adapter via `companion_adapter "$name"` from registry
- All existing modes preserved: `--review`, `--plan-review`, `--prompt`, `--review-complete`, `--needs-discussion`, `--triage-override`
- `--approve` remains blocked (but blocking moves to companion-gate.sh in Task 3; here, just don't implement it in the adapter)
- Status files written as `companion-status-<name>.json` instead of `codex-status.json`
- SKILL.md updated: "Codex" → "companion", modes documented with `--to` flag

**Key gotchas:**
- `settings.json` permissions reference `tmux-codex.sh` path — Task 5 updates this, so during this task both old and new paths should work (symlink or dual permission)
- `toon-transport.sh` symlink must remain accessible from new location
- Backward compatibility: if scripts call `tmux-codex.sh` directly (hooks do), they must still work until Task 3 renames them

## Tests

- `tmux-companion.sh --to wizard --review <dir>` dispatches to Codex adapter
- `tmux-companion.sh --review <dir>` (no `--to`) defaults to first companion with review capability
- Status file created at correct path (`companion-status-wizard.json`)
- SKILL.md has no hardcoded "codex" references in plumbing instructions

## Acceptance Criteria

- [ ] `codex-transport` skill renamed to `companion-transport`
- [ ] `tmux-companion.sh` routes via registry, not hardcoded
- [ ] All 6 modes work through the adapter layer
- [ ] `--to <name>` addressing works
- [ ] Default routing (no `--to`) resolves via capability
- [ ] Status file naming follows `companion-status-<name>.json` pattern
- [ ] `toon-transport.sh` accessible from new skill location
