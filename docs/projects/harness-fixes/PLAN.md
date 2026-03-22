# Harness Fixes — Post-V2 Improvement Plan

> **Goal:** Address remaining research report recommendations, clean up debt introduced by the harness-v2 migration, improve Go test coverage, and retire dead artifacts.
>
> **Baseline:** Harness V2 (PRs #58-#74, Tasks 1-15) is complete. `party-cli` is the primary implementation surface. Bash wrappers are thin delegates. Hooks and evidence system are stable post-phase-simplification.
>
> **Source:** [Workflow research](../harness-v2/research/research-workflow.md) | [Infra research](../harness-v2/research/research-infra.md) | [PR gate investigation](../harness-v2/research/pr-gate-investigation.md)

---

## 1. Audit: Research Recommendations vs Harness-V2 Outcomes

### Workflow Research (research-workflow.md) — 11 Recommendations

| # | Recommendation | Status | Evidence |
|---|---------------|--------|----------|
| 1 | Extract oscillation detection from agent-trace-stop.sh into lib/oscillation.sh | **DONE** (Task 3, PR #60) | `claude/hooks/lib/oscillation.sh` (105L); agent-trace-stop.sh dropped from 188L to 125L |
| 2 | Remove marker cleanup from session-cleanup.sh | **DONE** (Task 1, PR #61) | Line 15 now cleans worktree overrides, not markers |
| 3 | Add worktree-guard.sh tests | **DONE** (Task 3, PR #60) | `claude/hooks/tests/test-worktree-guard.sh` exists |
| 4 | Merge general.md into CLAUDE.md | **DONE** (Task 1, PR #61) | `claude/rules/general.md` no longer exists; "early returns" and "minimal comments" are in CLAUDE.md General Guidelines |
| 5 | Verify/remove orphaned prompt-templates.md | **OPEN** | `claude/skills/codex-transport/references/prompt-templates.md` still exists. No grep matches for `prompt-templates` in any SKILL.md or script. Orphaned. |
| 6 | Remove backward-compat 4th positional arg in tmux-codex.sh | **DONE** (Task 1, PR #61) | `--review` now uses `--scope`/`--dispute`/`--prior-findings` flags; no positional fallback remains |
| 7 | Add delivery confirmation to tmux transport | **PARTIALLY DONE** | Go `tmux.Send()` has delivery-confirmed sends (Task 6). But `party-lib.sh:tmux_send()` (still used by tmux-codex.sh) remains fire-and-forget |
| 8 | Consider branch-scoped evidence naming | **DEFERRED** | Research verdict was "session-scoped is correct"; no change made |
| 9 | Evaluate named-pipe transport for tmux-codex.sh | **DEFERRED** | Research verdict was "acceptable fragility for dev-local tool" |
| 10 | Commit or remove docs/projects/phase-simplification/ | **OPEN** | Still untracked (`?? docs/projects/phase-simplification/`) |
| 11 | Do not merge task/bugfix workflows | **RESPECTED** | Both remain separate skills |

### Infrastructure Research (research-infra.md) — 13 Recommendations

| # | Recommendation | Status | Evidence |
|---|---------------|--------|----------|
| 1 | Mandate jq with early check | **DONE** (Task 2, PR #62) | `party_state_upsert_manifest` returns error on missing jq |
| 2 | Quote `$lib_path` in tmux hooks | **DONE** (Task 2, PR #62) | |
| 3 | Add trap cleanup for temp files | **DONE** (Task 2, PR #62) | `trap "rm -f '$tmp'" RETURN` in party-lib.sh |
| 4 | Log tmux_send failures to stderr | **DONE** (Task 2, PR #62) | Return code 75 + stderr message |
| 5 | Extract shared launch logic | **SUPERSEDED** | party-cli owns all launch logic; bash duplication eliminated |
| 6 | Add exponential backoff to locking | **SUPERSEDED** | Go `flock()` in party-cli replaces mkdir locking for all lifecycle ops. `party-lib.sh:_party_lock` still uses mkdir but is only called by functions consumed solely by tmux-codex.sh |
| 7 | Add delivery confirmation to tmux_send | **PARTIALLY DONE** (same as workflow #7) | Go layer has it; bash layer does not |
| 8 | Remove legacy pane routing fallback | **DONE** (Task 2, PR #62) | `party_role_pane_target` is authoritative |
| 9 | Begin Go CLI port | **DONE** (Tasks 4-15) | `tools/party-cli/` — 5,021L source, 5,919L tests |
| 10 | Absorb picker into tracker | **DONE** (Task 14, PR #70) | `party-cli picker` replaces bash pipeline |
| 11 | Complete Go CLI to feature parity | **DONE** (Task 15, PR #74) | All lifecycle, messaging, picker, layout in Go |
| 12 | Implement structured IPC | **DEFERRED** | tmux remains the transport |
| 13 | Full sidebar TUI | **DONE** (Task 12, PR #73) | Worker sidebar with Codex status, evidence, peek popup |

### PR Gate Investigation — 3 Root Causes

| # | Root Cause | Status | Evidence |
|---|-----------|--------|----------|
| 1 | .svg not in docs-only allowlist | **DONE** | `pr-gate.sh:43` now uses implementation-file allowlist (`grep -E '\.(sh|bash|go|py|ts|...)$'`) instead of docs blocklist |
| 2 | Worktree override written empty | **MITIGATED** | Root cause was self-inflicted during debug; worktree-track tests added (Task 3) |
| 3 | Session ID unknowable for manual evidence | **OPEN** | `session-id-helper.sh` exists as a discovery helper, but the fundamental problem remains — Claude cannot directly read its own session_id |

---

## 2. New Issues Introduced by Harness-V2

### 2a. Thin Wrapper Coupling

**Problem:** `party-lib.sh` (581L) is still fully loaded by every bash wrapper and by `tmux-codex.sh`, but most of its 24 functions are only needed by `tmux-codex.sh`. The thin wrappers (`party.sh`, `party-relay.sh`, `party-picker.sh`, `party-preview.sh`) only need `party_resolve_cli_bin`, `party_attach`, and `discover_session`.

**Impact:** Loading 581 lines for 3 functions is wasteful. More importantly, `party-lib.sh` still contains manifest CRUD (`party_state_upsert_manifest`, `party_state_set_field`, etc.) and tmux operations (`tmux_send`, `tmux_pane_idle`) that are now duplicated in Go — dual maintenance surface.

**Functions used ONLY by tmux-codex.sh path:**
- `discover_session`, `party_is_master`, `party_codex_pane_target`, `party_role_pane_target`, `tmux_pane_idle`, `tmux_send`, `write_codex_status`, `party_layout_mode`

**Functions used ONLY by wrappers (for delegation):**
- `party_resolve_cli_bin`, `party_attach`

**Functions used by no external caller (dead or internal-only):**
- `party_state_upsert_manifest`, `party_state_set_field`, `party_state_get_field`, `party_state_add_worker`, `party_state_remove_worker`, `party_state_get_workers`, `ensure_party_state_dir`, `_party_lock`, `_party_unlock`, `party_resolve_cli_cmd`, `party_state_root`, `party_state_file`, `party_runtime_dir`, `party_role_pane_target_with_fallback`

Only `register-agent-id.sh` and `party-master-jump.sh` also source party-lib.sh — the former uses `party_state_set_field`, the latter uses `party_state_file`.

### 2b. Old party-tracker Not Retired

**Problem:** `tools/party-tracker/` (660L Go, 3 files) still exists alongside `tools/party-cli/internal/tui/tracker.go` (393L) which supersedes it. The old binary is a compiled artifact (`tools/party-tracker/party-tracker`) checked into the repo. Comments in party-cli reference it as historical source (`style.go:6`, `resolve.go:13`).

**Impact:** Confusing to find two tracker implementations. The old one has 0% test coverage and fire-and-forget error handling.

### 2c. Go Test Coverage Gaps

**Current coverage:**

| Package | Coverage | Concern |
|---------|----------|---------|
| `internal/config` | 93.3% | Good |
| `internal/state` | 85.8% | Good |
| `internal/message` | 83.0% | Good |
| `cmd` | 77.9% | Acceptable |
| `internal/tui` | 63.0% | **Low** — critical user-facing surface |
| `internal/picker` | 59.1% | **Low** — fzf interaction paths untested |
| `internal/session` | 58.9% | **Low** — lifecycle logic is the riskiest code |
| `internal/tmux` | 43.3% | **Low** — core infrastructure |

The tmux package (43.3%) is the foundation everything depends on. The session package (58.9%) handles start/stop/promote — the most dangerous operations. Both need better coverage.

### 2d. Stale Task Metadata (31 directories)

**Problem:** `claude/tasks/` contains 31 UUID directories with JSON task files. All are from completed or abandoned work sessions. None are marked as complete. Example: `24a915d2-*/` has 4 pending tasks for "Create codex-trace.sh" — work that was completed months ago.

### 2e. Stale Investigation/Plan Documents

**Problem:** `claude/investigations/` and `claude/plans/` contain pre-harness-v2 documents referencing retired concepts (`party-tracker.sh`, `cmux-migration`, `companion sessions`). These are historical artifacts that may confuse future sessions.

### 2f. Hook Error Log Contains Only Invalid JSON Errors

**Problem:** `claude/logs/hook-errors.log` has 37 lines, all `{"error": "Invalid JSON input"}`. These appear to be from hooks receiving non-JSON stdin during startup. The log provides no useful signal — it's noise.

### 2g. Empty Debug Log Stubs

**Problem:** Three empty debug log files exist: `hook-debug-codex-gate.log`, `hook-debug-pr-gate.log`, `hook-debug-worktree-guard.log`. Zero bytes each.

### 2h. Session Artifact Disk Space

| Artifact | Size | Action Needed |
|----------|------|---------------|
| `claude/projects/` | **1.2 GB** | Archive/prune old session history |
| `codex/shell_snapshots/` | 3.8 MB | Minor — prune >60 days |
| `claude/shell-snapshots/` | 244 KB | Fine |

---

## 3. Current Pain Points (Ranked)

### P0 — Dual Maintenance Surface (party-lib.sh + Go)

`party-lib.sh` contains manifest CRUD, locking, and tmux operations that are now also implemented in Go. Any schema change or behavioral fix must be applied in both places. The risk is divergence — e.g., Go uses `flock()` while bash uses `mkdir` locking, and both can write to the same manifest files.

### P1 — tmux-codex.sh Transport Fragility

The Codex transport still uses fire-and-forget `tmux_send()` from party-lib.sh. This is the one remaining high-value bash path that wasn't ported to Go. Long messages can be truncated, and there's no delivery confirmation.

### P2 — Low Go Test Coverage on Critical Paths

`internal/tmux` (43.3%) and `internal/session` (58.9%) are the most important packages and the least tested. The tmux package especially — since it's mocked in all other tests, bugs here aren't caught by downstream tests.

### P3 — Dead Artifacts Accumulation

31 stale task directories, orphaned prompt-templates.md, old party-tracker, stale plans/investigations, empty debug logs, noisy error log. None are blocking, but they add cognitive load.

---

## 4. Prioritized Task List

### Phase 1: Dead Code & Artifact Cleanup

#### Task 1 — Prune party-lib.sh to tmux-codex essentials
**Value:** HIGH — eliminates dual maintenance surface
**Scope:**
- Remove all manifest CRUD functions from party-lib.sh that are no longer called by any external script: `party_state_upsert_manifest`, `party_state_set_field`, `party_state_get_field`, `party_state_add_worker`, `party_state_remove_worker`, `party_state_get_workers`, `ensure_party_state_dir`, `_party_lock`, `_party_unlock`, `party_resolve_cli_cmd`, `party_role_pane_target_with_fallback`
- Move `register-agent-id.sh` to use party-cli for manifest writes (or read-only query), removing its dependency on `party_state_set_field`
- Move `party-master-jump.sh` to use party-cli for state file lookup
- Keep only: `party_state_root`, `party_state_file`, `party_runtime_dir` (needed by tmux-codex.sh for STATE_DIR), `discover_session`, `party_is_master`, `party_codex_pane_target`, `party_role_pane_target`, `party_layout_mode`, `tmux_pane_idle`, `tmux_send`, `write_codex_status`, `party_resolve_cli_bin`, `party_attach`
- **Target:** party-lib.sh drops from 581L to ~250L
- **Files:** `session/party-lib.sh`, `claude/hooks/register-agent-id.sh`, `session/party-master-jump.sh`
- **Acceptance:** All existing hook tests pass. `tmux-codex.sh` works. Thin wrappers work. No manifest CRUD functions remain in bash.

#### Task 2 — Retire old party-tracker
**Value:** MEDIUM — removes confusion, 660L dead Go code
**Scope:**
- Delete `tools/party-tracker/` directory (including the compiled binary)
- Update any docs referencing old tracker path
- Remove old go.mod/go.sum
- **Files:** `tools/party-tracker/*`
- **Acceptance:** `tools/party-tracker/` directory no longer exists. No broken references.

#### Task 3 — Purge stale artifacts
**Value:** LOW — housekeeping, reduces cognitive load
**Scope:**
- Delete all 31 directories under `claude/tasks/` (stale session task metadata, all completed or abandoned)
- Delete orphaned `claude/skills/codex-transport/references/prompt-templates.md`
- Commit `docs/projects/phase-simplification/` as historical project docs
- Clear `claude/logs/hook-errors.log` (all entries are noise from Feb 26)
- Delete empty debug log stubs (`hook-debug-*.log`)
- Archive or prune stale investigation/plan docs in `claude/investigations/` and `claude/plans/` that reference retired concepts
- **Files:** `claude/tasks/`, `claude/skills/codex-transport/references/prompt-templates.md`, `claude/logs/`, `docs/projects/phase-simplification/`, `claude/investigations/cmux-migration.md`, `claude/plans/cmux-migration.md`
- **Acceptance:** `claude/tasks/` has 0 directories. Orphaned files removed. Phase-simplification committed.

### Phase 2: Test Coverage

#### Task 4 — Improve tmux package test coverage (43% → 70%+)
**Value:** HIGH — this package is the foundation for everything
**Scope:**
- Add unit tests for `tmux.Send()` delivery confirmation logic
- Add tests for `tmux.Query()` session/pane discovery paths
- Add tests for `tmux.Lifecycle` (session create, kill, window management)
- Test error paths (tmux not running, invalid session, dead pane)
- **Files:** `tools/party-cli/internal/tmux/tmux_test.go`, potentially new test helpers
- **Acceptance:** `go test ./internal/tmux/ -cover` reports ≥70%

#### Task 5 — Improve session package test coverage (59% → 75%+)
**Value:** HIGH — lifecycle operations are the riskiest code
**Scope:**
- Add tests for `Start()` with master/worker/sidebar layout variants
- Add tests for `Promote()` — master promotion edge cases
- Add tests for `Stop()` / `Delete()` — cleanup guarantees
- Add tests for `Continue()` — resume-claude/resume-codex paths
- **Files:** `tools/party-cli/internal/session/session_test.go`
- **Acceptance:** `go test ./internal/session/ -cover` reports ≥75%

#### Task 6 — Hook test suite maintenance
**Value:** MEDIUM — ensure tests still pass after all changes
**Scope:**
- Run full hook test suite (`claude/hooks/tests/run-all.sh`) and fix any failures
- Verify `test-worktree-guard.sh` covers the edge cases added in Task 2 (harden shell prereqs)
- Add test for `session-cleanup.sh` worktree override cleanup (currently untested)
- **Files:** `claude/hooks/tests/`
- **Acceptance:** `bash claude/hooks/tests/run-all.sh` passes all suites

### Phase 3: Reliability Improvements

#### Task 7 — Add delivery confirmation to bash tmux_send
**Value:** MEDIUM-HIGH — last fire-and-forget path affects Codex communication
**Scope:**
- After `tmux send-keys`, verify the message appeared in the target pane via `tmux capture-pane`
- Add a short unique sentinel to each message; check pane buffer for it
- Return distinct exit codes: 0 (delivered), 75 (pane busy/dropped), 76 (delivery unconfirmed)
- Update `tmux-codex.sh` to handle delivery failures (retry once, then report CODEX_REVIEW_DROPPED)
- **Files:** `session/party-lib.sh` (tmux_send function), `claude/skills/codex-transport/scripts/tmux-codex.sh`
- **Acceptance:** `tmux_send` returns 0 only when message is confirmed in pane buffer. Hook tests pass.

#### Task 8 — Session artifact disk space management
**Value:** LOW — 1.2GB of session history is growing
**Scope:**
- Add `party-cli prune --artifacts` command to clean up:
  - Session history in `claude/projects/` older than 30 days
  - Codex shell snapshots older than 60 days
  - Empty log files
- Add `--dry-run` flag for safety
- Optionally integrate into `session-cleanup.sh` SessionStart hook
- **Files:** `tools/party-cli/cmd/prune.go`, `tools/party-cli/internal/state/`
- **Acceptance:** `party-cli prune --artifacts --dry-run` lists files to delete. Without `--dry-run`, reclaims space.

---

## 5. Dependency Graph

```text
Task 1 (prune party-lib) ──────────────────> Task 7 (delivery confirmation)
Task 2 (retire old tracker) ─── no deps ───
Task 3 (purge artifacts) ────── no deps ───

Task 4 (tmux test coverage) ── no deps ────
Task 5 (session test coverage) ── no deps ─
Task 6 (hook test suite) ──── no deps ─────

Task 7 (delivery confirmation) ── depends on Task 1
Task 8 (disk space mgmt) ──── no deps ─────
```

**Parallelism:** Tasks 1-6 are all independent and can run in parallel. Task 7 depends on Task 1 (party-lib.sh must be pruned before modifying tmux_send in it). Task 8 is independent.

**Recommended execution order:**
1. Phase 1 in parallel: Tasks 1, 2, 3 (quick-fix eligible: Tasks 2, 3)
2. Phase 2 in parallel: Tasks 4, 5, 6
3. Phase 3: Task 7, then Task 8

---

## 6. What NOT To Do

- **Do NOT port tmux-codex.sh to Go** — it works, it's the Codex transport's only consumer of party-lib.sh, and porting it means touching the Codex skill system. The right path is to slim party-lib.sh to only what tmux-codex.sh needs (Task 1).
- **Do NOT delete party-lib.sh entirely** — tmux-codex.sh depends on it for session discovery and pane routing. The goal is to shrink it, not kill it.
- **Do NOT rewrite the evidence system** — it's stable post-phase-simplification. The research report confirmed it's ~2x minimal size with defensible complexity.
- **Do NOT merge task-workflow and bugfix-workflow** — research confirmed trigger routing is more valuable than DRY.
- **Do NOT add branch-scoped evidence** — session ≈ branch in worktree model.

---

## Definition of Done

- [ ] party-lib.sh contains only tmux-codex essentials (~250L, no manifest CRUD)
- [ ] `tools/party-tracker/` directory deleted
- [ ] All 31 stale task directories removed, orphaned files cleaned
- [ ] `internal/tmux` test coverage ≥70%
- [ ] `internal/session` test coverage ≥75%
- [ ] Hook test suite passes with no failures
- [ ] `tmux_send` has delivery confirmation
- [ ] Disk space management available via `party-cli prune --artifacts`
