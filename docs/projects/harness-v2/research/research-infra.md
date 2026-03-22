# Session Infrastructure Research Report

**Date:** 2026-03-21
**Scope:** session/, tools/party-tracker/, tmux layer, CLI feasibility, planned work

---

## Executive Summary

The party session infrastructure is a 2,480-line system (1,722 bash + 660 Go + 98 tmux config) that orchestrates AI agent sessions via tmux. It works reliably ~99% of the time but has accumulated complexity: race conditions in locking, silent failures on missing dependencies, duplicated launch logic, and fire-and-forget messaging. The Go TUI is well-engineered but thin — a facade over bash. The tmux dependency is deep and irreplaceable without fundamental redesign.

**Key finding:** The system's biggest risk is not any single bug but the cumulative fragility of bash orchestrating stateful concurrent processes. A unified Go CLI would solve the testability and reliability gaps while preserving the tmux interaction model that actually works well.

---

## Current State

### Line Counts & Complexity

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **Session** | party.sh | 482 | Entry point: launch, resume, stop, promote, list |
| | party-lib.sh | 503 | Shared utilities: state, locking, pane routing, tmux ops |
| | party-master.sh | 186 | Master session lifecycle |
| | party-relay.sh | 252 | Worker-to-master communication |
| | party-picker.sh | 197 | fzf session picker |
| | party-preview.sh | 65 | fzf preview pane |
| | party-master-jump.sh | 37 | Keybinding helper |
| **Go TUI** | main.go | 436 | Bubble Tea TUI core |
| | workers.go | 154 | Worker state & tmux interaction |
| | actions.go | 70 | Command dispatch to shell |
| **tmux** | tmux.conf | 98 | Session config, plugins, status bar |
| **Total** | | **2,480** | |

### Architecture Diagram

```
User
  │
  ├─ party.sh ────────────── Launch / resume / stop sessions
  │    ├─ party-lib.sh ───── State management, locking, tmux ops
  │    ├─ party-master.sh ── Master-specific launch
  │    └─ party-picker.sh ── fzf picker UI
  │
  ├─ party-relay.sh ──────── Master↔Worker messaging
  │
  ├─ party-tracker (Go) ──── Master dashboard TUI
  │    └─ actions.go ──────── Shells out to party.sh / party-relay.sh
  │
  └─ tmux-codex.sh ──────── Claude↔Codex transport
       └─ party-lib.sh ──── Session discovery, pane routing
```

### State Management

- **Persistent:** `~/.party-state/party-<id>.json` — manifest per session (JSON, mkdir-locked)
- **Runtime:** `/tmp/<session-name>/` — session markers, relay buffers
- **tmux metadata:** `@party_role` pane option — role-based routing

---

## Pain Points (Ranked by Impact)

### P0 — Silent Failures

1. **jq missing = silent data loss.** All manifest operations return 0 when jq is absent. Sessions resume with wrong CWD, lost metadata. No warning to user.

2. **Message delivery is fire-and-forget.** `tmux_send` drops messages after 1.5s timeout with return code 75, which callers ignore. Messages to dead panes vanish.

3. **Lock timeout = silent operation failure.** When `_party_lock` times out (10s), manifest writes silently fail. Concurrent worker spawns can lose state.

### P1 — Race Conditions & Concurrency

4. **mkdir-based locking with fixed 10s timeout.** No exponential backoff. 5+ concurrent workers spawning can cause contention cascades.

5. **Worker registry inconsistency.** Master's `workers[]` can diverge from reality — crashed workers don't deregister, lock timeout loses deregistration.

6. **Partial manifest writes.** If jq transform fails mid-operation, temp file is cleaned but original is unchanged. No corruption, but silent data loss.

### P2 — Code Quality & Maintenance

7. **Duplicated agent launch logic.** `party.sh:86-158` and `party-master.sh:5-84` share ~60% identical code. Bug fixes must be applied twice.

8. **Fragile fzf keybinding escaping.** Complex shell commands embedded in fzf `--bind` strings. Paths with spaces break the picker.

