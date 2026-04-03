# Task 6 — Update Hook Tests

**Dependencies:** Task 3

## Goal

Update all hook test files to exercise the renamed, companion-generic hooks. Ensure backward compatibility and parameterization work correctly.

## Scope Boundary

**In scope:**
- Rename and update `test-codex-gate.sh` → `test-companion-gate.sh`
- Rename and update `test-codex-trace.sh` → `test-companion-trace.sh`
- Update `test-pr-gate.sh` to test config-driven evidence requirements
- Add test cases for multi-companion scenarios where applicable

**Out of scope:**
- Changing hook logic (already done in Task 3)
- Transport or session tests
- Workflow tests

**Design References:** N/A (non-UI task)

## Files to Create/Modify

| File | Action |
|------|--------|
| `claude/hooks/tests/test-codex-gate.sh` | Rename to `test-companion-gate.sh` + update |
| `claude/hooks/tests/test-codex-trace.sh` | Rename to `test-companion-trace.sh` + update |
| `claude/hooks/tests/test-pr-gate.sh` | Modify — add config-driven evidence tests |

## Requirements

**Functionality:**
- `test-companion-gate.sh`: Test that `--approve` is blocked for Codex adapter path AND any hypothetical adapter path. Test that all other modes pass.
- `test-companion-trace.sh`: Test that evidence is recorded with companion name (e.g., `"wizard"`) as the type, not hardcoded `"codex"`. Test sentinel detection for generalized sentinels.
- `test-pr-gate.sh`: Add cases for: (a) no `.party.toml` → uses default evidence list with companion name; (b) `.party.toml` with custom `[evidence].required` → uses that list; (c) companion name in evidence matches active companion.

**Key gotchas:**
- Tests must set up mock `.party.toml` files in temp dirs for config-driven tests
- Existing test assertions about `"codex"` evidence type change to companion name
- Test runner location/framework should match existing test conventions in the repo

## Tests

- All renamed test files pass
- Gate tests cover both Codex adapter and generic adapter paths
- Trace tests verify evidence type is companion name
- PR gate tests cover with/without `.party.toml`

## Acceptance Criteria

- [ ] All hook tests renamed and updated
- [ ] Gate tests cover any companion adapter, not just Codex
- [ ] Trace tests verify companion-name-based evidence
- [ ] PR gate tests cover config-driven and default evidence requirements
- [ ] All tests pass
