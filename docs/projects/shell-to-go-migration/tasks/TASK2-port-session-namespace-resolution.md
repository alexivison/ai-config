# Task 2 — Port Session Namespace Resolution

**Dependencies:** Task 1 | **Issue:** TBD

---

## Goal

Unify the party-session and Claude-UUID seam in Go so the tracker, sidebar, and later hook helpers all resolve evidence and metrics through one authoritative bridge instead of a manifest-only guess.

## Scope Boundary (REQUIRED)

**In scope:**
- Port `discover_session_id()` into Go with the same priority order: party state, worktree override, evidence-file scan
- Add `party-cli session resolve-claude-id`
- Extend the Go tmux/state stack as needed to query persisted `claude_session_id` and tmux environment state
- Refactor tracker/sidebar evidence lookup to use the shared resolver rather than `manifest.ExtraString("claude_session_id")` plus raw fallback

**Out of scope (handled by other tasks):**
- Evidence writes or checks themselves
- Hook verdict parsing
- Metrics, oscillation, or gate logic

**Cross-task consistency check:**
- Task 5 through Task 7 must consume the same resolver output whenever they need a Claude UUID from a party session context
- After this task there must be one place that decides when falling back to the tmux session name is allowed

## Reference

Files to study before implementing:

- `claude/hooks/lib/session-id-helper.sh:18` — discovery order and CLI behavior
- `claude/hooks/tests/test-session-id-helper.sh:40` — override and fallback fixtures
- `claude/hooks/register-agent-id.sh:31` — tmux env persistence of `CLAUDE_SESSION_ID`
- `claude/hooks/register-agent-id.sh:33` — manifest persistence of `claude_session_id`
- `tools/party-cli/internal/tui/model.go:409` — current auto-resolver seam
- `tools/party-cli/internal/tui/tracker_actions.go:153` — current manifest-only evidence ID fallback
- `tools/party-cli/internal/tmux/query.go:40` — existing session-name query helper

## Design References (REQUIRED for UI/component tasks)

N/A (non-UI task)

## Data Transformation Checklist (REQUIRED for shape changes)

- [ ] Proto definition (N/A)
- [ ] Proto -> Domain converter (N/A)
- [ ] Domain model struct for resolver results and provenance
- [ ] Params struct(s) for Cobra session-resolution command
- [ ] Params conversion functions from env/state/evidence artifacts to resolver output
- [ ] Any adapters between TUI session discovery and Claude UUID lookup

## Files to Create/Modify

| File | Action |
|------|--------|
| `tools/party-cli/internal/session/resolve_claude.go` | Create |
| `tools/party-cli/internal/session/resolve_claude_test.go` | Create |
| `tools/party-cli/internal/tmux/query.go` | Modify |
| `tools/party-cli/cmd/session_resolve.go` | Create |
| `tools/party-cli/cmd/root.go` | Modify |
| `tools/party-cli/internal/tui/model.go` | Modify |
| `tools/party-cli/internal/tui/tracker_actions.go` | Modify |

## Requirements

**Functionality:**
- Preserve the current priority order from `claude/hooks/lib/session-id-helper.sh:21-98`
- Preserve the “no discovery when evidence exists but no worktree override exists” behavior from `claude/hooks/tests/test-session-id-helper.sh:85-96`
- Allow tracker/sidebar flows to resolve evidence and metrics from a party session name without manual manifest inspection
- Return a non-zero exit from the CLI command when no mapping can be found

**Key gotchas:**
- The brief overstates current hook usage of `session-id-helper.sh`; the real value is the namespace bridge for TUI and manual flows, so do not hard-wire the resolver to only hook inputs
- File mtimes matter when multiple override or evidence candidates match the same repo

## Tests

Test cases:
- Party-state manifest resolution
- Worktree override discovery from repo root and nested subdirectories
- Evidence-scan fallback only when a matching worktree override exists
- Tracker/sidebar stage lookup when `claude_session_id` exists and when it does not

Verification commands:
- `go test ./internal/session ./internal/tmux ./internal/tui ./cmd`
- `bash claude/hooks/tests/test-session-id-helper.sh`

## Acceptance Criteria

- [ ] One Go resolver owns party-session to Claude-UUID mapping
- [ ] `party-cli session resolve-claude-id` matches the shell helper’s success and failure behavior
- [ ] Tracker/sidebar evidence lookup uses the shared resolver instead of manifest-only fallback logic
- [ ] Go tests cover the shell helper’s parity cases
