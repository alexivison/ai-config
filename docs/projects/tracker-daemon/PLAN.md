# Tracker Daemon

> **Goal.** Replace the N independent Bubble Tea tracker processes (one per tmux pane in every party session) with a single long-lived daemon that owns state aggregation and the global selection cursor, plus thin client renderers that connect over a Unix domain socket.
>
> **Approach.** Daemon owns: fsnotify-driven snapshot computation, periodic `tmux list-sessions` liveness poll, global cursor, action execution against `session.Service`/`message.Service`, and `markSessionObserved` writeback. Client owns: render, spinner/blink animation, transient input buffers (relay/broadcast/spawn modes), terminal geometry, keypress forwarding, fallback to embedded mode on daemon failure. Wire format: newline-delimited JSON over `~/.party-state/tracker.sock`, mode 0600.
>
> **Path conventions:** all paths relative to `tools/party-cli/` unless prefixed `/`. Repo root is `/home/user/ai-party`.

## Why now

**Scope: consumer-side aggregation only.** This daemon reads `state.json` files — it does not touch the per-hook fork-exec of `party-cli` that produces them. Hooks remain invoke-and-exit, writing the same `state.json` format via atomic-rename + flock exactly as today. The `hook-state-tracker/PLAN.md` ingestion model is unchanged; this PR extends it with an aggregator on the read side.

At 5–10 master sessions with ~2–3 workers each, the tracker spawns 15–30 Bubble Tea processes. Each polls tmux + scans `~/.party-state/` independently, each holds its own cursor (so navigation drifts between panes), and each calls `markSessionObserved` on its own current session every refresh tick. That's the N×N pattern this refactor collapses to 1×N.

## Phases

| Phase | Deliverable | Effort | Depends on | Status |
|-------|-------------|--------|------------|--------|
| 1 | Daemon scaffolding: `party-cli tracker daemon`, UDS server, fsnotify snapshot loop, election via flock | 5d | hook-state-tracker complete | ⏳ |
| 2 | Client mode: `party-cli tracker client`, snapshot protocol, render-only TUI extracted from `TrackerModel`, detach-cursor toggle | 4d | Phase 1 | ⏳ |
| 3 | Action RPC: Attach/Continue/Relay/Broadcast/Spawn/Delete/ManifestJSON over the wire with origin-pane + client geometry | 4d | Phase 2 | ⏳ |
| 4 | Lifecycle hardening: stale-socket cleanup, watchdog, version handshake, graceful shutdown, reconnect with embedded fallback | 3d | Phase 3 | ⏳ |
| 5 | Dogfood + flip default `PARTY_TRACKER_MODE=daemon` | 2 calendar weeks | Phase 4 | ⏳ |
| 6 | Remove embedded mode after one release of soak | 1d | Phase 5 + 1 release | ⏳ |

Total focused engineering: ~17 days. Realistic calendar to flipping the default: 5–6 weeks.

## Definition of Done

- [ ] Running 10 master sessions with workers (~25 panes): per-tracker RSS drops from ~6 MB (current) to ~1–1.5 MB (thin clients) — total resident set across tracker processes drops from ~150 MB to under 40 MB including the 1 daemon. The process count itself does not change (each pane still hosts a Bubble Tea program); what drops is per-process cost (no fsnotify watcher, no aggregation, no tmux probe per pane)
- [ ] Selection cursor stays in sync across all tracker panes (press `j` in any pane → all panes update)
- [ ] All existing tracker actions work via the daemon: Attach jumps from the requesting pane, Continue/Spawn create sessions sized to the requesting client (`currentClientSize` no longer degrades silently), Relay/Broadcast/Delete/ManifestJSON behave identically to embedded mode
- [ ] Daemon crash → next client trigger respawns within 2 seconds
- [ ] Daemon upgrade (party-cli reinstalled): old clients reject on protocol mismatch and fall back to embedded; new clients reconnect to new daemon
- [ ] Stale socket from unclean shutdown is auto-cleaned by the next client on election
- [ ] Snapshot fan-out is bounded — a hung client never blocks the daemon's event loop
- [ ] `markSessionObserved` writes happen exactly once per session per refresh, not N times
- [ ] `PARTY_TRACKER_MODE=embedded` env var preserves legacy in-process behavior unchanged
- [ ] Integration tests cover: daemon spawn-on-demand, snapshot push on `state.json` change, client reconnect after `SIGKILL`, version-skew rejection, concurrent-daemon election race
- [ ] No regressions in `tracker_test.go`, `tracker_phase2_test.go`, `tracker_actions_test.go`, `model_test.go`, or the shell suite in `/tests/`
- [ ] `docs/projects/tracker-daemon/README.md` written: how to operate, how to debug, where logs land

