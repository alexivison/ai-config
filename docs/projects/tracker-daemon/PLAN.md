# Tracker Daemon

> **Goal.** Replace the N independent Bubble Tea tracker processes (one per tmux pane in every party session) with a single long-lived daemon that owns state aggregation and the global selection cursor, plus thin client renderers that connect over a Unix domain socket.
>
> **Approach.** Daemon owns: fsnotify-driven snapshot computation, periodic `tmux list-sessions` liveness poll, global cursor, action execution against `session.Service`/`message.Service`, and `markSessionObserved` writeback. Client owns: render, spinner/blink animation, transient input buffers (relay/broadcast/spawn modes), terminal geometry, keypress forwarding, fallback to embedded mode on daemon failure. Wire format: newline-delimited JSON over a state-root-scoped Unix domain socket (default `~/.party-state/tracker.sock`; `$XDG_RUNTIME_DIR` paths include a hash of the resolved state root), directory mode 0700, socket mode 0600.
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
| 5 | Dogfood + flip compiled tracker default to daemon | 2 calendar weeks | Phase 4 | ⏳ |
| 6 | Remove embedded fallback/mode after one release of soak | 1d | Phase 5 + 1 release | ⏳ |

Total focused engineering: ~17 days. Realistic calendar to flipping the default: 5–6 weeks.

## Definition of Done

- [ ] Running 10 master sessions with workers (~25 panes): per-tracker RSS drops from ~6 MB (current) to ~1–1.5 MB (thin clients) — total resident set across tracker processes drops from ~150 MB to under 40 MB including the 1 daemon. The process count itself does not change (each pane still hosts a Bubble Tea program); what drops is per-process cost (no fsnotify watcher, no aggregation, no tmux probe per pane)
- [ ] Selection cursor stays in sync across all tracker panes (press `j` in any pane → all panes update)
- [ ] Per-client identity stays local: each pane still highlights its own row (`IsCurrent`), derives its own header, and gates Relay/Broadcast/Spawn from its own origin session; a daemon snapshot broadcast never contains another pane's "current" state
- [ ] All existing tracker actions work via the daemon: Attach jumps from the requesting pane, Continue/Spawn create sessions sized to the requesting client (`currentClientSize` no longer degrades silently), Relay/Broadcast/Delete/ManifestJSON behave identically to embedded mode
- [ ] Delete-current-session handoff is atomic from the user's perspective: the client captures the next target at keypress time, the daemon performs the switch/kill as one action, and cursor movement while Delete is in flight cannot change the attach target
- [ ] Daemon crash → next client trigger respawns within 2 seconds
- [ ] Daemon upgrade (party-cli reinstalled): old clients reject on protocol mismatch and fall back to embedded; new clients replace the old daemon and reconnect to a compatible one
- [ ] Stale socket from unclean shutdown is auto-cleaned by the next client on election
- [ ] Snapshot fan-out is bounded — a hung client never blocks the daemon's event loop
- [ ] `markSessionObserved` writes happen exactly once per session per refresh, not N times
- [ ] `PARTY_TRACKER_MODE=embedded` and `[tracker] mode = "embedded"` preserve legacy in-process behavior unchanged
- [ ] Rollback before Phase 6 is documented and tested: flip mode to embedded, respawn tracker panes, stop the daemon; no on-disk state migration or cleanup required
- [ ] Integration tests cover: daemon spawn-on-demand, snapshot push on `state.json` change, client reconnect after `SIGKILL`, version-skew replacement/rejection, concurrent-daemon election race, state-root socket namespace isolation, per-client current projection, delete-current attach handoff
- [ ] No regressions in `tracker_test.go`, `tracker_phase2_test.go`, `tracker_actions_test.go`, `model_test.go`, or the shell suite in `/tests/`
- [ ] `docs/projects/tracker-daemon/README.md` written: how to operate, how to debug, how to roll back, where logs land

## Design

### Daemon process

Lives at `internal/tracker/daemon/`. Entry point: `daemon.Run(ctx context.Context, store *state.Store, client *tmux.Client) error`. Concerns:

