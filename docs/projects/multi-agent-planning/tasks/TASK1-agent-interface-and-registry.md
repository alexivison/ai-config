# Task 1 — Agent Interface, Registry, Config, and Providers

**Dependencies:** None
**Branch:** `feature/multi-agent-planning`

## Goal

Create the foundation layer: a Go `Agent` interface, a `Registry` that loads agent/role definitions from `.party.toml`, a config parser, built-in providers (Claude, Codex, stub), and a `party-cli agent query` subcommand for shell hook consumption. Nothing uses this yet — later tasks wire it into session lifecycle, TUI, and hooks.

## Scope Boundary

**In scope:**
- `tools/party-cli/internal/agent/agent.go` — `Agent` interface, `AgentState`, `CmdOpts` types
- `tools/party-cli/internal/agent/role.go` — `Role` type, `RoleBinding`
- `tools/party-cli/internal/agent/registry.go` — `Registry` type with resolution methods
- `tools/party-cli/internal/agent/config.go` — `.party.toml` parsing + default config generation
- `tools/party-cli/internal/agent/claude.go` — Claude provider implementation
- `tools/party-cli/internal/agent/codex.go` — Codex provider implementation
- `tools/party-cli/internal/agent/stub.go` — Example stub provider for reference
- `tools/party-cli/internal/agent/agent_test.go` — Unit tests
- `tools/party-cli/cmd/agent.go` — `party-cli agent query` subcommand
- `tools/party-cli/go.mod` / `go.sum` — Add TOML dependency

**Out of scope:**
- Modifying `internal/session/` (Task 2)
- Modifying `internal/tui/` (Task 5)
- Modifying hooks (Task 7)
- Modifying manifest (Task 2)

## Reference Files

Study these files to understand the patterns being extracted:

### Command building (extract into providers)

- `tools/party-cli/internal/session/start.go` lines 53-55 — `resolveBinary()` pattern for finding agent binaries
- `tools/party-cli/internal/session/start.go` lines 172-180 — `resolveBinary()` function signature
- `tools/party-cli/internal/session/start.go` lines 195-199 — `masterSystemPrompt` constant (becomes `Claude.MasterPrompt()`)
- `tools/party-cli/internal/session/start.go` lines 202-218 — `buildClaudeCmd()` function — the exact flags: `--permission-mode bypassPermissions`, `--effort high` (master only), `--append-system-prompt` (master only), `--name`, `--resume`, `--` prompt
- `tools/party-cli/internal/session/start.go` lines 222-229 — `buildCodexCmd()` function — the exact flags: `--dangerously-bypass-approvals-and-sandbox`, `resume` subcommand (not `--resume`)
- `tools/party-cli/internal/session/start.go` lines 231-238 — `clearClaudeCodeEnv()` — Claude-specific pre-launch cleanup (unset `CLAUDECODE` env var from tmux)

### State reading (extract into providers)

- `tools/party-cli/internal/tui/sidebar_status.go` — `ReadCodexStatus()` function reads `codex-status.json` from `/tmp/<sessionID>/`. The JSON schema is `{state, target, mode, verdict, started_at, finished_at, error}`.
- `tools/party-cli/internal/tui/sidebar_status.go` — `ReadClaudeState()` function reads `claude-state.json`. Returns a simple state string.
- `session/party-lib.sh` lines 24-59 — `write_codex_status()` shows the Codex status JSON schema being written.

### Config resolution pattern

- `tools/party-cli/internal/config/resolve.go` — `ShellQuote()` for safe shell embedding. The agent `BuildCmd()` must use this same pattern.
- `tools/party-cli/internal/config/resolve.go` — `ResolvePartyCLICmd()` shows the binary resolution pattern (check PATH, fall back to `go run`).

### Existing companion-abstraction design (reference, not implement)