## Design

### Daemon process

Lives at `internal/tracker/daemon/`. Entry point: `daemon.Run(ctx context.Context, store *state.Store, client *tmux.Client) error`. Concerns:

1. **Snapshot aggregator** (`snapshot.go`) — wraps the existing `tui.NewLiveSessionFetcher` logic. fsnotify watcher on `~/.party-state/` with manual recursive expansion (Linux inotify is not recursive). 3s tmux `ListSessions` poll for liveness (state files linger after `tmux kill-session` — file events alone do not surface session death; see Agent 2 finding §5). On any event: recompute `TrackerSnapshot`, fan out to all clients.
2. **Client registry** (`registry.go`) — `map[clientID]*conn`. Each conn carries: origin tmux session, terminal geometry, last-acked snapshot seq, bounded send channel (cap 4), monotonic per-client sequence.
3. **Global cursor + observation sink** (`cursor.go`) — owns the `selected SessionID`. Owns `markSessionObserved` writeback: clients send "I observed X at T", daemon coalesces multiple observers into one `state.UpdateSessionState` call per (sessionID, tick).
4. **Action executor** (`actions.go`) — server-side implementation of the seven `TrackerActions` methods (`tracker_actions.go:31-39`). Each RPC carries the requesting client's origin session + geometry; the executor invokes `session.Service`/`message.Service` with those parameters.

### What stays on the client

Per Agent 1 finding §3 and §6:

- **Animation cadences** (`tracker.go:225-241`): spinner (100ms) and blink (600ms) stay client-side. Shipping them over the wire would push ~10 msgs/sec/client; the snapshot itself only needs to fly when state changes.
- **Transient input buffers** (`tracker.go:96, 111`): relay/broadcast/spawn input modes hold per-keystroke text that targets the requesting pane's session. Stay local.
- **Mode enum** (`tracker.go:33-39`): each client picks its own mode independently. Pressing `r` in pane A enters relay mode there only.
- **Viewport scroll / manifest scroll** (`tracker.go:109`): local.
- **`lastErr`** (`tracker.go:99`): populated from RPC response envelopes instead of direct Go-call returns.

The split is: snapshot data + selection cursor + observation writeback go daemon-side. Everything else stays client-side.

### Wire protocol

Newline-delimited JSON. One message per line. UTF-8. Versioned via `protocol` int. Initial version `1`.

**Socket path resolution:**
1. `$XDG_RUNTIME_DIR/party-cli/tracker.sock` if `XDG_RUNTIME_DIR` is set
2. else `$PARTY_STATE_ROOT/tracker.sock` if `PARTY_STATE_ROOT` is set
3. else `$HOME/.party-state/tracker.sock`

Mode 0600. Path length safely under 104 chars (BSD limit) for default `$HOME` patterns.

**Client → daemon: hello**
```json
{"type":"hello","protocol":1,"client_id":"<uuid>","origin_session":"party-1741230000","width":120,"height":40}
```

**Daemon → client: welcome**
```json
{"type":"welcome","protocol":1,"daemon_pid":12345,"snapshot_seq":42}
```

**Daemon → client: reject (version skew)**
```json
{"type":"reject","reason":"protocol_version","supported":[1,2],"got":3}
```
On reject, client falls back to embedded mode and writes a one-liner to stderr + `~/.party-state/tracker.fault`.

**Daemon → client: snapshot**
```json
{"type":"snapshot","seq":42,"sessions":[...SessionRow...],"current":{"session_type":"master","title":"..."},"selected":"party-1741230000","observed_at":"2026-05-21T12:00:00Z","status":""}
```
`SessionRow` is serialized as-is from `internal/tui/tracker.go:44-63` — all exported, all JSON-friendly today.

**Client → daemon: events**
- `{"type":"key","key":"j"}` — keypresses for cursor + global state (`j`/`k`/`g`/`G`/Enter)
- `{"type":"resize","width":120,"height":40}` — on SIGWINCH
- `{"type":"observed","session_id":"party-1741230000","at":"2026-05-21T12:00:00.500Z"}` — sent after each snapshot render
- `{"type":"action","id":"<uuid>","kind":"attach","target":"party-1741230001","origin_session":"party-...","origin_width":120,"origin_height":40}` — modal actions
- `{"type":"manifest_request","id":"<uuid>","session":"party-1741230001"}`
- `{"type":"bye"}`

