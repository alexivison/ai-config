# Hook-State Tracker

> **Goal:** Replace the snippet-hash heuristic in `internal/sessionactivity` with authoritative state pushed by Claude Code / Codex / Pi hooks. Tracker shows `working | blocked | done | idle | starting | stopped | unknown` per pane, sourced from a per-session `state.json` that hooks write to. Snippets become structured Activity strings from those same hook events.
>
> **Approach:** File-based state hand-off (hooks write a tiny JSON via `party-cli hook ...`, tracker reads it). Auto-install hooks during `install.sh` with `--no-hooks` opt-out. Delete the FNV-window detector and the `tmux capture-pane` snippet pipeline entirely at the end of Phase 2 — no fallback, hook-driven only.

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
- [ ] `tmux capture-pane` snippet pipeline and ANSI-strip helpers deleted (unless used elsewhere — verify with `grep`)
- [ ] `SessionRow.PrimaryActive`, `PrimaryActiveOverride`, the `ActiveOverride *bool` carve-out: deleted
- [ ] Pi sidecar routed through `party-cli hook pi <action>` — no more `ActiveOverride` path
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
    Seq       int64     `json:"seq"`        // monotonic; time.Now().UnixNano()
    LastEvent time.Time `json:"last_event"`
    LastKind  string    `json:"last_kind"`  // event kind that produced LastEvent — used by renderer for "…" suffix
}
```

Single read for the tracker. No log scanning on the hot path.

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
- All paths through `state.SanitizePartyID` — `$PARTY_SESSION` is never trusted as a path component.

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

**Subagent rule** (in `cmd/hook.go`, not in shell scripts): if the stdin payload contains a non-empty `agent_id` (Claude subagent), suppress `done`/`idle`; forward `blocked`; clamp `working` so the parent doesn't get re-marked working on every subagent step.

**Hot-path optimisation:** `tool_start`/`tool_end` always append to `state.jsonl` but only update `state.json` when the resulting `State` differs from the current value. Saves N flock dances per Claude turn.

#### Action → Activity mapping

| Hook event | Activity becomes |
|---|---|
| `SessionStart` | `"starting…"` |
| `UserPromptSubmit` | `"You: " + firstline(prompt)[:60]` — sticky until next event |
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

Pi already has `internal/piactivity` + sidecar. We keep the sidecar process but rewrite it to call `party-cli hook pi <action>` so all three agents flow through the same code path. No more `ActiveOverride bool` carve-out.

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

Status per agent is one of `Current | Outdated | NotInstalled`. Determined by:
1. Script file exists *and* its v-marker line matches the current expected version.
2. Settings file contains the expected hook entries, tagged with `"_party_cli": "v1"`.

Both must hold or status is `Outdated`.

#### Claude installer details

1. Resolve config dir: `$CLAUDE_CONFIG_DIR` → `~/.claude`.
2. `mkdir -p hooks/`, write `party-cli-state.sh` (0755).
3. Read `settings.json`. If missing, create with `{}`.
4. Back up to `settings.json.party-cli.bak` if no backup exists yet.
5. Merge our hook entries idempotently. Each entry tagged `{"_party_cli": "v1"}` for find/remove.
6. Write atomically (tmp + rename).

Hooks installed:

| Claude hook | Action arg |
|---|---|
| `SessionStart` | `starting` |
| `UserPromptSubmit` | (Activity only — no state change) |
| `PreToolUse` | `tool_start` |
| `PostToolUse` | `tool_end` |
| `Stop` | `done` |
| `SubagentStop` | (Activity only; subagent rule applies) |
| `Notification` | `blocked` |

Codex equivalent uses `$CODEX_HOME/hooks.json` + `[features] hooks = true` in `config.toml`. Pi sidecar already exists.

Uninstall walks settings.json by the `_party_cli` tag, removes matching entries only, leaves user's other hooks alone, deletes the script file.

#### `install.sh` integration

```
./install.sh             → runs `party-cli hooks install` after symlinks
./install.sh --no-hooks  → skips it
non-TTY                  → skips it (assume CI)
```

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

On every tracker refresh, before rendering:
```go
for id, ss := range loadedStates {
    p := ss.Panes["primary"]
    if p.State == "done" && ss.SeenAt.After(p.LastEvent) {
        p.State = "idle"
        state.SaveSessionState(id, ss)  // flock, atomic
    }
}
```

The hook never writes `idle` — only the tracker does, after observation.

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
- `install.sh` — auto-invoke `party-cli hooks install`, `--no-hooks` flag, non-TTY skip
- `cmd/spawn.go`, `cmd/start.go` — export `PARTY_STATE_ROOT` to pane env alongside `PARTY_SESSION`

Tests:
- `hookstate` unit (concurrent writes, rotation, schema rejection)
- `hook` command with sample Claude + Codex + Pi payloads
- Installer idempotency (run twice → no diff in settings.json)
- Latency benchmark asserting <20ms p99

Snippet-hash detector still drives the tracker. **No visible change.**

Dogfood for a couple of days. Verify <20ms hook latency, no Claude / Codex weirdness, no orphaned settings entries.

### Phase 2 — cut over, delete snippet-hash

Modify:
- `internal/sessionactivity/activity.go` — rewrite `Observation` / `Result` shape (most of the file gets simpler or moves out)
- `tui/tracker.go` — state-driven rendering, 7-state dot palette, snippet-from-Activity
- `tui/style.go` — new dot colors per state
- `internal/piactivity/*` — route through `party-cli hook pi`

**Delete:**
- The FNV-window logic in `internal/sessionactivity/activity.go` (the `HashSnippet`, `Entry`, `Window`-based detection)
- The `tmux capture-pane` invocation feeding snippets — wherever it lives (verify with `grep capture-pane tools/party-cli`)
- The ANSI-strip helpers it relied on (verify no other consumers first)
- `SessionRow.Snippet` derivation from capture (the field stays but is populated from Activity)
- `SessionRow.PrimaryActive`, `PrimaryActiveOverride`
- `Observation.ActiveOverride *bool` and the Pi-only carve-out in `Evaluate`
- Any per-session capture goroutines / tickers

Tests:
- State → dot rendering matrix
- Master roll-up aggregation
- `done → idle` transition driven by `SeenAt`
- Subagent suppression (Claude `agent_id` payload doesn't flip parent)
- Activity formatter coverage per hook event

After Phase 2: snippet-hash detector is gone. Tracker is hook-authoritative. Agents without hooks render `unknown`.

### Phase 3 — `blocked` polish

- Verify Claude `Notification` triggers `blocked` reliably (Claude Code's notification semantics have changed historically; test current behavior end-to-end).
- Codex equivalent — Codex's hook protocol is smaller; figure out which event maps to "needs input" (may require approximation via stop-event timing).
- Optional: `party-cli state log <session-id>` subcommand to tail `state.jsonl` for debugging.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Claude / Codex hook schema drift | Tolerant JSON parsing (unknown fields ignored, missing fields default); one parse path per agent in `cmd/hook.go`; version drift logs as warning, not error |
| 2 | Hook latency cascade — `party-cli hook` slow enough to show up in Claude's tool loop | Lean hot path (open, append, flock-write-rename, exit); benchmark asserts <20ms p99; rotation is `stat`-only on common path |
| 3 | `settings.json` patching collides with user's existing hooks | Tagged entries (`_party_cli: "v1"`); backup; merge not overwrite; uninstall removes only tagged entries |
| 4 | No fallback after Phase 2 — agents without hooks render `unknown` forever | Auto-install + `hooks install --check` for CI; `party-cli hooks status` surfaced in `party-cli config show` and (probably) in tracker help text |
| 5 | Pi sidecar regression — sidecar lives outside this repo | Coordinate with Pi integration owner before Phase 2 cuts the `ActiveOverride` path. Pi sidecar must be updated to call `party-cli hook pi <action>` before we delete `ActiveOverride` |
| 6 | Streaming-text gap — assistant prose between tool calls is invisible to hooks | Accepted. Renderer shows `…` suffix when `State == working` and `LastKind ∈ {PostToolUse, UserPromptSubmit}`. If this hurts UX after dogfooding, contained recovery is option C below |
| 7 | Tool arg leakage (Bash command lines, env vars in args) | Truncate at first newline + 60 chars; strip leading `[A-Z_]+=\S+`. Not worse than today |
| 8 | Stop hook needs to read `transcript_path` for the "Said: …" snippet — file may be large or absent | Read tail only (last ~4KB); if file missing or parse fails, omit the Said snippet — don't fail the hook |

### Contingency for risk #6 (if streaming gap really bites)

Hybrid: default to hook-driven Activity. If `State == "working"` and the most recent hook event is older than ~5 seconds, do a one-shot terminal capture to fill the snippet field (not state). Subprocess fires rarely; doesn't reintroduce the ticker. Defer this decision until after Phase 2 ships.

---

## Deferred to implementation time

These aren't blocking, but to flag in the implementation PR:

- **Should `tool_start`/`tool_end` actually update `state.json` on every event?** Plan says: append to `state.jsonl` always; update `state.json` only on state transitions. Saves flock dances per Claude turn. Re-validate empirically on first benchmark run.
- **`unknown` after 60s window — what's the right threshold?** Too low → idle sessions flicker. Too high → dead agents linger as `working`. Plan starts at 60s; may need 90–120s after observing Claude's typical inter-tool gaps.
- **Sanitization scope for Activity strings.** Plan strips `[A-Z_]+=\S+` heads and truncates at newline+60. May want to add patterns for known secret shapes (`gh[a-z]_`, `sk-`, etc) — decide on first PR review.

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