- `docs/projects/companion-abstraction/DESIGN.md` lines 104-142 — The `Companion` interface from the companion-abstraction project. Our `Agent` interface is broader (covers primary too) but draws from this.

## Files to Create/Modify

| File | Action | Estimated Lines |
|------|--------|-----------------|
| `tools/party-cli/internal/agent/agent.go` | Create | ~80 |
| `tools/party-cli/internal/agent/role.go` | Create | ~30 |
| `tools/party-cli/internal/agent/registry.go` | Create | ~80 |
| `tools/party-cli/internal/agent/config.go` | Create | ~100 |
| `tools/party-cli/internal/agent/claude.go` | Create | ~90 |
| `tools/party-cli/internal/agent/codex.go` | Create | ~70 |
| `tools/party-cli/internal/agent/stub.go` | Create | ~50 |
| `tools/party-cli/internal/agent/agent_test.go` | Create | ~250 |
| `tools/party-cli/cmd/agent.go` | Create | ~70 |
| `tools/party-cli/go.mod` | Modify | +1 dep |

## Requirements

### Agent Interface

See DESIGN.md § Agent Interface for the full type definition. Key methods:

- `Name()` — unique identifier (`"claude"`, `"codex"`, `"gemini"`)
- `DisplayName()` — human-facing label (`"Claude"`, `"The Wizard"`)
- `Binary()` — executable name (`"claude"`, `"codex"`)
- `BuildCmd(CmdOpts) string` — returns the full shell command string to launch the agent
- `ResumeKey() string` — manifest extra key for the agent's resume/session ID
- `ResumeFileName() string` — file name in runtime dir for the resume ID (e.g. `"claude-session-id"`, `"codex-thread-id"`)
- `EnvVar() string` — tmux environment variable name for resume ID
- `MasterPrompt() string` — prompt to inject when this agent is the primary in a master session
- `StateFileName() string` — name of the state JSON file in the runtime dir
- `ReadState(runtimeDir string) (AgentState, error)` — read and normalize the agent's state
- `FilterPaneLines(raw string, max int) []string` — extract meaningful lines from pane capture
- `PreLaunchSetup(ctx, client, session) error` — agent-specific setup before launch
- `BinaryEnvVar() string` — environment variable that overrides binary path (`"CLAUDE_BIN"`)
- `FallbackPath() string` — default binary path when not found on PATH or in env

### Claude Provider (`claude.go`)

Extract from `buildClaudeCmd()` at `start.go:202-218`:

```go
func (c *Claude) BuildCmd(opts CmdOpts) string {
    cmd := fmt.Sprintf("export PATH=%s; unset CLAUDECODE; exec %s --permission-mode bypassPermissions",
        config.ShellQuote(opts.AgentPath), config.ShellQuote(binary))
    if opts.Master {
        cmd += " --effort high"
        cmd += " --append-system-prompt " + config.ShellQuote(c.MasterPrompt())
    }
    if opts.Title != "" {
        cmd += " --name " + config.ShellQuote(opts.Title)
    }
    if opts.ResumeID != "" {
        cmd += " --resume " + config.ShellQuote(opts.ResumeID)
    }
    if opts.Prompt != "" {
        cmd += " -- " + config.ShellQuote(opts.Prompt)
    }
    return cmd
}
```

- `Name()` = `"claude"`, `DisplayName()` = `"Claude"`, `Binary()` = `"claude"`
- `ResumeKey()` = `"claude_session_id"`, `EnvVar()` = `"CLAUDE_SESSION_ID"`
- `BinaryEnvVar()` = `"CLAUDE_BIN"`, `FallbackPath()` = `"~/.local/bin/claude"` (expand `~` at runtime)
- `ResumeFileName()` = `"claude-session-id"`
- `StateFileName()` = `"claude-state.json"`
- `MasterPrompt()` = the `masterSystemPrompt` constant from `start.go:195-199`
- `PreLaunchSetup()` = unset `CLAUDECODE` env var (from `clearClaudeCodeEnv()`)
- `ReadState()` reads `claude-state.json` — simple `{"state": "active"|"idle"|...}` format
- `FilterPaneLines()` = filter agent metadata lines (like the current pane capture logic)