**Daemon → client: responses**
- `{"type":"action_result","id":"<uuid>","ok":true,"err":""}`
- `{"type":"manifest_response","id":"<uuid>","session":"...","json":"<escaped>"}`
- `{"type":"error","detail":"..."}` — out-of-band errors

Per Agent 3 finding §2: only `Attach`, `Continue`, `Spawn`, `Delete` need origin context. `Relay`/`Broadcast`/`ManifestJSON` do not. The protocol carries origin uniformly for simplicity — daemon ignores it where unused.

### Election / spawn-on-demand

Lockfile: `<socket_dir>/tracker.pid` (sibling of the socket). PID file format: text PID + newline.

**Client connect flow:**
1. Check `exec.LookPath("party-cli")`. If absent, skip election entirely → immediate embedded fallback with a one-line stderr. This prevents `setsid + fork(go run .)` from `config/resolve.go:21-28` (the `go run` compile alone takes seconds and blows past the dial-backoff budget across all clients simultaneously).
2. `net.Dial("unix", socketPath)`. On success, send hello, proceed.
3. On `ENOENT` or `ECONNREFUSED`: enter election.
4. Election: open `tracker.pid` with `O_CREATE|O_RDWR`, attempt `LOCK_EX|LOCK_NB`.
   - **Lock acquired:** read PID, check if alive (`kill -0`). If dead or empty, fork `party-cli tracker daemon --socket <path>` with `setsid`, redirect stdout/stderr to `<socket_dir>/tracker.log` (append, rotated by external logrotate or daemon at 10MB). Wait for daemon to bind socket (poll `Dial` with 50ms backoff, max 2s). Write daemon PID. Release lock.
   - **Lock contested:** another client is electing. Wait up to 2s polling `Dial`.
5. After election attempt, retry `Dial` with backoff 50/100/200/400/800 ms (5 attempts). On final failure, fall back to embedded mode, write fault marker.

**Daemon startup:**
1. Acquire `tracker.pid` lock (`LOCK_EX|LOCK_NB`). On failure, exit code 2 (another daemon owns it).
2. Try `net.Listen("unix", socketPath)`. On `EADDRINUSE`, try to `Dial` — if Dial succeeds, exit (race lost). If Dial fails, `unlink` socket + retry once.
3. Write own PID to `tracker.pid`. Keep lock held for daemon lifetime.
4. Start fsnotify watcher, accept loop, snapshot dispatcher.

**Watchdog:**
- Daemon touches `<socket_dir>/tracker.alive` every 5s.
- Clients monitor `tracker.alive` mtime. If > 15s stale: treat daemon as dead, close socket, re-enter election.

### fsnotify event handling

Watch directory: `~/.party-state/`.

**Recursive watch on Linux:**
- On startup: walk `~/.party-state/` once, add inotify watch for the root and every existing subdir.
- On `IN_CREATE` event for a subdir: add watch immediately, then list contents (in case `state.json` was created between the dir-create and watch-add).
- On `IN_DELETE_SELF` for a subdir: remove watch.

**Event filter** (Agent 2 finding §1, §2, "Red flags" §3):
- `state.json` `IN_MOVED_TO` or `IN_CREATE` (root dir + every subdir) → recompute snapshot
- `<party-id>.json` `IN_MOVED_TO` or `IN_CREATE` (root) → recompute (manifest changed)
- `*.tmp`, `*.lock`, `*.jsonl*` → ignore
- All else → ignore

**Coalescing:** 50ms debounce on the recompute pipeline. Multiple events in the window collapse to one snapshot pass.

**Liveness:** fsnotify alone cannot detect tmux session death (state files persist; see Agent 2 §5). Keep a daemon-side 3s `tmux list-sessions` poll; combine with fsnotify-driven snapshots for full coverage. Tests assert that killing tmux session X marks the row `stopped` within 4s.

### TUI client

Lives at `internal/tracker/client/` for transport + `internal/tui/clientmodel.go` for the Bubble Tea wrapper.

