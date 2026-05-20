# Hook-State Tracker

> **Goal:** Replace the snippet-hash heuristic in `tools/party-cli/internal/sessionactivity` with authoritative state pushed by Claude Code / Codex / Pi hooks. Tracker shows `working | blocked | done | idle | starting | stopped | unknown` per pane, sourced from a per-session `state.json` that hooks write to. Snippets become structured Activity strings from those same hook events.
>
> **Approach:** File-based state hand-off (hooks write a tiny JSON via `party-cli hook ...`, tracker reads it). Auto-install hooks during `install.sh` with `--no-hooks` opt-out. Delete the FNV-window detector and the tracker's `tmux capture-pane` snippet pipeline at the end of Phase 2 — no fallback, hook-driven only. The shared `internal/tmux` capture helpers are NOT deleted: they are still used by `party-cli read` (`internal/message/message.go`) and picker previews.
>
> **Path conventions:** Bare paths in this document (`internal/...`, `cmd/...`) refer to the Go module rooted at `tools/party-cli/`. The full path is `tools/party-cli/internal/...` on disk. Pi-side paths under `pi/agent/...` are absolute from the repo root.

## Phases

| Phase | Deliverable | Effort | Depends on | Status |
|---|---|---|---|---|
| 1 | Plumbing: `state.json` schema, `party-cli hook` subcommand, `party-cli hooks {install,status,uninstall}`, `install.sh` auto-install with `--no-hooks` | 2–3 days | — | ⏳ Planned |
| 2 | Cut over: tracker reads `state.json`, 4-state dot rendering, master roll-up, `done → idle` bookkeeping, Activity-driven snippets. **Delete** `internal/sessionactivity` detector + the terminal-capture snippet pipeline | 2–3 days | Phase 1 | ⏳ Planned |
| 3 | `blocked` polish: verify Claude `Notification` semantics, map Codex equivalent, optional `party-cli state log` debug subcommand | 1–2 days | Phase 2 | ⏳ Planned |

**Total budget:** ~5–8 working days.

Phase 4 (`PARTY_ENV` + SKILL.md groundwork enabled by reliable `blocked`) is **out of scope** for this plan and tracked separately.

## Definition of Done

- [ ] `party-cli hook <agent> <action>` writes `state.json` + `state.jsonl` in <20ms p99
- [ ] `party-cli hooks install` is idempotent, tagged, and reversible for Claude + Codex + Pi
- [ ] `install.sh` auto-installs hooks by default; `--no-hooks` skips; non-TTY skips
- [ ] Tracker dots reflect 7 states with correct color/animation per agent
- [ ] Master row rolls up worst worker state with a badge
- [ ] `done → idle` transitions when the tracker has observed the session post-`done`
- [ ] Subagent events (Claude `agent_id` populated) do not flip the parent pane to `done`/`idle`
- [ ] Snippets sourced from `PaneState.Activity` show tool / user-prompt / final-message context across a turn
- [ ] `internal/sessionactivity` FNV-window detector deleted
- [ ] Tracker's `tmux capture-pane` snippet path (the `captureRoleSnippet` branch in `internal/tui/tracker_actions.go`) deleted. The shared `internal/tmux` capture helpers stay (they are used by `internal/message/message.go` and picker previews — see Risk #4 in the scope-clarification table).
- [ ] `SessionRow.PrimaryActive`, `PrimaryActiveOverride`, the `ActiveOverride *bool` carve-out: deleted
- [ ] Pi sidecar (`pi/agent/extensions/activity-sidecar.ts`) updated to call `party-cli hook pi <action>` for state. Non-state fields that `internal/message/message.go` and `internal/session/pi_resume.go` consume (`session_file`, `pi_session_id`, `recent[]`) are preserved — see "Pi sidecar contract" below.
- [ ] Tests cover hook command, installer idempotency, state→dot rendering, master roll-up, done→idle, subagent suppression
- [ ] No regressions in existing Claude / Codex / Pi session start, continue, prune, read flows

---

## Design

### State files (per session)

```
~/.party-state/
  party-abc123.json                  # existing manifest, unchanged
  party-abc123/
    messages/                        # existing inbox
    state.json                       # authoritative current state; flock'd, atomic write
    state.jsonl                      # append-only log; capped at 1MB, rotates to .1
```

`state.json` schema (`internal/state/hookstate.go`):

```go
type SessionState struct {
    SessionID string                  `json:"session_id"`
    Version   int                     `json:"version"`     // = 1
    Panes     map[string]PaneState    `json:"panes"`       // key: role ("primary"|"companion")
    SeenAt    time.Time               `json:"seen_at"`     // tracker bookkeeping
}

type PaneState struct {
    Role      string    `json:"role"`
    Agent     string    `json:"agent"`
    State     string    `json:"state"`      // working|blocked|done|idle|starting|stopped|unknown
    Activity  string    `json:"activity"`   // structured snippet ("Edit foo.go", "Bash: go test ./...", "You: ...", "Said: ...")
    Tool      string    `json:"tool,omitempty"`
    Seq       int64     `json:"seq"`        // best-effort monotonic; see note below
    LastEvent time.Time `json:"last_event"`
    LastKind  string    `json:"last_kind"`  // event kind that produced LastEvent — used by renderer for "…" suffix

    // Pi-specific carry-through (populated only when Agent == "pi"). These
    // are not consumed by the tracker dot/snippet renderer; they exist so
    // `internal/message/message.go` (rich `party-cli read` output) and
    // `internal/session/pi_resume.go` keep working after the legacy
    // pi-activity.json sidecar is removed.
    Recent      []string `json:"recent,omitempty"`
    SessionFile string   `json:"session_file,omitempty"`
    PiSessionID string   `json:"pi_session_id,omitempty"`
}
```