9. **Legacy fallback in pane routing.** 2-pane sessions without `@party_role` fall back to hardcoded indices (pane 0=claude, 1=codex). Wrong if pane order differs.

### P3 — Minor

10. **Orphaned temp files.** Signal interrupts between `mktemp` and cleanup leave `/tmp/party-state.XXXXXX` files.

11. **Unquoted variable in tmux hook.** `$lib_path` in `set-hook` string — injection risk if path contains metacharacters.

12. **100ms polling in tmux_send.** 15 wakeups per send attempt. Inefficient for broadcasts to many workers.

---

## Refactoring Opportunities (Ranked by Effort vs Value)

### Quick Wins (1-2 hours each)

| # | Opportunity | Value | Effort |
|---|-----------|-------|--------|
| 1 | **Mandate jq with early check + clear error** | Eliminates P0.1 | 15 min |
| 2 | **Quote `$lib_path` in tmux hooks** | Fixes injection risk | 10 min |
| 3 | **Add trap cleanup for temp files** | Fixes P3.10 | 30 min |
| 4 | **Log tmux_send failures to stderr** | Surfaces P0.2 | 20 min |

### Medium Effort (1-2 days each)

| # | Opportunity | Value | Effort |
|---|-----------|-------|--------|
| 5 | **Extract shared launch logic** into `_party_launch_common()` in party-lib.sh | Eliminates P2.7 | 1 day |
| 6 | **Add exponential backoff to locking** + configurable timeout | Mitigates P1.4 | 0.5 day |
| 7 | **Add delivery confirmation** to tmux_send (check pane history after send) | Mitigates P0.2 | 1 day |
| 8 | **Remove legacy pane fallback** — require @party_role on all sessions | Eliminates P2.9 | 0.5 day |

### Larger Refactors (1+ weeks)

| # | Opportunity | Value | Effort |
|---|-----------|-------|--------|
| 9 | **Unified Go CLI** replacing bash scripts | Solves P0-P2 | 2-3 weeks |
| 10 | **Absorb picker into tracker TUI** | Reduces scripts by 262 lines | 1 week |
| 11 | **Structured IPC** replacing tmux send-keys | Solves P0.2 fundamentally | 2 weeks |

---

## Language/Stack Evaluation

### Bash (Status Quo)

| Aspect | Rating | Notes |
|--------|--------|-------|
| Iteration speed | A | Edit and run instantly |
| Testability | D | No unit test framework; integration tests are flaky |
| Concurrency | F | Race conditions are structural, not bugs |
| Error handling | D | Silent failures everywhere; `set -e` is a blunt instrument |
| tmux integration | A | Native — `tmux` commands are just shell commands |
| State management | C | jq + file locking works but fragile |
| Maintainability | C | 1,722 lines is the complexity ceiling for bash |

**Verdict:** Bash got us here but is hitting its ceiling. The complexity is manageable today but will degrade as sidebar-tui adds companion sessions, status files, and more routing logic.

### Go (Recommended)

| Aspect | Rating | Notes |
|--------|--------|-------|
| Iteration speed | B | Compile step, but fast (Go compiles in <1s) |
| Testability | A | Table-driven tests, mocking, race detector |
| Concurrency | A | Goroutines, channels, sync primitives |
| Error handling | A | Explicit error returns, no silent failures |
| tmux integration | B | `exec.Command("tmux", ...)` — slightly more verbose but equally capable |
| State management | A | Proper JSON marshal/unmarshal, file locking with `flock()` |
| Maintainability | A | Types, interfaces, tooling (gofmt, staticcheck, gopls) |

**Verdict:** Go is the natural evolution. Already used for the tracker. Single binary deployment. The team has Go expertise (tracker proves this). Solves concurrency, testability, and error handling structurally.

### Rust

| Aspect | Rating | Notes |
|--------|--------|-------|
| Iteration speed | C | Slower compile, steeper learning curve |
| Everything else | A | Superior to Go in safety guarantees |