Startup:
1. Generate `client_id` (UUID).
2. Resolve `PARTY_SESSION` via existing `discoverSessionID` (`internal/tui/model.go:389-413`).
3. Connect (election protocol above).
4. Send hello with terminal geometry from `term.GetSize(int(os.Stdout.Fd()))`.
5. Receive welcome.
6. Goroutine reads daemon → channel of decoded messages. Snapshot → `tea.Cmd` → re-render. Action result → match by RPC id → resolve pending future.
7. Goroutine writes channel → daemon (serialized JSON + newline).
8. Spinner + blink local (`bubbles/spinner` keeps current cadence).
9. `tea.WindowSizeMsg` → forward `resize` to daemon.
10. Daemon socket EOF or `tracker.alive` stale: close, re-elect. If election fails N times: fall back to embedded.

The existing `TrackerModel` (`internal/tui/tracker.go:89`) is refactored: snapshot computation extracted to `internal/tui/snapshot.go` (already nearly there with `NewLiveSessionFetcher`). Render funcs (`viewSessions`, `renderStatusBar`, `renderSessionRow`, etc.) made into pure functions taking `TrackerSnapshot + RenderState`. Client model holds the snapshot + `RenderState`, calls renderers directly.

### Origin-pane semantics

Per Agent 3 finding §1 and "Red flags" §1, §2, §3:

Every action RPC includes `origin_session`. Server-side:

- **Attach** wraps the existing `tmux run-shell -t <origin_session> "switch-client -t <target>"` pattern.
- **Continue** and **Spawn** additionally use `origin_width`/`origin_height` to override `tmux.Client.currentClientSize` (`internal/tmux/lifecycle.go:74-99`). The current function reads `TMUX_PANE` from process env — fine for embedded mode, useless from a detached daemon. Refactor: `currentClientSize` accepts an optional `(width, height)` override; `session.Service.Start`/`Continue` accept `ClientWidth`/`ClientHeight` in their opts struct.
- **Delete** that targets the requesting client's current session chains an Attach to a survivor (`tracker.go:391-393`). In daemon mode this becomes two sequential RPCs from the client: `Delete` → on success → `Attach(next)`. Daemon does not orchestrate the chain to keep the protocol stateless per action. **Race-prevention requirement:** the client must capture the resolved next-target *at keypress time* (when cursor + snapshot are consistent) and stash it in the action future, *before* dispatching the Delete RPC. Re-resolving `next` after Delete returns is incorrect — a `j` keypress between Delete-issued and Delete-returned would move the cursor and produce the wrong Attach target. This preserves the synchronous-in-keypress semantic of today's `tracker.go:391-393`.

### Cursor model

Global cursor, per Agent 1 finding §4:

- `j`/`k`/`g`/`G` keypresses move the daemon-owned `selected SessionID`. Daemon broadcasts updated `selected` in the next snapshot to all clients.
- Mode (relay/broadcast/spawn) is client-local. Entering relay mode in pane A does not change pane B's view.
- `Enter` (in normal mode) sends `action attach target=selected origin_session=<client's PARTY_SESSION>`. The target is the global selection; the origin is the requesting client.

This means: two users (or one user in two panes) navigating simultaneously share the cursor. If both press `j` at the same instant, last-write-wins; daemon serializes keypresses through one goroutine.

**Detach-cursor toggle (Phase 2 design, not deferred):** a `c` keybinding flips the client into "detached cursor" mode. Detached clients render their own local cursor and ignore the daemon's `selected` broadcasts; in detached mode, `selected` is advisory. State lives entirely client-side — the protocol does not change beyond treating the broadcasted `selected` as a hint rather than authoritative. Land this in Phase 2 while the protocol is still fluid; expensive to retrofit if shared-cursor assumptions get baked into client mental models. Concretely useful for: cross-referencing two workers, watching one worker while spawning another, comparing state across rows.

### Spawn-site changes

Per Agent 4 finding §1:

Three call sites currently invoke `s.resolveCLICmd()` to put `party-cli` (no args → embedded TUI) in a pane:
- `internal/session/layout.go:148` (launchSidebar)
- `internal/session/layout.go:206` (launchMaster)
- `internal/session/promote.go:78` (Promote)

New `Service.resolveTrackerLaunchCmd()`:
```go
func (s *Service) resolveTrackerLaunchCmd() (string, error) {
    base, err := s.resolveCLICmd()
    if err != nil {
        return "", err
    }
    if os.Getenv("PARTY_TRACKER_MODE") == "embedded" {
        return base, nil
    }
    return base + " tracker client", nil
}
```

