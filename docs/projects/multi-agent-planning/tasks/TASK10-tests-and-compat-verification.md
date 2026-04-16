# Task 10 — Tests and Backward Compatibility Verification

**Dependencies:** All previous tasks
**Branch:** `feature/multi-agent-planning`

## Goal

Extend the test suite for multi-agent scenarios, verify zero-config backward compatibility (no `.party.toml` produces identical behavior to today), and ensure manifest migration works correctly. This is the final verification gate.

## Scope Boundary

**In scope:**
- New integration tests for multi-agent scenarios
- Verify existing tests all pass
- Manifest migration tests (old format → new format)
- Zero-config parity verification
- Hook test updates for renamed hooks
- Shell transport compatibility verification for the role-tag migration

**Out of scope:**
- Code changes (all previous tasks handle implementation)

## Reference Files

### Existing test files

- `tools/party-cli/cmd/commands_test.go` — CLI command tests
- `tools/party-cli/cmd/lifecycle_test.go` — Session lifecycle tests
- `tools/party-cli/cmd/messaging_test.go` — Messaging tests
- `tools/party-cli/internal/session/session_test.go` — Session test suite (580+ lines, the largest test file)
- `tools/party-cli/internal/session/start_test.go` — Start-specific tests
- `tools/party-cli/internal/state/state_test.go` — Manifest/store tests
- `tools/party-cli/internal/tmux/lifecycle_test.go` — tmux lifecycle tests
- `tools/party-cli/internal/tmux/tmux_test.go` — tmux client tests
- `tools/party-cli/internal/tui/model_test.go` — TUI model tests
- `tools/party-cli/internal/tui/tracker_test.go` — Tracker tests
- `tools/party-cli/internal/tui/sidebar_test.go` — Sidebar tests
- `tools/party-cli/internal/tui/pane_test.go` — Pane tests
- `tools/party-cli/internal/tui/tracker_actions_test.go` — Tracker action tests
- `tools/party-cli/internal/message/message_test.go` — Message test suite
- `tools/party-cli/internal/picker/picker_test.go` — Picker tests
- `claude/hooks/tests/` — Shell hook tests

### Test infrastructure

- `tools/party-cli/internal/session/testhelper_test.go` — Test helpers for session tests
- `tools/party-cli/cmd/root_test.go` — Root command test with `WithDeps()` injection

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/internal/agent/agent_test.go` | Verify | Ensure Task 1 tests are comprehensive |
| `tools/party-cli/internal/session/session_test.go` | Modify | Add multi-agent session tests |
| `tools/party-cli/internal/state/state_test.go` | Modify | Add manifest migration tests |
| `tools/party-cli/internal/tui/tracker_test.go` | Modify | Update for unified tracker |
| `tools/party-cli/internal/tui/model_test.go` | Modify | Remove ViewWorker/ViewMaster tests, add unified view tests |
| `tools/party-cli/internal/message/message_test.go` | Modify | Update role strings in test fixtures |
| `claude/hooks/tests/test-codex-gate.sh` | Modify | Point to new hook, test companion-generic behavior |
| `claude/hooks/tests/test-codex-trace.sh` | Modify | Point to new hook, test companion-generic behavior |
| `tests/test-transport-role-routing.sh` | Create | Smoke-test `party_role_pane_target`, `tmux-codex.sh`, and `tmux-claude.sh` against new role tags |
| `tests/run-tests.sh` | Modify | Include new test files |

## Requirements

### Zero-Config Parity Tests

Critical: with no `.party.toml`, the system must produce **identical** behavior to the pre-refactor codebase.

Test cases:
1. `Start()` with default registry → `agentCmds[RolePrimary]` produces the exact same shell command as the old `buildClaudeCmd()` with the same inputs
2. `Start()` with default registry → `agentCmds[RoleCompanion]` produces the exact same shell command as the old `buildCodexCmd()` with the same inputs
3. Classic layout with defaults → 3 panes created with the same commands and proportions
4. Sidebar layout with defaults → 2 windows, same structure
5. Master layout with defaults → tracker + primary + shell, same as before
6. Continue with old manifest → resume IDs correctly extracted and passed

### Multi-Agent Scenario Tests

1. Codex as primary: registry with `roles.primary.agent = "codex"` → primary command uses Codex CLI flags
2. Claude as companion: registry with `roles.companion.agent = "claude"` → companion command uses Claude CLI flags
3. No companion: registry with no companion role → single-agent session starts successfully
4. Start with missing companion CLI → warning logged, session continues primary-only
5. Start with missing primary CLI → error returned (session cannot start)

### Manifest Migration Tests

1. Old manifest with `claude_bin`, `codex_bin`, `claude_session_id` (extra), `codex_thread_id` (extra) → `UnmarshalJSON` produces `Agents[]` with two entries
2. Old manifest with only `claude_bin` (no codex) → `Agents[]` has one entry
3. New manifest with `Agents[]` → round-trips correctly
4. Mixed manifest (both old fields and `Agents[]`) → `Agents[]` takes precedence

### Unified Tracker Tests

1. Tracker with master + workers → hierarchy displayed correctly
2. Tracker with standalone sessions → flat list
3. Tracker with mixed (master + standalone) → correct grouping
4. Current session highlighted in detail section
5. Companion status for current session → shown inline
6. Evidence for current session → shown inline

### Hook Tests

1. `companion-gate.sh` with no companion configured → allows all commands
2. `companion-gate.sh` with companion configured → blocks `--approve`
3. `companion-trace.sh` records evidence with companion name
4. `primary-state.sh` still writes `claude-state.json`
5. Symlinks at old paths work

### Shell Transport Compatibility Tests

1. `party_role_pane_target primary` resolves a pane tagged `primary`
2. `party_role_pane_target companion` resolves a pane tagged `companion`
3. `party_role_pane_target primary` still falls back to a pane tagged `claude`
4. `party_role_pane_target companion` still falls back to a pane tagged `codex`
5. `tmux-claude.sh` delivers to a pane tagged `primary`
6. `tmux-codex.sh` delivers to a pane tagged `companion`

## Verification Checklist

Run these commands to verify:

```bash
# Go tests
cd tools/party-cli && go test ./...

# Hook tests
bash claude/hooks/tests/run-all.sh

# Shell transport smoke tests
bash tests/test-transport-role-routing.sh

# Specific backward compat verification
# (these are manual checks, not automated)
# 1. Build party-cli
cd tools/party-cli && go build -buildvcs=false -o /tmp/party-cli .

# 2. Verify agent query defaults
/tmp/party-cli agent query names      # should output "claude\ncodex"
/tmp/party-cli agent query roles      # should output "primary\ncompanion"
/tmp/party-cli agent query primary-name  # should output "claude"

# 3. Verify surfaced session flags
/tmp/party-cli start --help | rg -- '--primary|--companion|--no-companion|--resume-agent'

# Compatibility aliases remain hidden by design; `go test ./...` covers them.
```

## Acceptance Criteria

- [x] `go test ./...` passes with zero failures
- [x] All hook tests pass
- [x] Zero-config produces identical commands to pre-refactor code
- [x] Manifest migration tests cover all old→new scenarios
- [x] Multi-agent scenario tests cover Codex-as-primary, no-companion, missing-CLI cases
- [x] Unified tracker tests cover hierarchy display
- [x] Shell transport compatibility is covered for both new and legacy role tags
- [x] No regressions in existing functionality