**Verdict:** Overkill. Rust's ownership model doesn't add meaningful value over Go for this use case. The system is I/O bound (tmux commands, file ops), not compute bound.

### Python

**Verdict:** Adds runtime dependency. No advantage over Go for this use case. Rejected.

### Hybrid (Go core + bash glue)

**Verdict:** This is what we have today (tracker in Go, everything else in bash). It works but creates a translation layer. A full Go CLI would be cleaner than expanding the hybrid boundary.

---

## CLI Feasibility Assessment

### What `party` CLI Would Look Like

```
party start [--master] [--prompt "..."] [--cwd /path] [--title "..."]
party stop <session-id>
party delete <session-id>
party list [--json] [--format table|compact]
party status <session-id>
party promote <session-id>
party relay <worker-id> "message"
party relay --broadcast "message"
party pick                    # Interactive picker (embedded or fzf)
party tracker <master-id>     # Launch TUI dashboard
party prune                   # Clean stale manifests
```

### What's Easy to Port

- **State management** (manifest CRUD, locking) — Go's `encoding/json` + `flock()` syscall
- **Session listing and pruning** — straightforward tmux queries
- **Relay messaging** — `exec.Command("tmux", "send-keys", ...)`
- **Picker** — either embed with Bubble Tea list component, or shell out to fzf

### What's Hard to Port

- **Agent launch** — building the exact `claude --session-id ... --prompt ...` command with proper quoting and environment setup. This is the most tmux-entangled code.
- **tmux hook registration** — `set-hook session-closed "run-shell '...'"` requires careful escaping
- **Pane role routing** — querying `@party_role` across panes/windows. Works the same in Go but the fallback logic is complex.

### Would It Solve the Core Issues?

| Issue | Bash | Go CLI |
|-------|------|--------|
| Race conditions in locking | mkdir hack | `flock()` + proper file locking |
| Silent failures | Structural | Explicit error returns + logging |
| Testability | Nearly impossible | Table-driven unit tests |
| Message delivery reliability | Fire-and-forget | Can implement retry + ack |
| Code duplication | Manual | Shared functions, types |
| Concurrent worker spawns | Race-prone | Goroutines + sync.Mutex |

### Effort Estimate

- **Phase 1** (state management + list/status/prune): 3-4 days
- **Phase 2** (start/stop/promote): 1 week
- **Phase 3** (relay + transport): 3-4 days
- **Phase 4** (picker, tracker integration): 1 week
- **Total:** ~3 weeks for feature parity

### Risk

The biggest risk is the "rewrite trap" — spending 3 weeks to reproduce existing functionality with new bugs. Mitigation: keep bash scripts working during transition, port one command at a time, use integration tests against real tmux.

---

## Planned Work Assessment

### Sidebar TUI (docs/projects/sidebar-tui/)

**Complexity:** High (6 tasks, 15+ files, shell + Go)

The sidebar plan replaces the visible Codex pane with a narrow sidebar + hidden companion session. Key concern: **it doubles the session management surface area** (companion lifecycle, routing through companions, status file I/O, popup mechanics).

**Simpler alternatives:**
1. **Collapse Codex pane to minimum width** when idle, expand on activity. Zero new sessions, zero new routing. ~80% of the screen-space benefit with ~20% of the effort.
2. **Toggle Codex visibility** with a keybinding (tmux `resize-pane -Z` or similar). Already possible with tmux — just needs a wrapper.
3. **Move Codex to a separate tmux window** (not pane) — accessed via keybinding. Simpler than companion sessions but preserves independence.

**Recommendation:** Try alternative #1 or #3 first. If insufficient, proceed with the full sidebar plan.

### Phase Simplification (docs/projects/phase-simplification/)

**Complexity:** Low-Medium (4 tasks, mostly deletion)

Well-scoped, low-risk simplification. Removes the two-phase gate model, consolidates to single-phase with PR gate as sole enforcer. **Should be done first** — it reduces complexity before adding sidebar features.