All three sites call the new resolver. `cmd/root.go:73-75` (the no-args TUI fallback) stays — shell invocations of `party-cli` still launch embedded mode, used for ad-hoc inspection.

**Runtime mode flips.** The tracker *process itself* (in `cmd/tracker.go`) also reads `PARTY_TRACKER_MODE` at startup. Effect: toggling the env in a shell + `tmux respawn-pane -t <tracker>` becomes a valid runtime flip path. Without this, the only way to flip mode mid-session is "delete and recreate the session" — too coarse to be useful for fallback-on-daemon-problem. Two reads, both cheap; the runtime read is what makes the fallback story actually usable.

### Test infrastructure

Per Agent 5 "Red flags" §1, §5: there is no multi-process test harness today. Build one as part of Phase 1.

New package `internal/tracker/testharness/`:

- `InProcDaemon(t *testing.T) (*Daemon, *Conn)` — daemon + client connected over `net.Pipe()`. For protocol unit tests, fast.
- `UDSDaemon(t *testing.T) (*UDSHarness)` — real socket in `t.TempDir()`, real daemon goroutine. For integration tests of election, reconnect, version handshake.
- `FakeFSNotifier` — injectable event source for snapshot tests.
- `FakeTmuxClient` — shared mock, replaces the per-package `mockRunner` pattern noted by Agent 5 §1 (refactor noted in `party-cli-refactor/PLAN.md:191`; do this opportunistically as part of Phase 1, since we need a robust fake for daemon integration tests anyway).

Bubble Tea client tested through existing `Model.Update`/`Model.View` pattern (Agent 5 §1). Protocol round-trips tested via channel adapters.

### Logging + observability

- Daemon stderr → `<socket_dir>/tracker.log`, append. Internal rotation at 10 MB to `.1` (one-deep, like `state.jsonl.1` precedent at `hookstate.go:289-293`).
- Structured logging via `log/slog`. JSON output. Fields: `client_id`, `origin_session`, `protocol`, `seq`, `duration_ms`, `err`.
- `party-cli tracker status` subcommand: dials daemon, requests `{type:"stats"}`, prints `{uptime, client_count, last_snapshot_at, last_error, snapshot_count, fsnotify_event_count}`, exits. Useful for diagnosing whether the daemon is alive without attaching a client.

## Sequenced rollout

### Phase 1 — Scaffolding (5d)

**Files to create:**
- `internal/tracker/daemon/daemon.go` — `Daemon` struct, `Run(ctx)` constructor
- `internal/tracker/daemon/snapshot.go` — fsnotify aggregator with debounce + recursive watch
- `internal/tracker/daemon/server.go` — UDS listener, per-client accept goroutine, dispatch
- `internal/tracker/daemon/election.go` — flock-based election + spawn-on-demand
- `internal/tracker/daemon/protocol.go` — wire types, version constants
- `internal/tracker/daemon/cursor.go` — global cursor + observation coalescer
- `internal/tracker/daemon/watchdog.go` — alive file touch loop
- `internal/tracker/testharness/inproc.go`
- `internal/tracker/testharness/uds.go`
- `internal/tracker/testharness/fakes.go`
- `cmd/tracker.go` — parent cobra command + `daemon`, `client`, `status` subcommands (matches `party-cli hooks {install,status,uninstall}` pattern in `cmd/hooks.go`)

**Files to modify:**
- `go.mod` — add `github.com/fsnotify/fsnotify`
- `cmd/root.go:78-99` — register `newTrackerCmd(o.store, o.client)`

**Tests:**
- Snapshot recompute fires ≥1 time after a burst of `state.json` writes settles. Phrased as "at least one recompute within 100ms of the last write," not "one recompute per write" — macOS FSEvents (which fsnotify backs onto) coalesces aggressively and would otherwise flake
- `.tmp`/`.lock`/`.jsonl*` events are ignored
- Subdir CREATE triggers nested watch
- Election: two would-be daemons → exactly one survives
- Stale socket from killed daemon → next election succeeds after unlink-rebind
- tmux liveness poll flips a session to `stopped` within 4s of `kill-session`

### Phase 2 — Client mode (4d)

**Files to create:**
- `internal/tracker/client/conn.go` — UDS dialer with election trigger on connect failure
- `internal/tracker/client/reconnect.go` — backoff, fault marker, embedded fallback
- `internal/tui/clientmodel.go` — Bubble Tea wrapper consuming snapshot channel

