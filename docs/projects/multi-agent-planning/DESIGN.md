# Multi-Agent Planning Design

> **Specification:** [SPEC.md](./SPEC.md)

## Architecture Overview

The design introduces four new concepts:

1. **Agent Interface** — A Go interface (`Agent`) that each CLI agent implements, covering command construction, resume metadata, and state observation
2. **Role System** — A mapping from abstract roles (`primary`, `companion`) to concrete agent providers
3. **Project Config** (`.party.toml`) — Per-repo overrides for agent selection and role assignment
4. **Unified Party Tracker** — A single TUI view replacing both the worker sidebar and master tracker, showing all sessions with master→worker hierarchy

The execution core, sub-agents, evidence system, and shell transport scripts are untouched.

```
┌─────────────────────────────────────────────────┐
│               Session Lifecycle                  │
│  (start, continue, spawn, promote — agent-free)  │
└────────────────────┬────────────────────────────┘
                     │ iterate roles → agents
                     ▼
┌─────────────────────────────────────────────────┐
│           Agent Registry + Role Config           │
│  .party.toml → roles → Agent implementations     │
└───────┬─────────────┬───────────────┬───────────┘
        ▼             ▼               ▼
   ┌─────────┐  ┌──────────┐  ┌────────────┐
   │  Claude  │  │  Codex   │  │   Stub/    │
   │  Agent   │  │  Agent   │  │  Example   │
   └─────────┘  └──────────┘  └────────────┘
```

## Existing Code Standards

| Pattern | Location | How It Applies |
|---------|----------|----------------|
| Role-based pane resolution | `internal/tmux/query.go` (`ResolveRole()`) | Already parameterized by role string — pass role from config instead of hardcoded `"claude"` |
| Manifest extras | `internal/state/manifest.go` (`ExtraString()`) | Per-agent state uses `Agents[]` typed field instead of scattered extras |
| fzf hierarchy | `internal/picker/format.go` | Workers use `│` prefix under masters with `●` — unified tracker adopts same visual language |
| Tmux `@party_role` | `internal/session/layout.go` | Already set per-pane — values change from agent names to role names |
| flock-protected CRUD | `internal/state/store.go` | Unchanged — manifest mutations remain flock-safe |
| Runner interface | `internal/tmux/client.go` (`Runner`) | Enables mocking for agent adapter tests |
| Ticker-based polling | `internal/tui/model.go` | 3-second tick cadence reused by unified tracker |
| Hook PreToolUse | `claude/hooks/codex-gate.sh` | Pattern match on transport command + extract companion name |

## Agent Interface (Go)

```go
// internal/agent/agent.go

// Agent represents any CLI coding agent that can run in a tmux pane.
type Agent interface {
    // Identity
    Name() string        // "claude", "codex", "gemini" — unique identifier
    DisplayName() string // "Claude", "The Wizard", "Gemini" — human-facing label
    Binary() string      // "claude", "codex", "gemini-cli" — executable name

    // CLI Construction
    BuildCmd(opts CmdOpts) string  // Build the full shell command to launch this agent
    ResumeKey() string             // Manifest extra key for resume ID: "claude_session_id"
    EnvVar() string                // tmux env var for resume: "CLAUDE_SESSION_ID"
    MasterPrompt() string          // System/initial prompt for master mode (empty = no injection)

    // Runtime Observation
    StateFileName() string                         // "claude-state.json", "codex-status.json"
    ResumeFileName() string                        // "claude-session-id", "codex-thread-id" — file in runtime dir
    ReadState(runtimeDir string) (AgentState, error) // Read state from runtime dir
    FilterPaneLines(raw string, max int) []string  // Extract meaningful lines from pane capture

    // Lifecycle
    PreLaunchSetup(ctx context.Context, client TmuxClient, session string) error
    BinaryEnvVar() string  // "CLAUDE_BIN", "CODEX_BIN" — env var override for binary path
    FallbackPath() string  // Default binary path if not on PATH or in env
}

type CmdOpts struct {
    AgentPath string // PATH for agent discovery
    ResumeID  string // Session/thread ID for resumption
    Prompt    string // Initial prompt text
    Title     string // Session title (for --name or equivalent)
    Master    bool   // Whether this is a master session primary
}

// AgentState is a normalized state read from an agent's status file.
type AgentState struct {
    State   string // "active", "idle", "working", "waiting", "done", "error", "offline"
    Mode    string // "review", "prompt", etc. (companion-specific)
    Target  string // What the agent is working on
    Verdict string // "APPROVED", "REQUEST_CHANGES", etc.
    Error   string // Error message if state is "error"
}
```

## Role System