**Additional simplification opportunities:**
- The evidence system itself could be simplified further — the JSONL + diff_hash model is sound but the hook scripts are complex
- If moving to Go CLI, evidence recording moves from hook scripts to Go functions — much cleaner

---

## Recommendations

### Immediate (This Week)

1. **Mandate jq** with early check and clear error message in party-lib.sh
2. **Fix the unquoted `$lib_path`** in tmux hook registration
3. **Add temp file cleanup traps** to all functions using mktemp
4. **Complete phase-simplification** — it's low-risk and reduces complexity

### Short-Term (Next 2 Weeks)

5. **Extract shared launch logic** into party-lib.sh to eliminate duplication
6. **Add exponential backoff** to `_party_lock`
7. **Remove legacy pane routing fallback** — require @party_role always
8. **Try simpler sidebar alternatives** before committing to the full plan

### Medium-Term (Next Month)

9. **Begin Go CLI port** — start with state management (Phase 1), which is the most impactful refactor. Keep bash scripts working in parallel.
10. **Absorb picker into tracker** — reduce the script count

### Long-Term (Quarter)

11. **Complete Go CLI** to feature parity — retire bash scripts
12. **Implement structured IPC** for reliable message delivery
13. **Full sidebar TUI** if simpler alternatives prove insufficient

### What NOT To Do

- Don't rewrite everything at once. Port incrementally.
- Don't add Rust. Go is sufficient and already in use.
- Don't add Python. Runtime dependency for no benefit.
- Don't over-engineer the sidebar. Try the simple approach first.
- Don't remove tmux. It's the right tool for multi-pane agent orchestration.

---

## Appendix: Detailed Findings

### A. Session Scripts — Specific Issues

| Issue | Severity | File:Line | Description |
|-------|----------|-----------|-------------|
| Lock timeout silent fail | HIGH | party-lib.sh:45-58 | `_party_lock` returns 1, callers silently skip operations |
| Unquoted `$lib_path` | CRITICAL | party.sh:83 | Shell injection risk in tmux set-hook |
| jq missing = silent skip | HIGH | party-lib.sh:76+ | `command -v jq || return 0` hides all state failures |
| Duplicate launch logic | MEDIUM | party.sh:86-158, party-master.sh:5-84 | ~60% identical code |
| Fragile fzf bindings | MEDIUM | party-picker.sh:171 | Complex shell in --bind string |
| Legacy pane fallback | MEDIUM | party-lib.sh:494-499 | Hardcoded pane indices for 2-pane sessions |
| Orphaned temp files | LOW | party-lib.sh:87+ | No signal trap cleanup |
| Fixed polling interval | LOW | party-lib.sh:351-391 | 100ms constant, no backoff |

### B. Go TUI — Quality Metrics

| Metric | Value | Assessment |
|--------|-------|-----------|
| Total lines | 660 | Lean |
| Cyclomatic complexity (max) | 24 (updateNormal) | Exceeds threshold, refactorable |
| Dependencies | 3 direct (Charm ecosystem) | Minimal |
| Binary size | 4.6 MB | Typical for Go+Bubble Tea |
| Test coverage | 0% | No tests exist |
| Error handling | Fire-and-forget | All exec calls ignore errors |

### C. tmux Layer — Fragility Map

| Scenario | Failure Mode | Recovery |
|----------|-------------|----------|
| tmux server crash | All scripts hang/fail | Restart tmux + party sessions |
| User in copy mode >1.5s | Message silently dropped | Exit copy mode, retry |
| Multiple party sessions outside tmux | Discovery fails | Set PARTY_SESSION env var |
| Pane metadata corrupted | ROLE_NOT_FOUND | Stop and recreate session |
| Codex pane manually killed | Sends to dead pane silently | Recreate session |
| jq missing | State never persisted | Install jq |
| Nested tmux | Discovery finds outer session | Set PARTY_SESSION |

---

*Report generated by Paladin reconnaissance. Codex deep analysis pending — will be appended when received.*