**Files to modify:**
- `internal/tui/tracker.go` — split `applySnapshot`/`updateSnippetActivity`/`preserveLastSnippets`/`markSessionObserved` from the rendering path. Snapshot-apply logic moves daemon-side; render funcs become pure
- `internal/tui/app.go:17-24` — `Launch()` reads `PARTY_TRACKER_MODE`. Default `embedded` (Phase 2); switches to `daemon` at Phase 5
- `cmd/tracker.go` — `client` subcommand wires up the client model; also has the detach-cursor toggle (`c` keybinding) per the Cursor model design section

**Tests:**
- Client connects, receives 3 snapshots, renders the third
- Spinner ticks do not trigger any daemon RPCs
- `tea.WindowSizeMsg` produces one `resize` event on the wire
- Daemon kills the connection → client schedules reconnect
- 5 reconnect failures → falls back to embedded model

### Phase 3 — Action RPC (4d)

**Files to create:**
- `internal/tracker/daemon/actions.go` — server-side `TrackerActions` with origin context
- `internal/tracker/client/actions.go` — client-side stub returning futures

**Files to modify:**
- `internal/tui/tracker_actions.go` — split `liveTrackerActions` into daemon-side (with full Service deps) and client-stub (RPC-only)
- `internal/session/service.go` — `StartOpts` and `ContinueOpts` accept `ClientWidth`, `ClientHeight`
- `internal/session/start.go` and `continue.go` — pass overrides into layout
- `internal/tmux/lifecycle.go:74-99` — `currentClientSize` accepts `(int, int)` override; returns it when non-zero

**Tests:**
- Attach RPC routes through `run-shell -t <origin_session>`; mock asserts the exact tmux args
- Continue with explicit `ClientWidth=200`/`Height=60` skips the `TMUX_PANE` probe
- Spawn with no override falls back to tmux defaults (regression case for daemon mode)
- Relay round-trip: client sends action, daemon executes `message.Service.Relay`, client receives action_result
- ManifestJSON request/response carries the full JSON

### Phase 4 — Lifecycle hardening (3d)

**Files to create:**
- `internal/tracker/daemon/shutdown.go` — SIGTERM/SIGINT handler, drain clients with `bye`
- `internal/tracker/daemon/version.go` — handshake helpers

**Files to modify:**
- `internal/tracker/client/conn.go` — read welcome/reject, route to fallback on reject
- `internal/tracker/daemon/watchdog.go` — touch frequency, alive-file ownership

**Tests:**
- Daemon `SIGKILL` mid-snapshot → client reconnects via election; new daemon serves next snapshot within 2s
- Daemon `SIGTERM` → drains clients with `bye`; clients reconnect; no `EPIPE` panic
- Protocol mismatch → client falls back; fault file written; embedded mode renders correctly
- Concurrent spawn-on-demand from 3 clients → exactly one daemon
- Watchdog alive-file stale > 15s → clients reset connection

### Phase 5 — Dogfood + flip default (2 calendar weeks)

- Use daemon mode personally for 1 week.
- Add `PARTY_TRACKER_MODE=daemon` to `install.sh setup_party_cli` as the default; allow opt-out via `PARTY_TRACKER_MODE=embedded` in `~/.config/party-cli/config.toml`.
- Write `docs/projects/tracker-daemon/README.md`: how to debug (`tracker status`, log location, fault file), how to disable, how to restart (`tracker restart` Phase 6 candidate).
- Update top-level `README.md` to mention the daemon as the default tracker substrate.
- Cross-link in commit summary: this PR extends `hook-state-tracker/PLAN.md` with a consumer-side aggregator; the hook-ingestion path is unchanged.

### Phase 6 — Remove embedded mode (1d, after one release of soak)