### Codex Provider (`codex.go`)

Extract from `buildCodexCmd()` at `start.go:222-229`:

```go
func (c *Codex) BuildCmd(opts CmdOpts) string {
    cmd := fmt.Sprintf("export PATH=%s; exec %s --dangerously-bypass-approvals-and-sandbox",
        config.ShellQuote(opts.AgentPath), config.ShellQuote(binary))
    if opts.ResumeID != "" {
        cmd += " resume " + config.ShellQuote(opts.ResumeID) // NOTE: "resume" is a subcommand, not a flag
    }
    return cmd
}
```

- `Name()` = `"codex"`, `DisplayName()` = `"The Wizard"`, `Binary()` = `"codex"`
- `ResumeKey()` = `"codex_thread_id"`, `EnvVar()` = `"CODEX_THREAD_ID"`
- `BinaryEnvVar()` = `"CODEX_BIN"`, `FallbackPath()` = `"/opt/homebrew/bin/codex"`
- `ResumeFileName()` = `"codex-thread-id"`
- `StateFileName()` = `"codex-status.json"`
- `MasterPrompt()` = `""` (Codex doesn't support `--append-system-prompt`; master prompt goes via initial `--prompt` if Codex is primary)
- `PreLaunchSetup()` = no-op
- `ReadState()` reads `codex-status.json` — schema: `{state, target, mode, verdict, started_at, finished_at, error}`
- Note: Codex ignores `opts.Title` and `opts.Master` in `BuildCmd()` — those are Claude-specific flags

### Stub Provider (`stub.go`)

Minimal documented example. Returns static values. `BuildCmd()` returns `echo "stub agent — not a real CLI"`.

### Config Parser (`config.go`)

Parse `.party.toml` into:

```go
type Config struct {
    Agents map[string]AgentConfig `toml:"agents"`
    Roles  RolesConfig            `toml:"roles"`
}

type AgentConfig struct {
    CLI string `toml:"cli"` // binary name override (optional)
}

type RolesConfig struct {
    Primary   *RoleConfig `toml:"primary"`
    Companion *RoleConfig `toml:"companion"`
}

type RoleConfig struct {
    Agent  string `toml:"agent"`  // references agents map key
    Window int    `toml:"window"` // tmux window index, default: -1 for primary, 0 for companion
}
```

Resolution order: CLI flags → `.party.toml` in CWD → walk up to git root → hardcoded defaults. Use `github.com/BurntSushi/toml`.

The config parser should accept optional overrides that take precedence over the file:

```go
type ConfigOverrides struct {
    Primary     string // agent name to use as primary (empty = no override)
    Companion   string // agent name to use as companion (empty = no override)
    NoCompanion bool   // if true, remove companion role entirely
}

func LoadConfig(cwd string, overrides *ConfigOverrides) (*Config, error)
```

`LoadConfig` parses `.party.toml` (or defaults), then applies overrides if non-nil. This allows CLI flags (`--primary codex`, `--companion claude`, `--no-companion`) to override per-session without changing the file. The overrides only affect the `[roles]` section — agent definitions come from the file or defaults.

Default config (no file found, no overrides):

```go
func DefaultConfig() *Config {
    return &Config{
        Agents: map[string]AgentConfig{
            "claude": {CLI: "claude"},
            "codex":  {CLI: "codex"},
        },
        Roles: RolesConfig{
            Primary:   &RoleConfig{Agent: "claude", Window: -1},
            Companion: &RoleConfig{Agent: "codex", Window: 0},
        },
    }
}
```

### Registry (`registry.go`)

```go
func NewRegistry(cfg *Config) (*Registry, error)
func (r *Registry) Get(name string) (Agent, error)
func (r *Registry) ForRole(role Role) (*RoleBinding, error)
func (r *Registry) Bindings() []*RoleBinding  // primary first
func (r *Registry) HasRole(role Role) bool
func (r *Registry) Names() []string
```

The registry maps config agent names to built-in provider constructors. Unknown agent names return an error. To add a new agent, add a Go file implementing `Agent` and register it in the constructor map.

### `party-cli agent query` subcommand (`cmd/agent.go`)

Three query modes (newline-delimited plain text output):

- `party-cli agent query roles` — lists configured role names (e.g. "primary\ncompanion")
- `party-cli agent query names` — lists configured agent names (e.g. "claude\ncodex")
- `party-cli agent query primary-name` — prints the primary agent name
- `party-cli agent query companion-name` — prints the companion agent name (empty if none)
- `party-cli agent query evidence-required` — lists required evidence types

This subcommand reads `.party.toml` and resolves the registry. It's the bridge for shell hooks (Task 7) that cannot import Go packages.

Register the subcommand in `cmd/root.go` via `root.AddCommand(newAgentCmd(repoRoot))`.

## Tests

### Registry tests
- `NewRegistry` with no `.party.toml`, no overrides → returns registry with two bindings (primary=claude, companion=codex)
- `NewRegistry` with `.party.toml` setting codex as primary → primary binding returns Codex
- `NewRegistry` with `.party.toml` omitting companion → `HasRole(RoleCompanion)` returns false
- `LoadConfig` with overrides `{Primary: "codex"}` → primary role uses Codex regardless of file
- `LoadConfig` with overrides `{NoCompanion: true}` → companion role absent
- `LoadConfig` with overrides `{Companion: "claude"}` on a file that sets codex as companion → Claude wins
- `Get("claude")` returns Claude agent with correct metadata
- `Get("unknown")` returns error
- `ForRole(RolePrimary)` returns the primary binding
- `ForRole(RoleCompanion)` when no companion configured → returns error

### Provider tests
- Claude `BuildCmd()` with no resume, no prompt → `"export PATH=...; unset CLAUDECODE; exec .../claude --permission-mode bypassPermissions"`
- Claude `BuildCmd()` with resume, prompt, title → includes `--resume`, `--name`, `-- "prompt"`
- Claude `BuildCmd()` with `Master=true` → includes `--effort high` and `--append-system-prompt`
- Codex `BuildCmd()` with resume → includes `resume <id>` (not `--resume`)
- Codex `BuildCmd()` with no resume → no `resume` subcommand
- Claude `ResumeKey()` = `"claude_session_id"`, Codex `ResumeKey()` = `"codex_thread_id"`
- Claude `MasterPrompt()` is non-empty, Codex `MasterPrompt()` is empty

### Config tests
- Config resolution with no file → returns default config
- Config resolution with valid `.party.toml` → parses correctly
- Config resolution walks up to git root
- Missing `[roles.companion]` → companion is nil

### CLI tests
- `party-cli agent query roles` outputs `"primary\ncompanion"` for default config
- `party-cli agent query names` outputs `"claude\ncodex"` for default config
- `party-cli agent query primary-name` outputs `"claude"` for default config

## Acceptance Criteria

- [x] `Agent` interface defined with all methods from DESIGN.md
- [x] `Role` type and `RoleBinding` struct defined
- [x] `Registry` loads from `.party.toml` or defaults
- [x] Claude provider produces identical commands to current `buildClaudeCmd()`
- [x] Codex provider produces identical commands to current `buildCodexCmd()`
- [x] Stub provider exists as documented example
- [x] Config parser handles missing file gracefully
- [x] TOML dependency added to `go.mod`
- [x] `party-cli agent query` subcommand works
- [x] All tests pass
- [x] No existing files modified except `go.mod`, `go.sum`, and adding `newAgentCmd()` to `cmd/root.go`