1. **Snapshot aggregator** (`snapshot.go`) — wraps a new neutral snapshot seam extracted from `tui.NewLiveSessionFetcher`: rows do not carry `IsCurrent`, and there is no global `CurrentSessionDetail`. The existing embedded fetcher becomes a thin projection wrapper that applies `current SessionInfo` locally. fsnotify watcher on the resolved state root with manual recursive expansion where needed. 3s tmux `ListSessions` poll for liveness (state files linger after `tmux kill-session` — file events alone do not surface session death; see Agent 2 finding §5). On any event: recompute a neutral `TrackerSnapshot`, normalize the global cursor if its row vanished, fan out to all clients.
2. **Client registry** (`registry.go`) — `map[clientID]*conn`. Each conn carries: origin tmux session pinned from hello, terminal geometry from hello/latest resize, last-acked/observed snapshot seq, bounded send channel (cap 4), monotonic per-client sequence.
3. **Global cursor + observation sink** (`cursor.go`) — owns the `selected SessionID`. Owns `markSessionObserved` writeback: clients send "I observed X at T for snapshot seq S", daemon coalesces multiple observers into one `state.UpdateSessionState` call per (sessionID, tick).
4. **Action executor** (`actions.go`) — server-side implementation of the seven `TrackerActions` methods (`tracker_actions.go:31-39`). The executor derives origin session and geometry from the connection registry, not from per-RPC client claims. Action frames carry only action payload (target/text/captured next target); the executor validates IDs, verifies peer UID, then invokes `session.Service`/`message.Service` with the pinned origin context.

### What stays on the client

Per Agent 1 finding §3 and §6:

- **Animation cadences** (`tracker.go:225-241`): spinner (100ms) and blink (600ms) stay client-side. Shipping them over the wire would push ~10 msgs/sec/client; the snapshot itself only needs to fly when state changes.
- **Transient input buffers** (`tracker.go:96, 111`): relay/broadcast/spawn input modes hold per-keystroke text that targets the requesting pane's session. Stay local.
- **Mode enum** (`tracker.go:33-39`): each client picks its own mode independently. Pressing `r` in pane A enters relay mode there only.
- **Viewport scroll / manifest scroll** (`tracker.go:109`): local.
- **`lastErr`** (`tracker.go:99`): populated from RPC response envelopes instead of direct Go-call returns.

The split is: snapshot data + selection cursor + observation writeback go daemon-side. Everything else stays client-side.

### Global snapshot vs. client-local projection

The daemon must not broadcast any field whose value differs by pane. Today `TrackerSnapshot.Current` and `SessionRow.IsCurrent` are computed from the embedded process's `current SessionInfo`; in daemon mode that becomes a client projection step.

- Daemon snapshots contain the ordered rows, hook-derived activity state, liveness, and the global `selected` ID. They do **not** contain `CurrentSessionDetail`, and every wire row omits `is_current`.
- Each client owns `origin_session` from `discoverSessionID`, marks its own row as current before rendering, and derives `CurrentSessionDetail` from that row (falling back to its locally resolved `SessionInfo` only when the row is absent).
- Relay/Broadcast/Spawn gating uses the client's projected origin row, not the highlighted row and not a daemon-global `Current` value.
- If the daemon's selected row disappears after a snapshot recompute, it moves `selected` to the nearest surviving row by the stable rendered order; if no rows survive, `selected` becomes empty. Detached-cursor clients keep their local cursor.

### Wire protocol

Newline-delimited JSON. One message per line. UTF-8. Versioned via `protocol` int. Initial version `1`. Each decoded frame is capped at 1 MiB. Do **not** serialize internal TUI structs directly: `internal/tracker/daemon/protocol.go` defines DTOs with explicit `json` tags (`SessionRowDTO`, `SnapshotMsg`, etc.) and conversion tests. The examples below are the stable wire schema.

**Socket path resolution:**
1. Resolve the state root exactly as production tracker code does: `$PARTY_STATE_ROOT`, else `$HOME/.party-state`.
2. Compute `namespace = hex(sha256(abs(clean(stateRoot))))[:12]`.
3. If `$XDG_RUNTIME_DIR` is set: use `$XDG_RUNTIME_DIR/party-cli/tracker-<namespace>/tracker.sock`; pid/log/alive/fault files are siblings in that namespace directory.
4. Else: use `<stateRoot>/tracker.sock`; pid/log/alive/fault files are siblings in the state root.
5. If the chosen socket path exceeds 100 bytes, fall back to `/tmp/party-cli-<uid>/tracker-<namespace>/tracker.sock` (directory mode 0700) to stay below the BSD `sun_path` limit even when `PARTY_STATE_ROOT` is a long temp path.

Create the socket directory with mode 0700 and the socket with mode 0600. Validate peer UID (`SO_PEERCRED` on Linux, `getpeereid` on macOS) before accepting hello.

**Client → daemon: hello**
```json
{"type":"hello","protocol":1,"client_id":"<uuid>","origin_session":"party-1741230000","width":120,"height":40}
```

**Daemon → client: welcome**
```json
{"type":"welcome","protocol":1,"daemon_pid":12345,"snapshot_seq":42,"namespace":"a1b2c3d4e5f6"}
```

**Daemon → client: reject (version skew)**
```json
{"type":"reject","reason":"protocol_version","daemon_pid":12345,"supported_min":1,"supported_max":1,"got":2}
```
If `supported_max < got`, the client is newer than the daemon and enters replacement election. If the client is older than the daemon's supported range, it falls back to embedded mode and writes a one-liner to stderr + `<socket_dir>/tracker.fault`.