- Delete `PARTY_TRACKER_MODE=embedded` branches.
- Delete `tui.Launch` embedded path; `cmd/root.go:73-75` instead bootstraps a `--client` invocation transparently.
- Delete `liveTrackerActions` direct-call code now unused.
- Bump protocol version, simplify handshake (no fallback path).

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Reviewer mis-reads this as reversing the anti-daemon principle from `hook-state-tracker/PLAN.md:600-604` | Frame as additive: this is a consumer-side aggregator for the same file-based state contract. The hook-ingestion model (invoke-and-exit, atomic-rename, flock) is unchanged. Make this explicit in the PR description, the "Why now" section header, and Phase 5 commit summary |
| 2 | UDS socket lifecycle bugs (stale sockets, election races, restart corruption) | flock-based election + try-connect-then-unlink-rebind protocol; concurrent-spawn integration test in Phase 1 |
| 3 | Daemon crash leaves clients stuck | Watchdog `tracker.alive` file with 15s stale threshold; client reconnects with backoff; fallback to embedded after N failures |
| 4 | Version skew during upgrade | Protocol version in hello; daemon rejects incompatible clients with explicit `supported` list; client falls back to embedded |
| 5 | `currentClientSize` silently degrades for daemon-spawned sessions (Agent 3 "Red flags" §1) | Pass `ClientWidth`/`ClientHeight` in every Spawn/Continue RPC; `currentClientSize` accepts override; integration test asserts new session is sized to requester |
| 6 | New attack surface: UDS socket | Per-user socket at user-only path, mode 0600; validate peer UID matches our own via `SO_PEERCRED` (Linux, returns `struct ucred {pid,uid,gid}`) / `getpeereid` (macOS, returns uid+gid); treat protocol input as untrusted; bound message size at 1 MB |
| 7 | No multi-process test harness exists (Agent 5 "Red flags" §1) | Build `internal/tracker/testharness/` as a Phase 1 deliverable, mandatory for Phases 2–4 |
| 8 | fsnotify event noise from `.tmp`/`.lock`/`.jsonl*` files (Agent 2 "Red flags" §1, §3, §4) | Filter by basename; 50ms debounce; tested in `snapshot_test.go` |
| 9 | tmux liveness still requires polling because state files linger after `kill-session` (Agent 2 §5) | Keep 3s `ListSessions` poll daemon-side — but once per daemon, not per pane. Net cost drops ~N× |
| 10 | Picker (`cmd/picker.go`) and `cmd/sessions.go` JSON bypass the daemon (Agent 4 §7, §9) | Out of scope. They continue reading state files directly. Daemon is purely additive |
| 11 | Cold-start `go run .` fallback (`config/resolve.go:21-28`) blows past the 1.55 s dial-backoff budget in daemon mode (multi-second Go compile alone exhausts it across all clients simultaneously) | Client checks `exec.LookPath("party-cli")` **before** entering election (step 1 of Client connect flow). If absent → skip election → immediate embedded fallback with one-line stderr. Never trigger `setsid + fork(go run .)` from the election path |
| 12 | Snapshot fan-out blocking on slow client; redundant broadcasts under sustained hook bursts | Bounded per-client send channel (capacity 4); on overflow, drop oldest non-current frame; daemon goroutine never blocks. Additionally: hash the serialized snapshot before broadcasting; if identical to last broadcast, skip the fan-out entirely. Under tool-storm (~20 Hz debounce ticks) this saves ~25 clients × ~5 KB × 20 Hz ≈ 2.5 MB/s on UDS plus matching client-side decode + render cost |
| 13 | `markSessionObserved` ownership confusion (daemon vs. client) | Daemon owns the write; clients send `observed` events; daemon coalesces by (session_id, tick) before one write per session per refresh |
| 14 | Pane SIGHUP on tmux session-close doesn't notify daemon of dead clients (Agent 4 §5) | Daemon detects via socket EOF + periodic `tmux list-clients` reconciliation; clients whose origin session is gone are reaped |
| 15 | Fallback to embedded silently hides daemon failures | When fallback triggers, write one-line stderr to client pane + fault file at `<socket_dir>/tracker.fault` with timestamp + reason |
| 16 | Conflict with in-flight `party-cli-refactor` or `pi-third-agent` | Coordinate via PLAN status updates; daemon scaffolding (Phase 1) is additive — touches no files those plans modify. Phase 3 touches `internal/session/service.go`, which `party-cli-refactor` Phase 4 (tasks M6 + M7, Start/Continue launch unification) also touches; sequence: this plan's Phase 3 starts only after `party-cli-refactor` Phase 4 lands |
| 17 | TODO files (`~/.claude/todos/`) and resume IDs (`/tmp/<party-id>/`) live outside the watched root (Agent 2 "Red flags" §7) | Daemon watches `~/.claude/todos/` for TODO overlay refreshes (small extra watch); resume IDs only read at session-start, not in steady-state snapshot, so no extra watch needed |
| 18 | `mode == trackerModeManifest` does synchronous `actions.ManifestJSON` on keypress (Agent 1 "Red flags" §6) | Becomes RPC `manifest_request` → `manifest_response`. Client shows spinner on `m` press until response arrives |
| 19 | Cursor + `current.ID` coupling: relay/broadcast gating uses *client's* session, not the highlighted row (Agent 1 §4, "Red flags" §2) | Mode is client-local. Daemon broadcasts the global cursor; each client gates relay/broadcast based on its own `origin_session`'s session_type, sent in hello and refreshed on snapshot |
| 20 | Delete→Attach chain race: cursor moves between the two RPCs and Attach lands on wrong target | Client captures the resolved `next` target at keypress time and stashes it in the action future *before* dispatching Delete. Never re-resolve `next` after Delete returns. Tested with an in-proc daemon that delays Delete response while the test issues `j` keypresses; assert the Attach target matches the captured `next`, not the post-`j` selection |

