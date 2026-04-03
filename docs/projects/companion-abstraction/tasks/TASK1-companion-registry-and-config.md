# Task 1 — Companion Registry, Adapter Interface, and Config

**Dependencies:** none

## Goal

Create the foundation layer: a shell-based companion registry, the adapter interface contract, a `.party.toml` parser, and the first adapter (Codex) that wraps existing behavior. Nothing uses this yet — later tasks wire it in.

## Scope Boundary

**In scope:**
- `shared/companions/registry.sh` — shell library with lookup functions
- `shared/companions/adapters/codex.sh` — Codex adapter implementing the interface
- `shared/companions/adapters/interface.md` — adapter contract documentation
- `.party.toml` parser (shell function reading TOML config, with fallback defaults)
- Default config equivalent to today's behavior (Codex as wizard)

**Out of scope:**
- Renaming any existing files (Task 2, 3, 4)
- Modifying transport, hooks, or session scripts (Task 2, 3, 4)
- install.sh changes (Task 5)
- Tests for hooks (Task 6)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `shared/companions/registry.sh` | Create |
| `shared/companions/adapters/codex.sh` | Create |
| `shared/companions/adapters/interface.md` | Create |

## Requirements

**Functionality:**
- `registry.sh` exports functions: `companion_list`, `companion_cli`, `companion_role`, `companion_capabilities`, `companion_has_capability`, `companion_adapter`, `companion_for_capability`, `companion_pane_window`
- Registry reads `.party.toml` from CWD or git root; falls back to hardcoded defaults if no file found
- TOML parsing uses `tomlq`/`yq` if available; falls back to `grep`/`sed` for the flat structure used in `.party.toml`
- Codex adapter implements `adapter_start`, `adapter_send`, `adapter_receive`, `adapter_health`
- Codex adapter logic extracted from existing `tmux-codex.sh` — same modes, same status files, same TOON handling
- Adapter writes status to `companion-status-<name>.json` (not `codex-status.json`)

**Key gotchas:**
- Registry must be sourceable (no side effects on source, only function definitions)
- Adapter scripts must also be sourceable (functions, not executable scripts)
- Default companion name is `wizard` (not `codex`) — the persona, not the tool

## Tests

- Source `registry.sh` with no `.party.toml` → `companion_list` returns `"wizard"`, `companion_cli "wizard"` returns `"codex"`
- Source `registry.sh` with a `.party.toml` defining two companions → both appear in `companion_list`
- `companion_for_capability "review"` returns the correct companion
- `companion_adapter "wizard"` returns path to `codex.sh`

## Acceptance Criteria

- [ ] `registry.sh` is sourceable and exports all listed functions
- [ ] Default behavior (no `.party.toml`) returns Codex as wizard
- [ ] `.party.toml` overrides are respected when file exists
- [ ] Codex adapter implements all four interface functions
- [ ] Adapter interface is documented in `interface.md`
- [ ] No existing files are modified (pure addition)