**Daemon → client: snapshot**
```json
{"type":"snapshot","seq":42,"sessions":[...SessionRowDTO...],"selected":"party-1741230000","observed_at":"2026-05-21T12:00:00Z","status":""}
```
`SessionRowDTO` is `tui.SessionRow` converted to snake_case JSON fields minus `is_current`; `CurrentSessionDetail` is never on the wire.

**Client → daemon: events**
- `{"type":"key","key":"j"}` — shared-cursor navigation only (`j`/`k`; add top/bottom keys only if embedded mode gets matching keybindings and tests)
- `{"type":"resize","width":120,"height":40}` — on `tea.WindowSizeMsg`; daemon updates the connection-pinned geometry used by later Spawn/Continue actions
- `{"type":"observed","seq":42,"session_id":"party-1741230000","at":"2026-05-21T12:00:00.500Z"}` — sent after each snapshot render; also acts as the snapshot ack for `last_acked_seq`
- `{"type":"action","id":"<uuid>","kind":"spawn","target_session":"party-master","master_session":"party-master","next_attach_session":"","text":"worker title"}` — modal actions. Fields unused by a kind are empty. Origin session and geometry are intentionally absent; daemon uses the values pinned to this connection at hello/resize time. Delete-current-session sets `next_attach_session` to the client-captured survivor.
- `{"type":"manifest_request","id":"<uuid>","session":"party-1741230001"}`
- `{"type":"stats_request","id":"<uuid>"}`
- `{"type":"bye"}`

**Daemon → client: responses**
- `{"type":"action_result","id":"<uuid>","ok":true,"err":""}`
- `{"type":"manifest_response","id":"<uuid>","session":"...","json":"<escaped>"}`
- `{"type":"stats_response","id":"<uuid>","uptime_ms":1234,"client_count":25,"last_snapshot_at":"2026-05-21T12:00:00Z","last_error":"","snapshot_count":99,"fsnotify_event_count":120}`
- `{"type":"error","detail":"..."}` — out-of-band errors

Per Agent 3 finding §2: only `Attach`, `Continue`, `Spawn`, and Delete-current need origin geometry/context. `Relay`/`Broadcast`/`ManifestJSON` do not. Origin context is connection-pinned from hello/latest resize; if a future protocol version adds origin fields for diagnostics, the daemon must reject any value that differs from the pinned connection metadata.

### Election / spawn-on-demand

Runtime files live beside the socket:
- `<socket_dir>/tracker.spawn.lock` — short-lived client election lock
- `<socket_dir>/tracker.pid` — daemon PID file and daemon lifetime flock
- `<socket_dir>/tracker.log`, `tracker.alive`, `tracker.fault`

Use **separate locks** for spawn election and daemon ownership. A client must never hold the same flock the child daemon needs to acquire, or the spawned daemon exits as "another daemon owns it" before it can bind.

**Client connect flow:**
1. Check `exec.LookPath("party-cli")`. If absent, skip election entirely → immediate embedded fallback with a one-line stderr. This prevents `setsid + fork(go run .)` from `config/resolve.go:21-28` (the `go run` compile alone takes seconds and blows past the dial-backoff budget across all clients simultaneously).
2. `net.Dial("unix", socketPath)`. On success, send hello.
   - `welcome` → proceed.
   - `reject protocol_version` where daemon `supported_max < client protocol` → replacement election.
   - any other reject → embedded fallback + fault marker.
3. On `ENOENT` or `ECONNREFUSED`: enter spawn election.
4. Spawn election: open `tracker.spawn.lock` with `O_CREATE|O_RDWR`, attempt `LOCK_EX|LOCK_NB`.
   - **Lock acquired:** re-dial once (another client may have won while we opened the lock). If still dead, unlink a stale socket only after `Dial` fails, then fork `party-cli tracker daemon --socket <path>` with `setsid`, redirect stdout/stderr to `<socket_dir>/tracker.log` (append, daemon rotates at 10MB). Wait for daemon to bind socket (poll `Dial` with 50ms backoff, max 2s). Release the spawn lock. The client never writes `tracker.pid`.
   - **Lock contested:** another client is electing. Wait up to 2s polling `Dial`.
5. After election attempt, retry `Dial` with backoff 50/100/200/400/800 ms (5 attempts). On final failure, fall back to embedded mode, write fault marker.

**Replacement election for upgrades:**
- Acquire `tracker.spawn.lock`, re-dial + hello to confirm the daemon is still incompatible, read PID from the reject or `tracker.pid`, verify it belongs to our UID, send `SIGTERM`, wait up to 2s for socket close, then follow the normal spawn path.
- If replacement fails, new clients fall back to embedded with a fault marker; old clients connected to the new daemon receive reject and fall back.