Single read for the tracker. No log scanning on the hot path.

**Seq is best-effort.** `time.Now().UnixNano()` is wall-clock — not monotonic across processes, not even monotonic within one process if the clock steps backward. We use it for tie-breaking in `state.jsonl` only; no ordering invariant depends on it. The locked read-modify-write API ("done → idle mechanics" below) is what protects against lost updates, not `Seq`. Don't introduce a daemon to broker a real monotonic source — accept best-effort.

### Hook entry point

One subcommand owns all hook semantics, regardless of which agent's shell script invokes it:

```
party-cli hook <agent> <action> [--session <id>]
```

- Reads stdin (agent-native hook payload JSON; may be empty).
- Falls back to `$PARTY_SESSION` if `--session` omitted.
- No-ops with exit 0 if `$PARTY_SESSION` is unset (so user shells with hooks installed are unaffected outside party sessions).
- Writes to `state.jsonl` (append) and `state.json` (flock + atomic rename).
- Target latency: <20ms p99. Asserted by `cmd/hook_test.go` benchmark.
- All paths gated by `state.IsValidPartyID` — `$PARTY_SESSION` is rejected (exit 0, no-op) if it doesn't match the `party-[a-zA-Z0-9_-]+` shape. `$PARTY_SESSION` is never used unsanitised as a path component.

#### Action → state mapping

| Action arg | State written | Notes |
|---|---|---|
| `starting` | `starting` | from SessionStart hooks |
| `working`  | `working`  | generic working signal (Codex / Pi) |
| `tool_start` | `working` | sets `Tool` field; conditional state write (see below) |
| `tool_end` | `working`  | clears `Tool` field; appends to log only |
| `done`     | `done`     | from Stop hook |
| `blocked`  | `blocked`  | from Notification hook |
| `stopped`  | `stopped`  | from SessionEnd / agent process exit |

**Subagent rule (per-agent, not generic).** `agent_id` is Claude-specific; Codex's Stop payload has no equivalent field (`codex-rs/hooks/src/lib.rs` ~480–495). Spell out per agent in `cmd/hook.go`:
  - **Claude:** if stdin payload contains non-empty `agent_id` (subagent), suppress `done`/`idle`; forward `blocked`; do not flip parent back to `working` on subagent tool events.
  - **Codex:** no subagent dimension on Stop — treat every Stop event as the top-level turn ending. If/when Codex grows a subagent signal, revisit.
  - **Pi:** sidecar emits one stream per process and does not nest; no suppression rule needed.

**Hot-path optimisation (state.json must reflect renderer-visible fields).**

`tool_start` / `tool_end` always append to `state.jsonl`. They re-write `state.json` whenever ANY field the renderer reads has changed: `State`, `Activity`, `Tool`, `LastKind`, or `LastEvent`. (`LastEvent` is updated on every event, so practically every `tool_start` flushes once.) The only writes the optimisation skips are no-ops where all five renderer-visible fields are byte-identical to the snapshot on disk — those are rare in practice and not worth the complexity of conditional writes that gate on a subset of fields.

Concretely: the original "only on State change" rule is rejected. Under that rule, while a pane is already `working`, subsequent `tool_start` events would never reach the tracker — Activity, Tool, LastKind, LastEvent all stale, and the `…` streaming-prose suffix (which keys off `LastKind ∈ {PostToolUse, UserPromptSubmit}`) would never flip on or off correctly. The renderer's correctness wins over the flock-dance microbenchmark; the benchmark gate in Phase 1 enforces that the flushy version still hits <20ms p99.

#### Action → Activity mapping

