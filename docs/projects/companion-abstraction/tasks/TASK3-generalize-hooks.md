# Task 3 — Generalize Hooks

**Dependencies:** Task 1

## Goal

Rename and parameterize the three Codex-specific hooks (`codex-gate.sh`, `wizard-guard.sh`, `codex-trace.sh`) to be companion-generic. Update `pr-gate.sh` to read required evidence types from `.party.toml` instead of a hardcoded string.

## Scope Boundary

**In scope:**
- Rename `codex-gate.sh` → `companion-gate.sh` — block `--approve` for ANY companion adapter script
- Rename `wizard-guard.sh` → `companion-guard.sh` — block direct tmux to ANY companion pane
- Rename `codex-trace.sh` → `companion-trace.sh` — record evidence with companion name as type
- Update `pr-gate.sh` — read `REQUIRED` evidence list from `.party.toml` (fall back to current hardcoded default)
- Keep old file names as thin wrappers (one-liner sourcing new file) for transition period

**Out of scope:**
- Transport renames (Task 2)
- Session/manifest changes (Task 4)
- settings.json path updates (Task 5)
- Hook test updates (Task 6)

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/codex-gate.sh` | Rename to `companion-gate.sh` + leave redirect stub |
| `claude/hooks/wizard-guard.sh` | Rename to `companion-guard.sh` + leave redirect stub |
| `claude/hooks/codex-trace.sh` | Rename to `companion-trace.sh` + leave redirect stub |
| `claude/hooks/pr-gate.sh` | Modify — config-driven evidence requirements |

## Requirements

**Functionality:**
- `companion-gate.sh`: Parse command for ANY adapter script path (not just `tmux-codex.sh`); block if `--approve` detected. The script checks if the invoked command matches any known adapter path from the registry.
- `companion-guard.sh`: Block direct tmux commands targeting any companion pane (resolve companion names/roles from registry, not hardcoded "codex" or "Wizard" regex). Still fail-open on parse errors.
- `companion-trace.sh`: After a companion adapter command succeeds, record evidence using the companion name (e.g., `append_evidence "$session_id" "wizard" "APPROVED" "$cwd"`). Parse TOON findings file and record via `record_finding_raised` / `record_findings_summary` with companion name.
- `pr-gate.sh`: Read `[evidence].required` from `.party.toml`. If not set, use current default. Replace literal `"codex"` in the default list with active companion name(s) from registry.

**Key gotchas:**
- The redirect stubs (`codex-gate.sh` → `companion-gate.sh`) ensure hooks work during the transition before `settings.json` is updated in Task 5
- `companion-trace.sh` sentinel strings (`CODEX_REVIEW_RAN`, `CODEX APPROVED`) may need to become companion-generic or the Codex adapter should output standardized sentinels
- Evidence type changing from `"codex"` to companion name means existing evidence files become stale — this is fine since evidence is per-session and session-scoped

## Tests

- `companion-gate.sh` blocks `--approve` on any adapter script path
- `companion-gate.sh` allows `--review`, `--prompt`, etc.
- `companion-guard.sh` blocks `tmux send-keys` targeting any companion pane
- `companion-trace.sh` records evidence with correct companion name
- `pr-gate.sh` with `.party.toml` uses custom evidence requirements
- `pr-gate.sh` without `.party.toml` uses default (current behavior with companion name substituted)

## Acceptance Criteria

- [ ] All three hooks renamed with companion-generic logic
- [ ] Redirect stubs exist at old paths for transition
- [ ] `companion-gate.sh` blocks `--approve` for any companion, not just Codex
- [ ] `companion-guard.sh` resolves companion names from registry
- [ ] `companion-trace.sh` records evidence using companion name as type
- [ ] `pr-gate.sh` reads evidence requirements from `.party.toml`
- [ ] `pr-gate.sh` falls back to current defaults when no config exists