```go
// internal/agent/role.go

type Role string

const (
    RolePrimary   Role = "primary"
    RoleCompanion Role = "companion"
)

// RoleBinding maps a role to a specific agent and tmux layout position.
type RoleBinding struct {
    Role     Role
    Agent    Agent
    PaneRole string // @party_role value: same as Role for v1
    Window   int    // tmux window index: -1 = workspace window, 0 = hidden window
}
```

## Registry

```go
// internal/agent/registry.go

type Registry struct {
    agents   map[string]Agent       // name → Agent
    bindings map[Role]*RoleBinding  // role → binding
}

func NewRegistry(cfg *Config) (*Registry, error)
func (r *Registry) Get(name string) (Agent, error)
func (r *Registry) ForRole(role Role) (*RoleBinding, error)
func (r *Registry) Bindings() []*RoleBinding  // in role order: primary first
func (r *Registry) HasRole(role Role) bool
```

## Project Config (`.party.toml`)

```toml
# .party.toml — optional, lives in repo root
# Absence = defaults (Claude as primary, Codex as companion)

[agents.claude]
cli = "claude"

[agents.codex]
cli = "codex"

[roles]
  [roles.primary]
  agent = "claude"

  [roles.companion]
  agent = "codex"
  window = 0           # hidden tmux window (default for companion)

[evidence]
# Override required evidence types for pr-gate.
# Default when companion exists: ["pr-verified", "code-critic", "minimizer", "<companion-name>", "test-runner", "check-runner"]
# Default when no companion:     ["pr-verified", "code-critic", "minimizer", "test-runner", "check-runner"]
# required = ["pr-verified", "code-critic", "minimizer", "test-runner", "check-runner"]
```

### Swapping agents: Codex as primary, Claude as companion

```toml
[agents.codex]
cli = "codex"

[agents.claude]
cli = "claude"

[roles]
  [roles.primary]
  agent = "codex"

  [roles.companion]
  agent = "claude"
  window = 0
```

### Solo mode: primary only, no companion

```toml
[agents.claude]
cli = "claude"

[roles]
  [roles.primary]
  agent = "claude"
```

### Default Config (no `.party.toml`)

When no `.party.toml` exists, the registry produces:

```
primary  → Claude agent, @party_role="primary",  window=workspace
companion → Codex agent,  @party_role="companion", window=0 (hidden)
```

This matches today's behavior exactly.

### Config Resolution Order

1. `.party.toml` in CWD
2. Walk up to git root
3. Hardcoded defaults (Claude primary + Codex companion)

## Manifest Schema Evolution

### Current

```json
{
  "party_id": "party-1234",
  "claude_bin": "/path/to/claude",
  "codex_bin": "/path/to/codex",
  "agent_path": "...",
  "claude_session_id": "uuid",
  "codex_thread_id": "thread-id"
}
```

### New

```json
{
  "party_id": "party-1234",
  "agent_path": "...",
  "agents": [
    {
      "name": "claude",
      "role": "primary",
      "cli": "/path/to/claude",
      "resume_id": "uuid",
      "window": 1
    },
    {
      "name": "codex",
      "role": "companion",
      "cli": "/path/to/codex",
      "resume_id": "thread-id",
      "window": 0
    }
  ]
}
```

### Backward Compatibility

- Old manifests with `claude_bin`/`codex_bin`/`claude_session_id`/`codex_thread_id` are migrated to `Agents[]` on read via `UnmarshalJSON`
- Old fields are kept read-only (not written in new manifests)
- `ClaudeBin`/`CodexBin` struct fields remain in Go for deserialization but are deprecated

## Unified Party Tracker TUI

### Motivation

The current TUI has two view modes:

- **Worker sidebar** (`ViewWorker`): Shows Codex status, Wizard pane snippet, evidence. Deeply coupled to Claude+Codex pairing.
- **Master tracker** (`ViewMaster`): Shows worker list with status, stage, Claude state dots. Only available in master sessions.

**Problems:**
1. Two code paths to maintain — every agent abstraction change touches both
2. Worker sidebar is useless without Codex (or with a different companion)
3. Only masters see the session overview — workers and standalone sessions are blind to siblings

### Design: One Tracker for All Sessions

The unified party tracker replaces both views. It shows all active party sessions with master→worker hierarchy, companion status inline, and supports switching between sessions.

```
┌─ Party Tracker ──────────────────────────────┐
│                                              │
│ ● Project Alpha        party-1230   master   │
│ │ fix-auth             party-1231   worker   │
│ │ dark-mode            party-1232   worker   │
│                                              │
│ ● solo task            party-1236   active   │
│                                              │
│ ── this session ──────────────────────────── │
│ party-1230  master  ~/Code/project-b         │
│   companion: codex (idle, APPROVED)          │
│   evidence: code-critic ✓  minimizer ✓       │
│                                              │
│ 4 sessions · j/k ⏎ jump · r relay · s spawn │
└──────────────────────────────────────────────┘
```