| Hook event | Activity becomes |
|---|---|
| `SessionStart` | `"starting…"` |
| `UserPromptSubmit` | `"You: " + firstline(prompt)[:60]` — sticky until next event. **State change:** also sets `State = working`, `LastKind = UserPromptSubmit`. See "Turn-start state" below. |
| `PreToolUse:Edit` / `Write` | `"Edit " + basename(file_path)` |
| `PreToolUse:Read` | `"Read " + basename(file_path)` |
| `PreToolUse:Bash` | `"Bash: " + firstline(command)[:60]` |
| `PreToolUse:Task` | `"Agent: " + description[:60]` |
| `PreToolUse:Grep` / `Glob` | `"Search: " + pattern[:60]` |
| `PostToolUse` | *unchanged* (don't clobber the tool snippet) |
| `Notification` | `"Notification: " + text[:60]` |
| `Stop` | `"Said: " + firstline(final_assistant_text)[:60]` — read from `transcript_path` in payload |
| `SubagentStop` | `"Subagent: " + firstline(result)[:60]` |
| Codex equivalents | analogous mapping — degraded gracefully where Codex's hook surface is thinner |
| Pi sidecar | `"Prompt: " + first_user_line[:60]` / `"Replying…"` |

**Privacy:** truncate at first newline + 60 chars; strip leading `[A-Z_]+=\S+` env-var assignments. Not worse than today (terminal scrape sees the same line); buys us a chance to add scrubbing we don't have now.

#### Turn-start state

`UserPromptSubmit` must set `State = working` (not just Activity). Otherwise a prompt that the agent answers without tool calls — common for short questions, status checks, or any pure-text reply — stays in whatever the previous state was (`idle`/`done`) for the entire turn, only flipping to `done` when `Stop` fires. The tracker would show prompt-only turns as invisible.

Sequence after this fix:
1. `UserPromptSubmit` → `State = working`, `Activity = "You: …"`, `LastKind = UserPromptSubmit`.
2. (Optional tool_start/tool_end events update Activity/Tool/LastKind; State stays `working`.)
3. `Stop` → `State = done`, `Activity = "Said: …"`, `LastKind = Stop`.

The subagent rule (above) takes precedence: a Claude `UserPromptSubmit` carrying a non-empty `agent_id` does NOT flip the parent pane to `working`.

#### Streaming-text gap

Hooks are event-driven, not streaming. In-progress assistant prose between two tool calls is invisible to hooks. **Accept this gap.** In the renderer, when `State == "working"` and `LastKind ∈ {PostToolUse, UserPromptSubmit}`, append a `…` suffix to the snippet to signal "probably writing prose right now." No transcript tailing, no terminal-scrape fallback.

If the streaming gap turns out to hurt UX after dogfooding, a contained recovery is documented in [Risks](#risks).

### Installed shell scripts (intentionally dumb)

`~/.claude/hooks/party-cli-state.sh`:
```sh
#!/bin/sh
# party-cli state hook v1 — managed by `party-cli hooks install`
[ -n "$PARTY_SESSION" ] || exit 0
command -v party-cli >/dev/null 2>&1 || exit 0
exec party-cli hook claude "$1"
```

`$CODEX_HOME/party-cli-state.sh`: identical except `hook codex "$1"`.

### Pi sidecar contract

`pi/agent/extensions/activity-sidecar.ts` is the Pi-side writer. The file is in this repo and symlinked via `install.sh` (`~/.pi → repo/pi`), so updates ship in the same PR as the Phase 2 cutover — no cross-repo flag day. The package `internal/piactivity` is read-only; it does NOT need to be "routed through party-cli hook pi". The Phase 2 modify list elsewhere in this document reflects that.

The legacy sidecar file at `/tmp/<party-id>/pi-activity.json` feeds three consumers today:

1. Tracker snippets + busy override (`internal/tui/tracker_actions.go:177-217`).
2. `party-cli read` rich Pi output (`internal/message/message.go:175,351-352` — uses `Recent[]` joined with newlines).
3. Pi resume UUID persistence (`internal/session/pi_resume.go:17` — `piactivity.ReadResumeID` extracts the `pi_session_id` / `session_file` fields, also referenced by the cleanup script).

A naive "delete the sidecar at end of Phase 2 and replace with state.json" would break (2) and (3). Resolution: **fold the non-State fields into `state.json`'s `PaneState`** (`Recent`, `SessionFile`, `PiSessionID` — already in the schema above). The sidecar TypeScript is rewritten to shell out to `party-cli hook pi <action>` with the same payload it writes to the JSON file today. `party-cli hook pi` populates the Pi-specific fields on `PaneState` alongside `State` / `Activity`.

Consumer migration:
- `internal/tui/tracker_actions.go`: drop `applyPiActivitySidecar` and `PrimaryActiveOverride` plumbing. Tracker reads `State` from `state.json`.
- `internal/message/message.go`: `readPiActivityOutput` migrates to read `PaneState.Recent` from `state.json` (no behaviour change — same field, same join logic).
- `internal/session/pi_resume.go`: `piactivity.ReadResumeID` becomes a thin shim that reads `PaneState.PiSessionID` / `PaneState.SessionFile` from `state.json`. The cleanup script in `internal/session/start.go:385` still points at `/tmp/$W/pi-activity.json` today; Phase 2 updates it to `/tmp/$W/state.json` (or to the canonical `~/.party-state/$W/state.json` path).
- `internal/piactivity/*`: kept as a read-only adapter for the duration of Phase 2 (its `Read` / `ReadLatest` / `ReadResumeID` now wrap `state.LoadSessionState`). At the start of Phase 3 the package is deleted and its remaining callers inlined.

`ActiveOverride *bool` is a **transitional shim**, not deleted at end of Phase 2. It remains in `SessionRow` and `Observation` as long as `internal/piactivity` exists. Once Phase 3 deletes `internal/piactivity`, the carve-out goes with it. The Definition of Done items that say "ActiveOverride deleted" / "Snippet derivation from capture deleted" are tightened in the DoD block above to call this out explicitly.

The shell script's contract — "shell out to `party-cli hook <agent> <action>` with stdin passthrough" — is what `v1` means. `party-cli hook`'s internal semantics can change freely without re-running `hooks install`. Bumping the script to v2 only happens if the contract itself changes (e.g. argv shape).

### Hook installer

New files:
- `cmd/hooks.go` — `party-cli hooks {install,status,uninstall}` subcommand surface
- `internal/hooks/manager.go` — orchestration, status logic
- `internal/hooks/claude.go`, `codex.go`, `pi.go` — per-agent installers
- `internal/hooks/assets/party-cli-state.sh` — single template, embedded via `//go:embed`

Surface:
```
party-cli hooks status                 # human-readable per-agent status
party-cli hooks install [agent...]     # default: all known agents
party-cli hooks install --check        # exit 1 if any installed agent is Outdated
party-cli hooks uninstall [agent...]
```

Status per agent is one of `Current | Outdated | Untrusted | Modified | NotInstalled` (the last two only apply to Codex; see Codex installer details). Determined by:
1. Script file exists *and* its v-marker line matches the current expected version.
2. Settings/config file contains the expected hook entries, tagged with `"_party_cli": "v1"`.
3. For Codex: the recorded `trusted_hash` matches the on-disk script hash.
4. For Pi: the installed extension version marker matches what `party-cli` was built against (see Pi sidecar contract).

All required checks must hold or status is one of the failure values above.

#### Claude installer details

1. Resolve config dir: `$CLAUDE_CONFIG_DIR` → `~/.claude`.
2. `mkdir -p hooks/`, write `party-cli-state.sh` (0755).
3. Read `settings.json`. If missing, create with `{}`.
4. Back up to `settings.json.party-cli.bak` if no backup exists yet.
5. Merge our hook entries idempotently. Each entry tagged `{"_party_cli": "v1"}` for find/remove.
6. Write atomically (tmp + rename).

Hooks installed:

| Claude hook | Action arg | Notes |
|---|---|---|
| `SessionStart` | `starting` | |
| `UserPromptSubmit` | `working` | turn-start state — see "Turn-start state" above |
| `PreToolUse` | `tool_start` | conditional state.json flush — see "Hot-path optimisation" |
| `PostToolUse` | `tool_end` | conditional state.json flush — see "Hot-path optimisation" |
| `Stop` | `done` | subagent rule suppresses when `agent_id` is non-empty |
| `SubagentStop` | (Activity only; subagent rule applies) | |
| `Notification` | `blocked` | |

#### Codex installer details

Codex config lives at `$CODEX_HOME/config.toml` and `$CODEX_HOME/hooks.json`. Beyond writing the hook entries, two upstream constraints have to be respected before hooks actually fire:

1. **Trust state.** Upstream Codex (`codex-rs/hooks/src/engine/discovery.rs:495-500`) only dispatches hooks tagged `Managed` or `Trusted` (i.e., whose `trusted_hash` in the config matches the on-disk script). An entry without a matching `trusted_hash` lands as `Untrusted` and Codex silently no-ops it. The installer MUST:
   - Compute the SHA-256 of the installed `party-cli-state.sh` and write it as the `trusted_hash` in `hooks.json`, OR
   - Mark the entry as `Managed` if Codex's `hooks.json` schema allows it for our use case (check upstream — if `Managed` requires the script to live under a Codex-controlled path, fall back to `trusted_hash`).
2. **Approvals are bypassed.** party-cli launches Codex with `--dangerously-bypass-approvals-and-sandbox` (`internal/agent/codex.go:52`). That means `PermissionRequest` (the closest analogue to Claude's `Notification`) effectively never fires. The Codex `blocked` mapping must NOT rely on `PermissionRequest`. See Phase 3 / Risk #9 for the resolved `blocked` semantics on Codex.

`party-cli hooks status codex` MUST surface trust state separately from the version-marker check. The status values become:

- `Current` — script + settings + `trusted_hash` all match.
- `Outdated` — script or settings version-marker doesn't match.
- `Untrusted` — entries present but trust hash is missing or stale (Codex won't dispatch them).
- `Modified` — script on disk doesn't hash to the recorded `trusted_hash` (likely user-edited).
- `NotInstalled` — neither script nor entries present.

Pi sidecar uses the existing extension surface; see "Pi sidecar contract" below.

Uninstall walks settings.json by the `_party_cli` tag, removes matching entries only, leaves user's other hooks alone, deletes the script file.

#### `install.sh` integration

```
./install.sh             → runs `party-cli hooks install` after symlinks
./install.sh --no-hooks  → skips it
non-TTY                  → skips it (assume CI)
```

`install.sh` today has exactly two flags: `--symlinks-only` and `-h/--help` (`install.sh:11-24`). Phase 1 must extend the argument-parser loop to accept `--no-hooks` and gate the post-symlink `party-cli hooks install` call on it. The existing interactive `read` at `install.sh:419` runs unconditionally; Phase 1 must short-circuit the prompt when stdin is not a TTY (`[[ -t 0 ]]`) AND skip `party-cli hooks install` in the same branch.

**Settings file ownership.** `install.sh` symlinks `~/.claude → repo/claude`, `~/.codex → repo/codex`, `~/.pi → repo/pi` (`install.sh:67,89`). Any write to `~/.claude/settings.json` or `~/.codex/config.toml` therefore mutates files inside this repo and shows up as a dirty working tree after `./install.sh`. Decision:

- **Hook entries are runtime-managed, not checked in.** `party-cli hooks install` writes to an overlay file that is `.gitignore`d at the repo root:
  - Claude: `~/.claude/settings.local.json` (already supported by Claude as a per-user overlay; precedence is `settings.local.json` > `settings.json`).
  - Codex: `~/.codex/hooks.json` is the dedicated hooks file in upstream Codex (`config.toml` keeps `[features] hooks = true` only). Add `hooks.json` to `.gitignore` under `codex/`.
  - Pi: extension config lives at `~/.pi/extensions/`; the activity-sidecar extension itself is checked in via symlink, but any runtime-generated extension state file (e.g., `~/.pi/extensions/.party-cli-installed`) is `.gitignore`d.
- Acceptance: after `./install.sh && ./install.sh` (idempotent), `git status` inside the repo is clean.

**Settings.json round-trip safety.** Phase 1 includes a round-trip validation test asserting that Claude Code (and Codex) preserve unknown keys (specifically the `_party_cli: "v1"` tag) across re-serialization. The test reads a known-good settings file, lets Claude/Codex parse-and-rewrite it (via a smoke run), then reads back and asserts the tag survived. If round-trip is lossy, the installer falls back to a sidecar manifest at `~/.claude/party-cli-hooks.lock.json` / `~/.codex/party-cli-hooks.lock.json` listing the entries we own, and `uninstall` consults that manifest instead of scanning by tag. Decision deadline: end of Phase 1.

### Tracker integration

`internal/sessionactivity/Evaluate` rewrites. New `Observation` / `Result` shape:

```go
type Observation struct {
    Key       string
    SessionID string  // need this to read state.json
    Enabled   bool
}

type Result struct {
    State    string  // working|blocked|done|idle|starting|stopped|unknown
    Activity string  // structured snippet
    LastKind string  // for "…" streaming-prose suffix
    Stale    bool    // true if LastEvent > 60s ago and state isn't idle/stopped
}
```

`Snippet`, `ActiveOverride`, FNV hash, the entire window-based generating detector — **gone** at end of Phase 2.

Resolution is trivial:
```go
ss, err := state.LoadSessionState(sessionID)
if err != nil || ss == nil {
    return Result{State: "unknown"}
}
p := ss.Panes["primary"]
stale := time.Since(p.LastEvent) > 60*time.Second && p.State != "idle" && p.State != "stopped"
if stale && p.State == "working" {
    // a working session that hasn't checked in for >60s — show unknown
    return Result{State: "unknown", Activity: p.Activity, Stale: true}
}
return Result{State: p.State, Activity: p.Activity, LastKind: p.LastKind, Stale: stale}
```

#### `SessionRow` changes (`tui/tracker.go`)

Drop:
- `PrimaryActive bool`
- `PrimaryActiveOverride *bool`
- `Snippet` derivation from terminal capture (replaced by Activity)
- `TodoOverlay` derivation that depends on snippet, if any

Add:
- `State string`
- `LastKind string`

`activityDot()` selects glyph/color from `State`:

| State | Glyph | Color | Animation |
|---|---|---|---|
| `working` | agent icon | agent color | blink (today's behavior) |
| `blocked` | `!` or `▲` | bright red | steady |
| `done`    | agent icon | bright cyan | steady |
| `idle`    | agent icon | muted | steady |
| `starting` | `…` | muted | steady |
| `stopped` | `○` | dim | steady |
| `unknown` | `?` | dim | steady |

Snippet line below the title stays. Text comes from `Result.Activity`, falling back to `"no recent activity"` when empty. Streaming-prose suffix appended in the renderer:

```go
suffix := ""
if state == "working" && (lastKind == "PostToolUse" || lastKind == "UserPromptSubmit") {
    suffix = " …"
}
```

#### Master roll-up

For master rows, compute `displayState = worst(self, ...workers)` with priority order:
```
blocked > working > done > starting > idle > unknown > stopped
```

Display the master's own state next to the master's title; if a worker is in a worse state, prepend a badge like `⚠ 2 workers blocked` on the master row.

### `done → idle` mechanics

Tracker writes `SeenAt` to `state.json` when:
- User presses `Enter` to attach a session (existing tracker behavior).
- The session has been the current/attached session for ≥2s of wall time.

The hook never writes `idle` — only the tracker does, after observation.

**Critical: locked read-modify-write.** A naive `Load → mutate → Save` pattern (even with `flock` on the save) loses concurrent updates because the load happens outside the lock. Scenario: tracker reads `{State: done}`. A hook fires and writes `{State: working}`. Tracker then writes back `{State: idle}`, clobbering the hook's `working`. `flock` serialises writers; it does NOT prevent saving a stale snapshot.

`internal/state/hookstate.go` exposes a single update API for transitions of this shape:

```go
// UpdateSessionState acquires flock, re-reads state.json inside the lock,
// invokes mutate (which may return false to skip the write), and saves
// atomically while still holding the lock.
//
// mutate runs against the freshly-read state inside the critical section.
// Returning false aborts the write (used when the freshly-read state no
// longer satisfies the precondition the caller checked optimistically).
func UpdateSessionState(sessionID string, mutate func(*SessionState) bool) error
```

Tracker refresh uses it like this:
```go
state.UpdateSessionState(id, func(ss *state.SessionState) bool {
    p := ss.Panes["primary"]
    // Re-check inside the lock: hooks may have moved this off `done`
    // between our optimistic load and acquiring the lock.
    if p.State != "done" || !ss.SeenAt.After(p.LastEvent) {
        return false
    }
    p.State = "idle"
    ss.Panes["primary"] = p
    return true
})
```

`UpdateSessionState` also bumps `SeenAt` separately when the tracker just wants to record observation without changing state — that path takes a similar mutate function that only writes `SeenAt`.

**Allowed transitions from inside `UpdateSessionState` (tracker-side).** The only state mutations the tracker is allowed to apply are:
- `done → idle` when `SeenAt > LastEvent`.
- `SeenAt` updates (no state change).

Anything else is a hook write. This invariant keeps the tracker incapable of clobbering hook-driven `working`/`blocked` transitions even if a future refactor adds a new tracker-side mutation by mistake.

The `Seq` field is informational only here — see the schema-section note. Don't gate `UpdateSessionState` on `Seq` comparisons; gate it on the actual fields the tracker is allowed to touch.

### File rotation

`state.jsonl` rotation on every hook write (one cheap stat call):
- If size > 1 MB, rename to `state.jsonl.1` (overwriting), open fresh.
- Keep only `.1` — one historical file is plenty for debug.

### Concurrency / safety

- `flock` (POSIX) on `state.json` with 1s timeout. Hook backs off and retries once, then logs to stderr and exits 0 (hook failures must never surface to the agent).
- Atomic writes: tmp file + rename.
- Schema migration: `Version: 1` now. Unknown version → hook overwrites; tracker treats as `unknown`.

---

## Sequenced rollout

### Phase 1 — plumbing, no UX change

Files to create:
- `internal/state/hookstate.go` + `hookstate_test.go` — read/write/lock/rotation
- `internal/hooks/manager.go`, `claude.go`, `codex.go`, `pi.go`, `assets/party-cli-state.sh`
- `cmd/hook.go` — the `party-cli hook <agent> <action>` subcommand
- `cmd/hooks.go` — the `party-cli hooks {install,status,uninstall}` surface

Files to modify:
- `install.sh` — auto-invoke `party-cli hooks install`, `--no-hooks` flag, non-TTY skip (see "install.sh integration" above for the specific lines that move)
- `internal/session/launch.go` — `launchSession` already calls `s.Client.SetEnvironment(ctx, lc.sessionID, "PARTY_SESSION", lc.sessionID)` at line 48; add the matching call for `PARTY_STATE_ROOT` immediately after, sourced from the resolved state-root path. This is the single tmux env hand-off, not `cmd/spawn.go` / `cmd/start.go`.

Tests:
- `hookstate` unit (concurrent writes, rotation, schema rejection, locked read-modify-write via `UpdateSessionState`)
- `hook` command with sample Claude + Codex + Pi payloads
- Installer idempotency (run twice → no diff in settings.json / hooks.json)
- Settings round-trip preservation test (Claude + Codex) for the `_party_cli: "v1"` tag (see "install.sh integration"). If it fails, switch to sidecar lock file.
- Codex trust-state test: `party-cli hooks install codex` writes a `trusted_hash` and `party-cli hooks status codex` reports `Untrusted` when the script is tampered.
- Latency benchmark asserting <20ms p99 — **shell-driven, not in-process.** Spec: `time party-cli hook claude tool_start <<< '{}'` repeated N≥200 times with the binary warm in cache. An in-process Go benchmark hides the Go runtime / binary load cost that hooks actually pay every invocation. Measured baseline on dev hardware: `party-cli version` p99 ~4.65ms cold-but-warm-binary — headroom exists for the hook path, but `internal/state/store.go:32` uses a 10s lock timeout and the existing manifest lock polls at 10ms intervals (`internal/state/store.go:211-226`); flock contention on a single state.json can eat most of the budget. Benchmark must exercise the contention case (2 concurrent hook invocations + tracker `UpdateSessionState`).
- **Hook path must NOT call `DiscoverSessions`** (~13ms for 100 manifests on dev hardware). Asserted by a unit test on `cmd/hook.go` that records the set of `state.Store` methods touched per invocation.

Snippet-hash detector still drives the tracker. **No visible change.**

Dogfood for a couple of days. Verify <20ms hook latency, no Claude / Codex weirdness, no orphaned settings entries.

### Phase 2 — cut over, delete snippet-hash

Modify:
- `internal/sessionactivity/activity.go` — rewrite `Observation` / `Result` shape (most of the file gets simpler or moves out)
- `internal/tui/tracker.go` + `internal/tui/tracker_actions.go` — state-driven rendering, 7-state dot palette, snippet-from-Activity; drop the `captureRoleSnippet` branch (see Delete list)
- `internal/tui/style.go` — new dot colors per state
- `pi/agent/extensions/activity-sidecar.ts` — the actual Pi writer (17k LOC TypeScript file). Rewrites to shell out to `party-cli hook pi <action>` while still populating the Pi-specific carry-through fields (`recent`, `session_file`, `pi_session_id`) on `state.json`. See "Pi sidecar contract" for the consumer migration.
- `internal/piactivity/*` — kept as a transitional read-only adapter pointing at `state.json`. Deleted in Phase 3, not Phase 2.
- `internal/message/message.go` — `readPiActivityOutput` switches to reading `PaneState.Recent` from `state.json` (same join semantics).
- `internal/session/pi_resume.go` + the cleanup-script string in `internal/session/start.go:385` — point at `state.json` instead of `pi-activity.json`.

**Delete (tracker-side snippet pipeline only):**
- The FNV-window logic in `internal/sessionactivity/activity.go` (the `HashSnippet`, `Entry`, `Window`-based detection).
- The tracker's `captureRoleSnippet` call site in `internal/tui/tracker_actions.go` — this is the ONLY `tmux capture-pane` invocation that gets removed in Phase 2.
- `SessionRow.Snippet` derivation from capture (the field stays but is populated from `state.json`'s `PaneState.Activity` / `Recent`).
- `SessionRow.PrimaryActive`, `PrimaryActiveOverride` (the `ActiveOverride *bool` carve-out itself lingers until Phase 3 — see Pi sidecar contract).
- Per-session capture goroutines / tickers feeding the tracker.

**Do NOT delete in Phase 2:**
- `internal/tmux` capture helpers and ANSI-strip helpers. They are also called by `internal/message/message.go` (`party-cli read` quoted output) and picker preview rendering (`internal/picker/picker_test.go` exercises both). Scope of the Phase 2 delete is strictly the tracker snippet pipeline. A grep confirms multiple consumers (`tools/party-cli/internal/picker/picker_test.go:243,374,841`, `tools/party-cli/internal/message/message_test.go:527,…`).
- `Observation.ActiveOverride *bool` — stays as the Pi transitional shim. Removed when `internal/piactivity/*` is deleted in Phase 3.

Tests:
- State → dot rendering matrix
- Master roll-up aggregation
- `done → idle` transition driven by `SeenAt`
- Subagent suppression (Claude `agent_id` payload doesn't flip parent)
- Activity formatter coverage per hook event

After Phase 2: snippet-hash detector is gone. Tracker is hook-authoritative. Agents without hooks render `unknown`.

### Phase 3 — `blocked` polish, `internal/piactivity` removal

**Per-agent `blocked` resolution was moved earlier** (decided in Phase 1, demonstrated in Phase 2). Phase 3 polishes the result; it does not unblock Phase 2 cutover.

Per-agent decisions (all locked in by end of Phase 1):

- **Claude.** `Notification` event maps to `blocked`. Verify current Claude Code semantics end-to-end during Phase 1 dogfood — Claude's notification surface has changed historically.
- **Codex.** Codex has no `Notification` event. The closest signal, `PermissionRequest`, does not fire because party-cli launches Codex with `--dangerously-bypass-approvals-and-sandbox` (`internal/agent/codex.go:52`). **Decision: Codex does not show `blocked` after Phase 2.** All Codex panes resolve to `working` / `done` / `idle` / `starting` / `stopped` / `unknown`. If a future Codex release exposes a "needs input" signal, revisit. This is an explicit accepted limitation, not a TODO.
- **Pi.** The Pi sidecar emits `session_start`, `before_agent_start`, `agent_start`, `message_update`, `message_end`, `tool_execution_*`, `agent_end`, `session_shutdown`. None of these are a "needs input" signal. **Decision: Pi does not show `blocked` after Phase 2.** Same caveat as Codex — revisit if Pi grows a blocked-equivalent event.

The 7-state palette therefore renders fully for Claude and renders 6-of-7 for Codex/Pi. The dot color table stays as-is (`blocked` exists in the palette); the `unknown`-vs-empty distinction is what protects against confusing renderings on Codex/Pi panes that genuinely can't report blocked.

Phase 3 work:
- Delete `internal/piactivity/*` (the transitional read-only adapter introduced in Phase 2). All callers move directly to `state.LoadSessionState`.
- Remove the `ActiveOverride *bool` carve-out from `SessionRow` and `Observation` (it can't be removed earlier — see Pi sidecar contract).
- Optional: `party-cli state log <session-id>` subcommand to tail `state.jsonl` for debugging.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Claude / Codex hook schema drift | Tolerant JSON parsing (unknown fields ignored, missing fields default); one parse path per agent in `cmd/hook.go`; version drift logs as warning, not error |
| 2 | Hook latency cascade — `party-cli hook` slow enough to show up in Claude's tool loop | Lean hot path (open, append, flock-write-rename, exit); shell-driven benchmark asserts <20ms p99 under flock contention; rotation is `stat`-only on common path; hook path forbidden from calling `DiscoverSessions` |
| 3 | `settings.json` patching collides with user's existing hooks | Tagged entries (`_party_cli: "v1"`); backup; merge not overwrite; uninstall removes only tagged entries. Round-trip test in Phase 1 verifies the tag survives Claude/Codex re-serialization; if it fails, switch to sidecar lock file |
| 4 | No fallback after Phase 2 — agents without hooks render `unknown` forever | Auto-install + `hooks install --check` for CI; `party-cli hooks status` surfaced in `party-cli config show` and (probably) in tracker help text |
| 5 | Pi sidecar version skew on user machines without symlinks | Pi sidecar (`pi/agent/extensions/activity-sidecar.ts`) is in-repo and symlinked via `install.sh`, so the cutover ships in the same PR — no cross-repo flag day. Real risk is users on stale config (non-symlink install, or `~/.pi` overridden). Mitigation: `party-cli hooks status pi` reports a sidecar extension-version marker, derived from a constant emitted by the TS extension on `before_agent_start`. Mismatched marker → `Outdated`. |
| 6 | Streaming-text gap — assistant prose between tool calls is invisible to hooks | Accepted. Renderer shows `…` suffix when `State == working` and `LastKind ∈ {PostToolUse, UserPromptSubmit}`. If this hurts UX after dogfooding, contained recovery is option C below |
| 7 | Tool arg leakage (Bash command lines, env vars in args) | Truncate at first newline + 60 chars; strip leading `[A-Z_]+=\S+`. Not worse than today |
| 8 | Stop hook needs to read `transcript_path` for the "Said: …" snippet — file may be large or absent | Read tail only (last ~4KB); if file missing or parse fails, omit the Said snippet — don't fail the hook |
| 9 | Codex / Pi can't report `blocked` | Accepted as an explicit Phase 3 decision (see "Phase 3 — `blocked` polish"). 7-state palette renders 6-of-7 for Codex/Pi; `blocked` slot is reserved for future protocol additions. |
| 10 | Codex hooks silently no-op if trust state is missing | Installer computes `trusted_hash` (SHA-256 of installed script) and writes it into `hooks.json`; `party-cli hooks status codex` reports `Untrusted` / `Modified` separately from `Current`. See "Codex installer details". |
| 11 | Subagent suppression is Claude-shaped (Codex Stop has no `agent_id`) | Subagent rule is per-agent, not generic — see "Subagent rule" block. Codex treats every Stop as top-level; Pi has no subagent dimension. |

### Contingency for risk #6 (if streaming gap really bites)

Hybrid: default to hook-driven Activity. If `State == "working"` and the most recent hook event is older than ~5 seconds, do a one-shot terminal capture to fill the snippet field (not state). Subprocess fires rarely; doesn't reintroduce the ticker. Defer this decision until after Phase 2 ships.

---

## Deferred to implementation time

Items central to correctness (hot-path update rule, prompt-only turn-start state, locked read-modify-write, per-agent `blocked` resolution) have moved into the design body. The remaining items are genuine tuning knobs that can wait for empirical data:

- **`unknown` after 60s — what's the right threshold?** Too low → idle sessions flicker. Too high → dead agents linger as `working`. Plan starts at 60s; may need 90–120s after observing Claude's typical inter-tool gaps. Decision: pick during Phase 1 dogfood; not a Phase 1 blocker.
- **Activity-string secret patterns.** Plan strips `[A-Z_]+=\S+` heads and truncates at newline+60. May want to add patterns for known secret shapes (`gh[a-z]_`, `sk-`, etc) — decide on first PR review.
- **`state.jsonl` rotation size.** 1 MB cap is a guess; may want 256 KB if disk usage matters or 4 MB if we ever want a longer history. Tune in Phase 3 after observing real session sizes.

---

## Out of scope (this plan)

- `PARTY_ENV` discoverable agent profile (depends on reliable `blocked`)
- SKILL.md installation flows that depend on `PARTY_ENV`
- Cross-host session tracking (`state.json` is local-only; no network sync)
- Generic non-agent shell pane tracking (could be added later via a shell hook, but not in this plan)

---

## Prior art

### [Herdr](https://github.com/ogulcancelik/herdr) — agent multiplexer for the terminal

Herdr is a directly comparable project: a terminal multiplexer for managing multiple AI agents with per-pane state tracking (`blocked | working | done | idle`). It supports a wider agent matrix than party-cli today — Claude Code, Codex, Pi, Droid, Amp, OpenCode, Grok CLI, Hermes — and crucially, it solves the same "what is each agent doing" tracking problem with a similar dual-mechanism approach.

**Where Herdr's design overlaps with this plan:**
- Same problem framing: terminal-native, no GUI, persistent sessions, per-agent state at a glance.
- Same instinct that terminal-output heuristics alone aren't enough → both projects add a structured reporting channel for semantic state.
- Same target state vocabulary (`blocked | working | done | idle`).

**Where it diverges from this plan:**
- **Herdr uses a socket API** for agents to report state semantically. This plan uses **file-based hand-off** via `party-cli hook ...` writing `state.json`.
- Herdr keeps process-name + terminal-output detection as a permanent zero-config fallback. This plan **deletes the heuristic detector entirely** at end of Phase 2.

**Why a different mechanism here.** A socket API needs a long-lived listener process. party-cli is invoke-and-exit (no daemon), so file-based state survives between invocations without us standing up a tracker process. Hooks are also agent-native config — once `party-cli hooks install` runs, the agent's existing config system carries them, no per-agent dial-in code needed. Trade-off: we lose Herdr's zero-config "works for any process" coverage. We accept that, because for the agents we care about (Claude Code, Codex, Pi) we control the installer and can guarantee hooks are present.

**What's worth borrowing later** (out of scope for this plan, but tracked for follow-up):
- Herdr's broader agent matrix (Droid, Amp, OpenCode, Grok CLI, Hermes) — once the hook installer abstraction is in place, adding new agents is mostly a per-agent `internal/hooks/<agent>.go` file plus a payload-shape mapping in `cmd/hook.go`.
- The process-name / terminal-output heuristic as a degraded mode for *unrecognized* panes (e.g. the user opens a raw shell pane and we still want to show *something*). Today's plan renders these as `unknown`; Herdr's approach is a reasonable future upgrade.

Worth reading Herdr's [README](https://github.com/ogulcancelik/herdr) and [Architecture docs](https://github.com/ogulcancelik/herdr/blob/main/docs/) before opening the Phase 1 PR — design choices made by another team in the same problem space are cheap lessons.