**Daemon startup:**
1. Open `tracker.pid`, acquire `LOCK_EX|LOCK_NB`, and keep it held for the daemon lifetime. On failure, exit code 2 (another daemon owns it).
2. Try `net.Listen("unix", socketPath)`. On `EADDRINUSE`, try to `Dial` — if Dial succeeds, exit (race lost). If Dial fails, `unlink` socket + retry once.
3. Write own PID + newline to `tracker.pid` after the listener is bound.
4. Start fsnotify watcher, accept loop, snapshot dispatcher.

**Watchdog:**
- Daemon touches `<socket_dir>/tracker.alive` every 5s.
- Clients monitor `tracker.alive` mtime. If > 15s stale: treat daemon as dead, close socket, re-enter election.

### fsnotify event handling

Watch the resolved state root, not a hardcoded `~/.party-state/`.

**Recursive watch (Linux + macOS):**
- On startup: walk the state root once, add a watch for the root and every existing session subdir.
- On `fsnotify.Create` for a subdir: add watch immediately, then list contents (in case `state.json` was created between the dir-create and watch-add).
- On subdir remove/rename/delete-self: remove the watch if fsnotify still has it.
- Use fsnotify's portable `Op` bits (`Create`, `Write`, `Rename`, `Remove`) in code and tests; do not assert Linux-only `IN_*` names.

**Event filter** (Agent 2 finding §1, §2, "Red flags" §3):
- `<session-dir>/state.json` create/write/rename/remove → recompute snapshot
- `<state-root>/<party-id>.json` create/write/rename/remove → recompute snapshot (manifest changed or deleted)
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
5. Receive welcome or reject; reject routes through replacement/fallback rules above.
6. Goroutine reads daemon → channel of decoded messages. Snapshot → project client-local current/header/cursor state → `tea.Cmd` → re-render. Action result → match by RPC id → resolve pending future.
7. Goroutine writes channel → daemon (serialized JSON + newline).
8. Spinner + blink local (`bubbles/spinner` keeps current cadence).
9. `tea.WindowSizeMsg` → forward `resize` to daemon.
10. Daemon socket EOF or `tracker.alive` stale: close, re-elect. If election fails N times: fall back to embedded.

The existing `TrackerModel` (`internal/tui/tracker.go:89`) is refactored in two steps: Phase 1 extracts snapshot computation from `NewLiveSessionFetcher` (`internal/tui/tracker_actions.go:140-181`) into `internal/tui/snapshot.go` as a neutral builder plus embedded projection wrapper; Phase 2 makes render funcs (`viewSessions`, `renderStatusBar`, `renderSessionRow`, etc.) pure functions taking `TrackerSnapshot + RenderState`. Client model holds the daemon snapshot + client-local `RenderState`, marks `IsCurrent` locally, and calls renderers directly. Fallback must call an explicit embedded launcher that ignores `PARTY_TRACKER_MODE` so `party-cli tracker client` cannot recursively launch another client.

### Origin-pane semantics

Per Agent 3 finding §1 and "Red flags" §1, §2, §3:

Action origin is **connection-pinned**, not trusted per RPC. The daemon records `origin_session` from the hello frame after peer-UID validation, updates width/height from resize frames, and passes only those pinned values into action execution. Server-side:

- **Attach** wraps the existing `tmux run-shell -t <pinned origin_session> "switch-client -t <target>"` pattern.
- **Continue** and **Spawn** use the connection's latest pinned width/height to override `tmux.Client.currentClientSize` (`internal/tmux/lifecycle.go:74-99`). The current function reads `TMUX_PANE` from process env — fine for embedded mode, useless from a detached daemon. Refactor with explicit option structs: `StartOpts` and `SpawnOpts` gain `ClientWidth`/`ClientHeight`; `ContinueWithOpts(ctx, sessionID, ContinueOpts)` is added while existing `Continue(ctx, sessionID)` delegates with zero opts; tmux gets `NewSessionWithSize` or `NewSessionOpts` while `NewSession` stays as the compatibility wrapper.
- **Delete** RPC carries `target_session`, `master_session` (for worker/ghost cleanup), and, when `target_session == pinned origin_session`, the client-captured `next_attach_session`. The client must capture `next_attach_session` *at keypress time* (when cursor + snapshot are consistent), before dispatching Delete. Re-resolving `next` after Delete returns is incorrect — a `j` keypress between Delete-issued and Delete-returned would move the cursor and produce the wrong Attach target. The daemon performs the delete-current handoff as one server-side action (switch the origin client to the captured survivor, then kill/delete the target) before replying; otherwise the tmux session being killed can terminate the client before it sends a follow-up Attach RPC.

### Cursor model

Global cursor, per Agent 1 finding §4:

- `j`/`k` keypresses move the daemon-owned `selected SessionID`. Daemon broadcasts updated `selected` in the next snapshot to all clients. Do not add `g`/`G` in daemon mode unless embedded mode gets the same keybindings and tests in the same phase.
- Mode (relay/broadcast/spawn) is client-local. Entering relay mode in pane A does not change pane B's view.
- `Enter` (in normal mode) sends `action attach target_session=selected`. The target is the global selection; the origin is the requesting connection's pinned `origin_session`.

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
    if trackerLaunchMode(defaultTrackerMode) != "daemon" {
        return base, nil
    }
    return base + " tracker client", nil
}
```

`trackerLaunchMode` resolves `PARTY_TRACKER_MODE` first, then `[tracker] mode` in the existing user config (`~/.config/party-cli/config.toml` / `$XDG_CONFIG_HOME/party-cli/config.toml`), then the compiled default. The compiled default remains `embedded` through Phase 4 and flips to `daemon` only in Phase 5. All three spawn sites call the new resolver. `cmd/root.go:73-75` (the no-args TUI fallback) stays — shell invocations of `party-cli` still launch embedded mode unless the resolved mode is daemon.

**Runtime mode flips.** The tracker *process itself* (in `cmd/tracker.go`) also reads the same mode resolver at startup. Effect: toggling the env/config in a shell + `tmux respawn-pane -t <tracker>` becomes a valid runtime flip path. Without this, the only way to flip mode mid-session is "delete and recreate the session" — too coarse to be useful for fallback-on-daemon-problem. Two reads, both cheap; the runtime read is what makes the fallback story actually usable.

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
- Structured logging via `log/slog`. JSON output. Fields: `client_id`, `origin_session`, `protocol`, `namespace`, `seq`, `duration_ms`, `err`.
- `party-cli tracker status` subcommand: dials daemon, sends `stats_request`, prints `{uptime, client_count, last_snapshot_at, last_error, snapshot_count, fsnotify_event_count}`, exits. Useful for diagnosing whether the daemon is alive without attaching a client.

## Sequenced rollout

### Phase 1 — Scaffolding (5d)

**Files to create:**
- `internal/tracker/daemon/daemon.go` — `Daemon` struct, `Run(ctx)` constructor
- `internal/tracker/daemon/snapshot.go` — fsnotify aggregator with debounce + recursive watch; consumes the neutral TUI snapshot seam and broadcasts client-neutral snapshots
- `internal/tracker/daemon/server.go` — UDS listener, peer-UID validation, per-client accept goroutine, dispatch
- `internal/tracker/daemon/election.go` — split-lock election + spawn-on-demand
- `internal/tracker/daemon/socketpath.go` — state-root namespace + path-length fallback
- `internal/tracker/daemon/protocol.go` — DTO wire types, explicit JSON tags, version constants, 1 MiB frame limit
- `internal/tracker/daemon/cursor.go` — global cursor + observation coalescer
- `internal/tracker/daemon/watchdog.go` — alive file touch loop
- `internal/tracker/testharness/inproc.go`
- `internal/tracker/testharness/uds.go`
- `internal/tracker/testharness/fakes.go`
- `cmd/tracker.go` — parent cobra command + `daemon`, `client`, `status` subcommands (matches `party-cli hooks {install,status,uninstall}` pattern in `cmd/hooks.go`)

**Files to modify:**
- `go.mod` — add `github.com/fsnotify/fsnotify` (and promote `golang.org/x/sys` if peer-credential helpers need a direct dependency)
- `cmd/root.go:78-99` — register `newTrackerCmd(o.store, o.client, o.repoRoot)`
- `internal/tui/tracker_actions.go:140-181` — extract the hardcoded `current SessionInfo` projection from `NewLiveSessionFetcher` into a neutral builder (new `internal/tui/snapshot.go` is acceptable); keep `NewLiveSessionFetcher` as the embedded wrapper that applies `CurrentSessionDetail` and `IsCurrent` locally

**Tests:**
- Neutral snapshot seam test: daemon-facing builder returns ordered rows with `IsCurrent == false` for every row and zero `CurrentSessionDetail`; embedded `NewLiveSessionFetcher(current)` still marks exactly the current row and fills the header detail
- Protocol DTO test: marshalled daemon snapshot contains no `current` object and no `is_current` field
- Snapshot recompute fires ≥1 time after a burst of `state.json` writes settles. Phrased as "at least one recompute within 100ms of the last write," not "one recompute per write" — macOS fsnotify coalesces aggressively and would otherwise flake
- Manifest remove and `state.json` remove both recompute so deleted sessions disappear
- `.tmp`/`.lock`/`.jsonl*` events are ignored
- Subdir create triggers nested watch
- Socket path namespace differs for two `PARTY_STATE_ROOT` values even when `XDG_RUNTIME_DIR` is shared
- Election: three clients racing → exactly one daemon; the spawn lock never prevents the daemon from acquiring its lifetime pid lock
- Stale socket from killed daemon → next election succeeds after unlink-rebind
- tmux liveness poll flips a session to `stopped` within 4s of `kill-session`

### Phase 2 — Client mode (4d)

**Files to create:**
- `internal/tracker/client/conn.go` — UDS dialer with election trigger on connect failure
- `internal/tracker/client/reconnect.go` — backoff, fault marker, embedded fallback
- `internal/tui/clientmodel.go` — Bubble Tea wrapper consuming snapshot channel

**Files to modify:**
- `internal/tui/tracker.go` — split `applySnapshot`/`updateSnippetActivity`/`preserveLastSnippets`/`markSessionObserved` from the rendering path. Snapshot-apply logic moves daemon-side; render funcs become pure and accept client-local `RenderState`
- `internal/tui/app.go:17-24` — `Launch()` reads tracker mode through the env/config/default resolver. Default `embedded` (Phase 2); switches to `daemon` at Phase 5. Add an explicit embedded launcher for fallback that ignores the mode resolver
- `internal/agent/config.go` and `cmd/config.go` — add `[tracker] mode = "embedded"|"daemon"` to the existing user config surface and config rendering
- `cmd/tracker.go` — `client` subcommand wires up the client model; also has the detach-cursor toggle (`c` keybinding) per the Cursor model design section

**Tests:**
- Client connects, receives 3 snapshots, renders the third
- Two clients connected to the same daemon mark different `IsCurrent` rows and render different headers from the same snapshot payload
- Relay/Broadcast/Spawn gating follows each client's origin row, not the global cursor
- Spinner ticks do not trigger any daemon RPCs
- `tea.WindowSizeMsg` produces one `resize` event on the wire
- Daemon kills the connection → client schedules reconnect
- 5 reconnect failures → falls back to embedded model without recursively launching `tracker client`
- `PARTY_TRACKER_MODE` overrides `[tracker] mode`, and Phase 2 default remains embedded

### Phase 3 — Action RPC (4d)

**Files to create:**
- `internal/tracker/daemon/actions.go` — server-side `TrackerActions` with origin context
- `internal/tracker/client/actions.go` — client-side stub returning futures

**Files to modify:**
- `internal/tui/tracker_actions.go` — split `liveTrackerActions` into daemon-side (with full Service deps) and client-stub (RPC-only)
- `internal/session/service.go` — define `ContinueOpts`; keep `Continue(ctx, id)` as a wrapper around `ContinueWithOpts(ctx, id, ContinueOpts{})`
- `internal/session/start.go`, `spawn.go`, and `continue.go` — `StartOpts`/`SpawnOpts`/`ContinueOpts` accept `ClientWidth`, `ClientHeight`; pass overrides into tmux session creation
- `internal/tmux/lifecycle.go:74-99` — add `NewSessionWithSize`/`NewSessionOpts`; `currentClientSize` uses the explicit override when non-zero and otherwise preserves the `TMUX_PANE` probe

**Tests:**
- Attach RPC routes through `run-shell -t <pinned origin_session>` from the connection metadata; mock asserts the exact tmux args and a mismatched/forged per-RPC origin field is rejected if present
- Continue with pinned `ClientWidth=200`/`Height=60` skips the `TMUX_PANE` probe
- Spawn with pinned geometry sizes the new worker to the requesting client; spawn with no override falls back to tmux defaults
- Delete-current RPC includes captured `next_attach_session`; daemon switches to that target and deletes the original session even if cursor moves before Delete returns
- Delete ghost worker RPC carries `master_session` and still removes the orphan from the master's worker list
- Relay round-trip: client sends action, daemon executes `message.Service.Relay`, client receives action_result
- ManifestJSON request/response carries the full JSON

### Phase 4 — Lifecycle hardening (3d)

**Files to create:**
- `internal/tracker/daemon/shutdown.go` — SIGTERM/SIGINT handler, drain clients with `bye`
- `internal/tracker/daemon/version.go` — handshake helpers

**Files to modify:**
- `internal/tracker/client/conn.go` — read welcome/reject, route to replacement election or fallback on reject
- `internal/tracker/daemon/watchdog.go` — touch frequency, alive-file ownership
- `internal/tracker/daemon/protocol.go` — stats response + version-range helpers

**Tests:**
- Daemon `SIGKILL` mid-snapshot → client reconnects via election; new daemon serves next snapshot within 2s
- Daemon `SIGTERM` → drains clients with `bye`; clients reconnect; no `EPIPE` panic
- New client sees old daemon reject (`supported_max < got`) → replacement election starts a compatible daemon; old client sees new daemon reject → embedded fallback + fault file
- Protocol mismatch where the client is too old → client falls back; fault file written; embedded mode renders correctly
- Concurrent spawn-on-demand from 3 clients → exactly one daemon
- Watchdog alive-file stale > 15s → clients reset connection
- `party-cli tracker status` returns stats over `stats_request` without starting a Bubble Tea client

### Phase 5 — Dogfood + flip default (2 calendar weeks)

- Use daemon mode personally for 1 week with explicit `PARTY_TRACKER_MODE=daemon` before flipping the compiled default.
- Flip the compiled `defaultTrackerMode` from `embedded` to `daemon`; do not mutate user config during install. Allow opt-out via `PARTY_TRACKER_MODE=embedded` or `[tracker] mode = "embedded"` in `~/.config/party-cli/config.toml`.
- Write `docs/projects/tracker-daemon/README.md`: how to debug (`tracker status`, log location, fault file), how to disable/roll back, how to restart (manual stop/start now; `tracker restart` remains a Phase 6 candidate).
- Update top-level `README.md` to mention the daemon as the default tracker substrate and document the embedded fallback.
- Cross-link in commit summary: this PR extends `hook-state-tracker/PLAN.md` with a consumer-side aggregator; the hook-ingestion path is unchanged.

### Phase 6 — Remove embedded mode (1d, after one release of soak)

- Delete `PARTY_TRACKER_MODE=embedded` / `[tracker] mode = "embedded"` branches.
- Delete `tui.Launch` embedded path; `cmd/root.go:73-75` instead bootstraps a `tracker client` invocation transparently.
- Delete `liveTrackerActions` direct-call code now unused.
- Bump protocol version, simplify handshake (no fallback path).

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Reviewer mis-reads this as reversing the anti-daemon principle from `hook-state-tracker/PLAN.md:600-604` | Frame as additive: this is a consumer-side aggregator for the same file-based state contract. The hook-ingestion model (invoke-and-exit, atomic-rename, flock) is unchanged. Make this explicit in the PR description, the "Why now" section header, and Phase 5 commit summary |
| 2 | UDS socket lifecycle bugs (stale sockets, election races, restart corruption) | Split spawn lock vs daemon lifetime pid lock; try-connect-then-unlink-rebind protocol; concurrent-spawn integration test in Phase 1 |
| 3 | Daemon crash leaves clients stuck | Watchdog `tracker.alive` file with 15s stale threshold; client reconnects with backoff; fallback to embedded after N failures |
| 4 | Version skew during upgrade | Protocol version in hello; daemon rejects incompatible clients with explicit version range; newer clients run replacement election, older clients fall back to embedded |
| 5 | `currentClientSize` silently degrades for daemon-spawned sessions (Agent 3 "Red flags" §1) | Pass `ClientWidth`/`ClientHeight` in every Spawn/Continue RPC; tmux session creation accepts an explicit size override; integration test asserts new session is sized to requester |
| 6 | New attack surface: UDS socket | State-root-scoped per-user socket, namespace directory mode 0700, socket mode 0600; validate peer UID via `SO_PEERCRED` (Linux) / `getpeereid` (macOS); treat protocol input as untrusted; bound message size at 1 MB |
| 7 | No multi-process test harness exists (Agent 5 "Red flags" §1) | Build `internal/tracker/testharness/` as a Phase 1 deliverable, mandatory for Phases 2–4 |
| 8 | fsnotify event noise from `.tmp`/`.lock`/`.jsonl*` files (Agent 2 "Red flags" §1, §3, §4) | Filter by basename; 50ms debounce; portable `fsnotify.Op` tests in `snapshot_test.go` |
| 9 | tmux liveness still requires polling because state files linger after `kill-session` (Agent 2 §5) | Keep 3s `ListSessions` poll daemon-side — but once per daemon, not per pane. Net cost drops ~N× |
| 10 | Picker (`cmd/picker.go`) and `cmd/sessions.go` JSON bypass the daemon (Agent 4 §7, §9) | Out of scope. They continue reading state files directly. Daemon is purely additive |
| 11 | Cold-start `go run .` fallback (`config/resolve.go:21-28`) blows past the 1.55 s dial-backoff budget in daemon mode (multi-second Go compile alone exhausts it across all clients simultaneously) | Client checks `exec.LookPath("party-cli")` **before** entering election (step 1 of Client connect flow). If absent → skip election → immediate embedded fallback with one-line stderr. Never trigger `setsid + fork(go run .)` from the election path |
| 12 | Snapshot fan-out blocking on slow client; redundant broadcasts under sustained hook bursts | Bounded per-client send channel (capacity 4); on overflow, drop oldest pending frame and enqueue the latest; daemon goroutine never blocks. Additionally: hash the serialized snapshot before broadcasting; if identical to last broadcast, skip the fan-out entirely. Under tool-storm (~20 Hz debounce ticks) this saves ~25 clients × ~5 KB × 20 Hz ≈ 2.5 MB/s on UDS plus matching client-side decode + render cost |
| 13 | `markSessionObserved` ownership confusion (daemon vs. client) | Daemon owns the write; clients send `observed` events with snapshot seq; daemon coalesces by (session_id, tick) before one write per session per refresh |
| 14 | Pane SIGHUP on tmux session-close doesn't notify daemon of dead clients (Agent 4 §5) | Daemon detects via socket EOF + periodic `tmux list-clients` reconciliation; clients whose origin session is gone are reaped |
| 15 | Fallback to embedded silently hides daemon failures | When fallback triggers, write one-line stderr to client pane + fault file at `<socket_dir>/tracker.fault` with timestamp + reason |
| 16 | Conflict with in-flight `party-cli-refactor` or `pi-third-agent` | Coordinate via PLAN status updates; daemon scaffolding (Phase 1) is additive — touches no files those plans modify. Phase 3 touches `internal/session/service.go`, which `party-cli-refactor` Phase 4 (tasks M6 + M7, Start/Continue launch unification) also touches; sequence: this plan's Phase 3 starts only after `party-cli-refactor` Phase 4 lands |
| 17 | External task-summary files and resume IDs (`/tmp/<party-id>/`) live outside the watched root (Agent 2 "Red flags" §7) | The tracker no longer consumes external task-summary files; resume IDs are only read at session-start, not in steady-state snapshots, so no extra watch is needed |
| 18 | `mode == trackerModeManifest` does synchronous `actions.ManifestJSON` on keypress (Agent 1 "Red flags" §6) | Becomes RPC `manifest_request` → `manifest_response`. Client shows spinner on `m` press until response arrives |
| 19 | Cursor + `current.ID` coupling: relay/broadcast gating uses *client's* session, not the highlighted row (Agent 1 §4, "Red flags" §2) | Mode is client-local. Daemon broadcasts the global cursor; each client derives its own current row from connection-pinned `origin_session` and gates relay/broadcast/spawn locally |
| 20 | Delete-current kills the client before it can send a follow-up Attach, or cursor moves and Attach lands on wrong target | Client captures the resolved `next` target at keypress time and includes it in the Delete RPC. Daemon performs switch-to-next + delete as one action using the connection-pinned origin. Test delays Delete while issuing `j`; assert Attach target matches captured `next`, not post-`j` selection |
| 21 | Global snapshot accidentally leaks per-client fields (`Current`, `IsCurrent`) so panes render another pane as current | Phase 1 extracts a neutral snapshot seam from `NewLiveSessionFetcher`; wire DTO omits per-client fields; client projection sets `IsCurrent` and header locally; tests assert daemon snapshots/DTOs have no `Current`/`IsCurrent` and two clients render different current rows from one snapshot |
| 22 | Forged action frame claims another pane as `origin_session` to attach/delete/spawn from the wrong place | Origin session and geometry are connection-pinned from hello/latest resize after peer-UID validation. Action frames do not carry origin fields; if future/legacy frames include them, daemon rejects mismatches before dispatching actions |
| 23 | Multiple `PARTY_STATE_ROOT` values collide on one `$XDG_RUNTIME_DIR` socket | Socket namespace includes a hash of the resolved state root; tests assert two roots get separate sockets/daemons |

## Rollback / migration

- **No data migration.** Manifests (`<state_root>/<party-id>.json`) and hook state (`<state_root>/<party-id>/state.json`) stay in the existing file formats. The daemon only reads them and writes the same `SeenAt`/done→idle updates through `state.UpdateSessionState`.
- **Rollback before Phase 6:** set `PARTY_TRACKER_MODE=embedded` or `[tracker] mode = "embedded"`, respawn tracker panes, and stop the daemon with `SIGTERM` using `<socket_dir>/tracker.pid`. Stale socket cleanup handles leftover socket files on the next client start.
- **Bad Phase 5 default flip:** revert `defaultTrackerMode` to `embedded` and ship; no state cleanup is required. Existing daemon processes can be left to exit when idle or stopped manually.
- **Protocol migration:** every incompatible wire change bumps `protocol`. New clients replace older daemons only after a version reject and spawn-lock election; older clients fall back to embedded rather than speaking an unknown protocol.
- **Phase 6 removal gate:** do not remove embedded mode until one release has shipped with the rollback path documented and exercised.

## Deferred to implementation time

- Whether to switch the wire format from line-delimited JSON to length-prefixed JSON or protobuf — measure first; JSON is fine until profiling shows otherwise
- Exact watchdog cadence beyond the 5s baseline
- Whether to expose `party-cli tracker inspect` (full internal state dump) in addition to `status`
- Whether to expose human-friendly daemon namespace names beyond the state-root hash used in socket paths
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
