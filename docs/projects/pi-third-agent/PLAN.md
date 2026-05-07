# Pi as a Third Agent

> **Goal:** `party-cli config set-companion pi` (or `set-primary pi`) launches a working Pi pane that participates in master/worker sessions, accepts relay/broadcast, returns readable output via `read`, and resumes across `continue`.
>
> **Approach:** Add Pi (`@mariozechner/pi-coding-agent`) as a third selectable provider alongside Claude and Codex. Zero regression for existing setups. Hooks, skills, subagents, and evidence governance remain Claude/Codex-only — Pi panes run "naked" with our master/worker prompts in this phase. Existing Claude/Codex hooks continue firing on their own panes regardless of which agent is the other party.

This plan is the first milestone of a longer migration that could eventually replace Claude Code and Codex entirely with Pi. See [Background](#background) for the broader research that motivated this scoping.

## Phases

| Phase | Deliverable | Effort | Depends on | Status |
|---|---|---|---|---|
| 0 | Reconnaissance — verify Pi's actual flag and output behavior | ½ day | — | ✅ Done |
| 1 | Pi provider stub in `internal/agent/pi.go` + registry wiring | 1 day | Phase 0 | ✅ Done |
| 2 | Output filter strategy for Pi panes (`read` command) | ½–1½ days | Phase 1 | ✅ Code complete — `party-cli read` uses the Pi activity sidecar first, then cleaned raw pane fallback |
| 3 | Resume-ID plumbing | ½–1½ days | Phase 0 | ✅ Code complete — Pi UUID is extracted from sidecar/session files, persisted, and passed to `continue` |
| 4 | Tests and integration wiring | 1 day | Phases 1–3 | ✅ Code complete — targeted Pi read/resume coverage added; manual validation still pending |
| 5 | Manual end-to-end validation | ½ day | Phase 4 | 🟡 Partial — standalone Pi/activity validated; full role-swap and transport matrix still missing |
| 6 | Docs and migration notes | ½ day | Phase 5 | ✅ Code complete — README, Claude/Codex role docs, and Pi limitations doc updated; manual validation still pending |

**Total budget:** ~4–6 working days. The wider end accounts for Phase 2's JSON-sidecar branch and Phase 3's indirection branch (both decided by Phase 0).

## Completed so far

- [x] Phase 0 reconnaissance captured in `docs/projects/pi-third-agent/RECON.md`
- [x] Pi provider added in `tools/party-cli/internal/agent/pi.go`
- [x] Pi registered in the party-cli agent registry and default config
- [x] Pi artifact prune paths added for `~/.pi/agent/sessions` and `~/.pi/agent/git`
- [x] Pi launch command supports system prompts, thinking level, resume flag, positional prompt, and activity sidecar env
- [x] Generic Pi activity sidecar extension writes JSON activity state
- [x] Tracker and `party-cli sessions` consume Pi activity sidecars
- [x] Tracker preserves last non-empty snippet when a refresh returns empty
- [x] `party-cli read` for Pi consumes sidecar `recent`/`snippet` output before falling back to cleaned raw pane capture with a header
- [x] Pi resume UUIDs are parsed from sidecar `pi_session_id` or `session_file` values and sanitized before use
- [x] Pi resume UUIDs are persisted into `agents[].resume_id` and `pi_session_id`; `continue` relaunches Pi with `--session` and `PI_SESSION_ID`
- [x] Running-session `continue` reattach remains manifest-tolerant while opportunistically persisting Pi resume IDs
- [x] Targeted tests cover Pi read sidecar/fallback behavior, non-Pi read filtering, resume parsing/persistence, cleanup-script persistence, and manifest sanitization
- [x] README, Claude/Codex role docs, and `docs/pi-companion.md` document Pi as a third selectable agent with current limitations
- [x] Current test suite passes with `cd tools/party-cli && go test ./...`

## Phase 0 — Reconnaissance ✅ Done

The earlier research was ~85% derived from Pi's docs. Seven facts must be verified on a real Pi binary before code is written; each one determines a branch in Phases 1–3.

| # | Question | How to answer | Decision it unblocks |
|---|---|---|---|
| 0.1 | Do `--append-system-prompt`, `--no-session`, `--session <id>`, `--mode json`, `--mode rpc`, `--thinking <level>` exist? Is `--session` a flag (Claude-style) or positional subcommand (Codex-style `resume <id>`)? | `pi --help`, `pi --version` | Whether the BuildCmd shape works at all; whether master pane can request high effort |
| 0.2 | What does a Pi session ID look like? Path, UUID, short token, or none-exposed? | `pi -p "hi"; ls -la ~/.pi/agent/sessions/`; inspect `--mode json` output for any session-ID emission | Whether `validResumeID` regex needs relaxing |
| 0.3 | Does `--session <id> --append-system-prompt "..."` re-apply the prompt cleanly on resume? | Launch with prompt, kill, resume same flags, observe behavior | Whether `continue.go` can pass `MasterPrompt()` every time or must persist it |
| 0.4 | What does `pi --mode json -p "list files"` actually emit? | Capture stdout to a file; inspect JSONL events | Whether `read.go` can pivot to JSON ingestion or must keep capture-pane |
| 0.5 | What does an interactive Pi pane look like under `tmux capture-pane`? Glyph prefixes? Differential render artifacts? | Run Pi in tmux, `tmux capture-pane -p -S -200` after each tool call | Whether we need a `FilterPiLines` at all |
| 0.6 | How is the initial user-turn prompt delivered? Positional arg, stdin, dedicated flag? | `pi "hello"`, `echo "hello" \| pi`, `pi --help \| grep -i prompt` | Whether `BuildCmd` ends with `<positional-prompt>` or relies on post-launch `tmux send-keys` |
| 0.7 | What `PI_*` env vars does Pi read at launch? Any collision with our planned `PI_SESSION_ID`? | `pi --help`, grep `pi-mono` source/README for env-var references | Whether `EnvVar()` needs renaming, and whether `PreLaunchSetup` needs to unset something the way Claude unsets `CLAUDECODE` |

**Deliverable:** `docs/projects/pi-third-agent/RECON.md` answering all seven with output snippets. ✅ Done

## Phase 1 — Provider Stub ✅ Done

**Files to create**

- `tools/party-cli/internal/agent/pi.go` — implements `agent.Agent` (13 interface methods) plus a `NewPi(cfg AgentConfig) *Pi` constructor for the registry to call

**Files to edit**

- `tools/party-cli/internal/agent/registry.go` — register `"pi"` in `providerConstructors`
- `tools/party-cli/internal/agent/config.go` — add `pi` to `DefaultConfig().Agents` (do **not** change default `Roles`; Claude+Codex stay default)
- `tools/party-cli/cmd/prune.go` — add `~/.pi/agent/sessions`, `~/.pi/agent/git` to `runPruneArtifacts` path list

**Pi provider methods (proposed values; some defer to Phase 0 outcomes)**

| Method | Value | Notes |
|---|---|---|
| `Name()` | `"pi"` | |
| `DisplayName()` | `"Pi"` | |
| `Binary()` | `cfg.CLI` or `"pi"` | |
| `ResumeKey()` | `"pi_session_id"` | rename if 0.7 reveals collision |
| `ResumeFileName()` | `"pi-session-id"` | |
| `EnvVar()` | `"PI_SESSION_ID"` | rename if 0.7 reveals Pi already reads this |
| `BinaryEnvVar()` | `"PI_BIN"` | |
| `FallbackPath()` | `"/opt/homebrew/bin/pi"` (mirror Codex) | confirm in 0.7 against `which pi` after `npm install -g`; alternative `/usr/local/bin/pi` for non-Homebrew |
| `MasterPrompt()` | Same content as Claude's `MasterPrompt` with the agent-name token replaced ("Claude" → "Pi"); leave proper nouns like "Claude Code" and file paths unchanged | |
| `WorkerPrompt()` | Same as Claude's, same substitution rule | |
| `FilterPaneLines()` | Stub returning `tmux.FilterAgentLines` until Phase 2 lands the real implementation | |
| `PreLaunchSetup()` | TBD by 0.7 — likely no-op, but must clear any colliding `PI_*` var Pi reads at launch (mirroring Claude's `CLAUDECODE` unset) | |
| `BuildCmd(opts)` | See below | |

**`BuildCmd` proposed shape** (final shape decided by 0.1 and 0.6)

```
export PATH=<agentPath>; exec pi
  [--append-system-prompt <MasterPrompt or WorkerPrompt+SystemBrief>]
  [--thinking high]                                 # master only, if 0.1 confirms flag
  [--session <ResumeID>]                            # or "resume <ResumeID>" if subcommand-style
  [<initial-prompt>]                                # only if 0.6 confirms positional acceptance
```

The Phase 1 deliverable is a *stub* — methods compile and snapshot tests pass; full filter behavior lands in Phase 2 and resume-ID nuances in Phase 3.

## Phase 2 — Output Filter Strategy ✅ Code Complete

`internal/message/message.go:filterPrimaryPaneLines` currently has an asymmetric one-arm dispatch — `if primaryAgentName(m) == "codex" → FilterCodexLines, else FilterAgentLines`. Adding Pi means refactoring to a switch (or staying as nested if-else). Pi has no glyph prefixes (component-based rendering), so the right strategy depends on Phase 0:

**Priority order** (pick the first whose Phase 0 evidence supports it):

1. **`--mode json` works cleanly (0.4 confirmed)** → JSON sidecar approach: redirect Pi's JSONL events to `/tmp/<sessionID>/pi-events.jsonl` from `BuildCmd`; have `read.go` parse the last N events and pretty-print. Cleanest long-term, ~1.5 days. Prefer this when feasible.
2. **Stable glyph-like markers visible in capture-pane (0.5 confirmed)** → write `FilterPiLines` in `internal/tmux/capture.go` mirroring `FilterAgentLines`; refactor `filterPrimaryPaneLines` to a switch with `case "pi":`. ~½ day.
3. **Neither works** → `read` returns raw last-N-lines for Pi panes with a `[raw output — Pi has no structured pane format]` header. ~½ day. Acceptable for "third agent" milestone; document the limitation in Phase 6.

**Implemented code path:** `party-cli read` now uses the Pi activity sidecar first (latest `recent` lines, then `snippet`). If no usable sidecar exists, it returns cleaned raw pane lines prefixed with `[raw Pi pane output — no usable activity sidecar]`. Claude and Codex filtering remains unchanged.

The chosen branch keeps the generic `Pi.FilterPaneLines` fallback for non-`read` callers; `message.Read` owns the Pi sidecar/raw fallback path.

## Phase 3 — Resume-ID Plumbing ✅ Code Complete

Implemented outcome: Pi session files expose UUIDs as `<timestamp>_<uuid>.jsonl`, and the sidecar may also expose `pi_session_id` directly. `party-cli` extracts only UUID-shaped values, sanitizes them through the manifest resume-ID policy, persists them to both `agents[].resume_id` and `pi_session_id`, and passes the value back through `--session` plus `PI_SESSION_ID` during `continue`. The running-session reattach fast path keeps manifest access best-effort.

Historical decision tree based on Phase 0 outcome 0.2:

1. **Short tokens matching `[A-Za-z0-9_-]+`** → zero changes
2. **Path-style IDs** → relax the `validResumeID` regex (`internal/state/manifest.go`) to `^[A-Za-z0-9_./-]+$`. Add a unit test for path-traversal rejection (resume IDs are shell-quoted by `config.ShellQuote` already, so the surface is shallow but worth covering). **Note:** `sanitizeResumeID` silently blanks invalid IDs — a too-strict regex makes resume "appear to work but not resume," so debug accordingly.
3. **IDs needing indirection (e.g., long/binary tokens)** → add a `pi-session-map.json` under `~/.party-state/` mapping ULIDs → Pi session paths. Pi provider's `BuildCmd` looks up the path; manifest stores the ULID. ~1 day extra. Avoid if possible.
4. **No exposed session ID at all (resume-by-cwd or auto-only)** → `ResumeKey`/`EnvVar`/`ResumeFileName` become decorative; `BuildCmd` resumes by passing `--no-session=false` and relying on Pi's per-CWD auto-resume. Document the limitation: cross-cwd resume won't work, and `party-cli continue` semantics for Pi panes degrade to "rerun in same cwd."

## Phase 4 — Tests and Wiring ✅ Code Complete

**Targeted coverage added/kept**

- `internal/agent/agent_test.go` — Pi `BuildCmd` includes `--session <uuid>` on resume
- `internal/message/message_test.go` — Pi read prefers the activity sidecar, raw fallback is cleaned and headed, and Claude/Codex filtering is unchanged
- `internal/piactivity/activity_test.go` — Pi resume UUID extraction from `session_file` rejects malformed values
- `internal/session/session_test.go` — `continue` persists Pi resume IDs from activity and uses `--session`/`PI_SESSION_ID`; reattach tolerates missing manifests
- `internal/session/start_test.go` — cleanup script persists Pi resume IDs before removing `/tmp/<session>`
- `internal/state/*_test.go` — `pi_session_id` is sanitized like other provider resume IDs

Manual end-to-end validation remains Phase 5 work.

## Phase 5 — Manual Validation 🟡 Partial

Concrete checklist on a real machine. Steps 1, 2, and 7 also exercise the no-regression invariant for Claude+Codex.

1. `party-cli config set-companion pi`, then `party-cli config show` displays Pi as companion
2. `./session/party.sh "test"` launches a session with Claude primary + Pi companion + shell, all panes alive
3. From the primary pane: `party-cli relay <pi-session-id> "say hello"` delivers the message into the Pi pane
4. Pi receives, processes, replies. (If Pi-as-companion → Claude-primary reply path needs a `tmux-primary.sh` tweak, file a follow-up; not blocking this milestone)
5. `party-cli read <session>` returns something readable from the Pi pane (quality per the Phase 2 branch chosen; documented limitations are acceptable)
6. `party-cli stop` then `party-cli continue <id>` resumes the Pi session with the right resume ID (or per-cwd auto-resume if Phase 3 outcome 4)
7. Swap roles: `set-primary pi`, `set-companion claude`, repeat steps 2–6 — confirms both directions work
8. Regression: with `set-primary claude`, `set-companion codex` (default), repeat steps 2–3 to confirm classic flow unaffected
9. `party-cli prune --artifacts --dry-run` lists Pi paths
10. Run `party-cli prune --artifacts` against a throwaway Pi session and confirm `~/.pi/agent/sessions/<id>` is removed

Anything that fails here goes back to its Phase as a follow-up task.

## Phase 6 — Docs ✅ Code Complete

- [x] Update `README.md` "The Party" table to mention Pi as a third available agent
- [x] Update `README.md` "CLI Installation Methods" with Pi's install command
- [x] Add `docs/pi-companion.md` describing what works and what doesn't (no hooks, no evidence, no governance — explicit "use at own risk for Pi panes"); include the sidecar/raw fallback behavior for `read`
- [x] Update `claude/CLAUDE.md` and `codex/AGENTS.md` to mention Pi as a third option in the Party table

Manual end-to-end validation remains Phase 5 work and is not claimed here.

## Definition of Done

- [ ] `pi install` (npm or homebrew) → `party-cli config set-companion pi` → `./session/party.sh "task"` launches a working 3-pane party with Claude primary + Pi companion + shell
- [ ] Primary can dispatch to Pi via `agent-transport`; Pi can reply via the companion-side transport (or follow-up filed if reply path needs cross-agent fixup)
- [ ] `relay`, `broadcast`, `report`, `workers`, `continue`, `stop`, `delete` all function for Pi panes
- [x] Code path for `read` returns output for Pi panes — sidecar first, cleaned raw fallback with documented header; real-pane manual validation remains pending in Phase 5
- [ ] Role swap works in both directions (Pi-as-primary, Pi-as-companion)
- [ ] `party-cli prune --artifacts` actually removes Pi session artifacts (not just dry-run output)
- [x] `go test ./...` passes for `tools/party-cli`
- [ ] Phase 5 step 8 manual smoke confirms the default Claude/Codex layout still launches and exchanges a relay
- [x] `docs/projects/pi-third-agent/RECON.md` exists with verified Phase 0 answers
- [x] README and CLAUDE.md/AGENTS.md updated to mention Pi as a third option

**Explicitly out of scope for this phase:** hooks, skills, subagents, evidence system, pr-gate. Pi panes have no governance until the full migration (separate project). Existing Claude/Codex hooks continue firing on their own panes regardless of which agent occupies the other role.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Phase 0 reveals a missing flag | Unknown until Phase 0 | Halt; reassess port architecture before any Go work |
| Pi already reads `PI_SESSION_ID` (or another `PI_*` var we collide with), causing wrong-session resumes | Unknown until 0.7 | Rename `EnvVar()`; have `PreLaunchSetup` unset the colliding var the way Claude unsets `CLAUDECODE` |
| Pi session resume doesn't re-inject the system prompt cleanly | Unknown until 0.3 | Persist the prompt to `.pi/SYSTEM.md` per-session as a fallback; document the behavior |
| Pi pane output is genuinely unreadable via `capture-pane` | Unknown until 0.4/0.5 | Phase 2 outcome 1 (JSON sidecar) handles this cleanly; outcome 3 documents the degradation |
| Companion-side `agent-transport` scripts assume Claude/Codex layout — Pi-as-companion reply path may break | Medium | Verify in Phase 5 step 4; patch transport scripts (in scope) if needed |
| `pi-tui` differential rendering breaks `tmux send-keys -l` paste timing | Low | Already have a 15ms `sendEnterDelay`; bump to 30ms for Pi if needed |
| Pi's npm-global binary path varies by system | Low | `FallbackPath` + `PI_BIN` env-var override mirror what we do for Claude/Codex |
| Pi 0.x versioning churn (weekly releases, occasional breaking changes) | Medium | Pin a known-good version; budget quarterly upgrade time |

## Background

Pi is a minimalist MIT-licensed TypeScript terminal coding agent (`@mariozechner/pi-coding-agent`, repo `github.com/badlogic/pi-mono`) launched late 2025. Earlier research established:

- Pi has full feature parity with Claude Code's CLI surface (resume, system prompts, autonomous mode, JSON/RPC output modes)
- Pi reads `CLAUDE.md` and `AGENTS.md` natively as context files (zero rewrite for our rules)
- Pi has a hook system (~25 lifecycle events) that is functionally equivalent to Claude Code's hooks
- Pi has no native subagents but the `pi-subagents` extension provides full parity
- Pi has no native MCP but `pi-mcp-adapter` provides token-efficient integration
- Pi-tui uses component-based rendering with no stable glyph prefixes — RPC/JSON mode is preferred over `capture-pane` for programmatic output ingestion

**None of those parity features are integrated in this milestone.** This plan delivers only the bare provider so that `party-cli` can launch and route to a Pi pane. Hook/subagent/MCP integration belongs to the full-replacement project below.

Full feasibility analysis lives in this PR's description.

This plan deliberately scopes only the "third agent" milestone. Full replacement of Claude Code + Codex by Pi is a separate, larger project (rough order-of-magnitude estimate: several weeks of engineering) that would port hooks, subagents, skills, evidence, and governance. We do that after this milestone proves the foundation works.