### Hierarchy Display

Workers are visually nested under their master, following the picker's established visual language:

| Element | Symbol | Color |
|---------|--------|-------|
| Master session | `●` | Gold (`#ffd700`) |
| Worker (under master) | `│` | Warn/yellow (ANSI 3) |
| Standalone session | `●` | Clean/green (ANSI 2) |
| Stopped/resumable | `○` | Muted (ANSI 8) |

The hierarchy is derived from manifest data: masters have `session_type = "master"` and a `workers[]` array. Workers have a `parent_session` extra field.

### Current Session Detail

The current session (discovered via `PARTY_SESSION` env or tmux) gets an expanded detail section below the session list, showing:

- Session metadata (role, cwd, title)
- Companion status (reading `companion-status-<name>.json` or the agent's `StateFileName()`)
- Evidence summary (from evidence JSONL, same as current worker sidebar)
- Primary agent state dot

This replaces what the worker sidebar currently shows — but in a role-agnostic way.

### Actions

| Key | Action | Context |
|-----|--------|---------|
| `j`/`k` | Navigate session list | Always |
| `Enter` | Jump to selected session (tmux switch) | Always |
| `r` | Relay message to selected worker's primary pane | Master only, worker selected |
| `b` | Broadcast to all workers | Master only |
| `s` | Spawn new worker | Master only |
| `x` | Stop selected worker | Master only |
| `d` | Delete selected worker | Master only |
| `m` | Inspect manifest of selected session | Always |
| `M` | Inspect manifest of current session | Always |
| `q` | Quit TUI | Always |

### Data Flow

The tracker uses the existing `state.Store` to discover all sessions (`DiscoverSessions()`) and `tmux.Client` to check liveness. Master-worker hierarchy is derived from manifest `workers[]` arrays. This is the same data path the picker uses — the tracker just renders it as a live-updating Bubble Tea view instead of a one-shot fzf list.

## @party_role Migration

### Current → New Role Names

| Current `@party_role` | New `@party_role` | Meaning |
|----------------------|-------------------|---------|
| `"claude"` | `"primary"` | The main agent pane |
| `"codex"` | `"companion"` | The secondary agent pane |
| `"shell"` | `"shell"` | User's terminal (unchanged) |
| `"sidebar"` | `"tracker"` | Unified tracker TUI (was sidebar in worker, tracker in master) |
| `"tracker"` | `"tracker"` | Unchanged |

### Backward Compatibility

Shell scripts that resolve panes by role (`party_role_pane_target()`) must accept both old and new names during a transition period. The Go `ResolveRole()` function adds a fallback: if `"primary"` not found, try `"claude"`; if `"companion"` not found, try `"codex"`.

## Session Lifecycle Changes

### Start

Current `launchSession()` calls `buildClaudeCmd()` and `buildCodexCmd()` directly. New flow:

1. Load registry from `.party.toml` (or defaults)
2. For each role binding in `registry.Bindings()`:
   a. Resolve binary via `agent.BinaryEnvVar()` → PATH → `agent.FallbackPath()`
   b. Check binary exists (`exec.LookPath`). If missing: warn and skip (companion) or error (primary)
   c. Call `agent.PreLaunchSetup()` (e.g., clear `CLAUDECODE` env var)
   d. Call `agent.BuildCmd(opts)` to get the shell command string
3. Pass role→command map to layout functions
4. Layout functions use role names for `@party_role`, not agent names

### Continue

Current `Continue()` reads `claude_session_id` and `codex_thread_id` from manifest. New flow:

1. Read `manifest.Agents[]`
2. For each agent entry: look up the agent provider by name, call `BuildCmd()` with the stored `ResumeID`
3. If old manifest (no `Agents[]`): migration in `UnmarshalJSON` populates from legacy fields

### Master Mode

Master mode is a session-level concept, not an agent capability. Any primary agent can orchestrate:

- Claude: receives `masterSystemPrompt` via `--append-system-prompt`
- Codex: receives orchestration instructions via initial prompt (Codex doesn't support system prompt injection at CLI level)
- Other agents: use whatever prompt injection mechanism they support, falling back to initial prompt

Each agent provider implements `MasterPrompt() string`. The session startup passes this to `BuildCmd()` in the appropriate way for that agent.

## Hook Generalization

### Renames

| Current | New | Change |
|---------|-----|--------|
| `codex-gate.sh` | `companion-gate.sh` | Match transport command by companion name via `party-cli agent query` |
| `codex-trace.sh` | `companion-trace.sh` | Evidence type = companion name from config |
| `wizard-guard.sh` | `companion-guard.sh` | Query `party-cli agent query roles` for companion role names |
| `claude-state.sh` | `primary-state.sh` | Query primary agent role from config |

### Hook Bridge: `party-cli agent query`

Shell hooks cannot import Go packages. A `party-cli agent query` subcommand bridges the gap:

```
party-cli agent query roles              # "primary\ncompanion"
party-cli agent query names              # "claude\ncodex"
party-cli agent query primary-name       # "claude"
party-cli agent query companion-name     # "codex" (or empty if none)
party-cli agent query evidence-required  # list required evidence types
```

Reads `.party.toml` using the same resolution logic as the registry.

## Message Prefix Migration

| Current | New | Rationale |
|---------|-----|-----------|
| `[CODEX] message` | `[COMPANION] message` | Role-based, not agent-specific |
| `[CLAUDE] message` | `[PRIMARY] message` | Role-based, not agent-specific |
| `[MASTER] message` | `[MASTER] message` | Unchanged |
| `[WORKER:id] message` | `[WORKER:id] message` | Unchanged |

Transport scripts (`tmux-codex.sh`, `tmux-claude.sh`) keep working but use role-based pane resolution internally. The message prefixes change for new sessions; old sessions in flight keep old prefixes.

## Design Decisions

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| Unified `Agent` interface for both roles | Both primary and companion need: build command, resume, read state. One interface covers both. | Separate `Primary`/`Companion` interfaces (rejected: too much duplication) |
| Role-based `@party_role` values | If panes tagged `"claude"`, swapping to Codex as primary breaks all role lookups. Roles are stable across agent swaps. | Keep agent names (rejected: defeats the purpose) |
| Go interface, not plugin system | Agent CLIs have wildly different flags, resume mechanisms, output formats. Config alone can't handle this. A Go file per agent (~60-80 lines) keeps it testable. | Generic config-driven adapter (rejected: can't generalize completion parsing); Go plugins (rejected: fragile, platform-dependent) |
| Subsume companion-abstraction | Doing companion-only first then re-abstracting primary = touching same files twice. One coherent pass is cleaner. | Sequential projects (rejected: double rework) |
| Build on main, not PR #119 | #119 is open with merge conflicts for 10+ days. Agent abstraction touches mostly different files (session, state, tui vs. transport). | Wait for #119 (rejected: blocks progress on uncertain timeline) |
| Unified tracker replaces both TUI modes | Worker sidebar is deeply Codex-coupled. Two view modes double maintenance. One tracker with hierarchy covers all use cases. | Keep both modes, generalize each (rejected: 2x maintenance surface) |
| Master = session mode, not agent capability | Orchestration is prompt-driven. Any agent that accepts a prompt can orchestrate. | Agent capability flag (rejected: unnecessarily restrictive) |
| Hierarchy via `│` prefix (same as picker) | Users already see this in `party.sh --switch`. Consistent visual language. | Tree lines, indentation only (rejected: less clear parent-child relationship) |

## External Dependencies

- **Go TOML parser:** `github.com/BurntSushi/toml` or `github.com/pelletier/go-toml/v2` for `.party.toml` parsing
- **No new CLI tools required.** Agent CLIs are user-provided.

## Integration Points

| Point | Current Code | Change |
|-------|-------------|--------|
| Command building | `buildClaudeCmd()`, `buildCodexCmd()` in `start.go` | `agent.BuildCmd(opts)` per provider |
| Binary resolution | `resolveBinary("CLAUDE_BIN", ...)` | `agent.BinaryEnvVar()` + `agent.FallbackPath()` |
| Resume ID storage | `claude_session_id`, `codex_thread_id` in extras | `manifest.Agents[].ResumeID` |
| Resume file names | `claude-session-id`, `codex-thread-id` in runtime dir | `agent.ResumeFileName()` per provider |
| Evidence file path | `/tmp/claude-evidence-{session}.jsonl` hardcoded | `/tmp/{primary-name}-evidence-{session}.jsonl` or configurable |
| Pane role tags | `"claude"`, `"codex"` hardcoded | `"primary"`, `"companion"` from role config |
| Pane resolution in messaging | `ResolveRole(_, _, "claude", _)` | `ResolveRole(_, _, primaryRole, _)` |
| TUI worker view | `ViewWorker` + Codex status polling | Unified tracker with per-session detail |
| TUI master view | `ViewMaster` + `TrackerModel` | Same unified tracker (master gets relay/spawn actions) |
| State file reading | `ReadCodexStatus()` hardcoded | `agent.ReadState(runtimeDir)` per provider |
| Window constants | `WindowCodex = 0`, `WindowWorkspace = 1` | From role binding `Window` field |
| Master prompt | `masterSystemPrompt` constant | `agent.MasterPrompt()` per provider |
| CLI flags | `--resume-claude`, `--resume-codex` | `--resume primary=<id>` (old flags kept as hidden aliases) |
