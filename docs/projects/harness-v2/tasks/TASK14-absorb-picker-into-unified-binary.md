# Task 14 — Absorb Picker Into Unified Binary

**Dependencies:** Task 8, Task 10 | **Issue:** TBD

---

## Goal

Replace the Bash picker pipeline with `party-cli picker`, using the shared discovery and lifecycle services. This removes another shell-only surface and prepares the final wrapper cutover.

## Scope Boundary (REQUIRED)

**In scope:**
- Add `party-cli picker`
- Reproduce current selection and preview behavior through shared services
- Choose the simplest implementation that preserves usability: embedded list first, `fzf` fallback only where it still buys value

**Out of scope (handled by other tasks):**
- Final shell-wrapper retirement
- Worker sidebar or master tracker rendering
- Messaging transport

**Cross-task consistency check:**
- Picker data must come from the same visible-session discovery as `party-cli list`
- Picker actions must call the same lifecycle services as Task 10, not separate shell flows

## Reference

Files to study before implementing:

- `session/party-picker.sh` — current picker behavior
- `session/party-preview.sh` — current preview behavior
- `tools/party-cli/internal/state/*` — discovery layer
- `tools/party-cli/internal/session/*` — lifecycle actions

## Design References (REQUIRED for UI/component tasks)

- `../diagrams/before-after.svg`
- `../diagrams/end-state-architecture.svg`

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A unless a typed file contract is introduced)
- [ ] Proto -> Domain converter (N/A unless a typed file contract is introduced)
- [ ] Domain model struct
- [ ] Params struct(s) — check ALL variants
- [ ] Params conversion functions
- [ ] Any adapters between param types

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/cmd/picker.go` | Create |
| `tools/party-cli/internal/picker/*` | Create |
| `tools/party-cli/internal/picker/*_test.go` | Create |
| `session/party-picker.sh` | Modify if wrapper delegation is added incrementally |
| `session/party-preview.sh` | Modify or retire later |

## Requirements

**Functionality:**
- Picker shows only visible sessions
- Preview content remains useful for attach/continue/delete decisions
- Picker actions call shared Go lifecycle services
- Missing `fzf` does not produce silent failure; either a built-in path works or the command errors clearly

**Key gotchas:**
- Preserve the current preview signal-to-noise ratio; a worse picker is not simplification
- All sessions are user-facing under the hidden-window model — no companion filtering needed

## Tests

Test cases:
- Picker row generation from session discovery
- Preview generation
- Attach/continue/delete actions from picker selection
- `fzf`-missing fallback or error behavior

## Acceptance Criteria

- [ ] `party-cli picker` exists and is backed by shared services
- [ ] Picker shows all sessions (no companion filtering needed) and preserves preview usefulness
- [ ] Selection actions call Go lifecycle services
- [ ] Picker tests pass