## Deferred to implementation time

- Whether to switch the wire format from line-delimited JSON to length-prefixed JSON or protobuf — measure first; JSON is fine until profiling shows otherwise
- Exact watchdog cadence beyond the 5s baseline
- Whether to expose `party-cli tracker inspect` (full internal state dump) in addition to `status`
- Whether to support multiple concurrent daemons on the same host scoped to different `PARTY_STATE_ROOT` values (out of scope for v1; XDG keys socket name implicitly)
- Log rotation: ship in v1 (10 MB → `.1`), or punt to external logrotate
- Whether the `restart` admin subcommand lands in Phase 5 or Phase 6

## Out of scope

- `cmd/picker.go` migration to daemon (it stays file-backed; SketchyBar consumes its JSON). Note: the picker has its own scaling concern — it captures 500 lines of scrollback per session preview (`internal/picker/picker.go:287, 350`), which already hits tmux hard when scrolling fast through many sessions. This PR does not address that; a separate effort would.
- `cmd/sessions.go` JSON output migration (used by SketchyBar; remains file-backed)
- Web dashboard, menubar app, or any non-tmux client — the daemon makes these possible later, but they are separate projects
- Adding new tracker UI actions (promote, kill, read, report) — separate work, would extend the action RPC surface
- Replacing the file-based hook → `state.json` pipeline — this daemon consumes it
- Running the daemon as a systemd or launchd service — auto-spawn-on-demand via flock is simpler and sufficient
- Cross-user daemon sharing — per-user only
- **Hook-side fork-exec cost.** Every hook event (PreToolUse / PostToolUse / Stop / SessionStart / UserPromptSubmit) shells out to `party-cli hook <agent> <event>` via `tools/party-cli/internal/hooks/assets/party-cli-state.sh:5`. That's a `/bin/sh` fork + `exec` of the full `party-cli` binary + Go runtime startup + JSON parse + flock + atomic rename per event. At dozens of events/min per agent × N agents this is a real bottleneck on the *agent's* hot path (each PreToolUse delays the tool call). This PR does not address it — a sibling "hook daemon" effort would. They are orthogonal: this daemon **consumes** `state.json`; a hook daemon would **produce** it. Distinct processes, distinct sockets, distinct failure modes

## Prior art

- **`docs/projects/hook-state-tracker/PLAN.md`** — defines the file-based state pipeline this daemon consumes. Its "Why a different mechanism here" section (lines 600–604) argues against a daemon for hook *ingestion*; this PR is additive to that contract on the consumer side and leaves the ingestion model untouched.
- **`internal/state/store.go` and `internal/state/hookstate.go`** — atomic write via temp + `os.Rename`, lock-free reads. The daemon's snapshot aggregator depends on this contract.
- **`tmux run-shell -t <session> "switch-client -t <target>"`** in `internal/tui/tracker_actions.go:68-71` — the existing daemon-safe pattern for `switch-client`. Generalized to all origin-pane-bound actions in this plan.
- **`TrackerActions` interface** (`internal/tui/tracker_actions.go:31-39`) — the existing seam for action injection. The daemon implements one variant; the client a stub variant.
- **`TrackerModel.SessionFetcher` injection** (`internal/tui/tracker.go:80`) — existing seam for snapshot computation. The client model consumes a snapshot channel instead.
- **`internal/tmux/client.go` `Runner` interface + per-package `mockRunner`** — existing pattern for tmux mocking. The new `testharness/FakeTmuxClient` consolidates this where it helps the daemon refactor.
- **Charmbracelet `bubbletea`** — already in use. The client mode is a `tea.Program` consuming a snapshot channel; no new TUI framework.
