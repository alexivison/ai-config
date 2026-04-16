# Task 2 — Agent-Agnostic Session Lifecycle

**Dependencies:** Task 1
**Branch:** `feature/multi-agent-planning`

## Goal

Refactor `internal/session/start.go` and `internal/session/continue.go` to use the agent registry instead of hardcoded `buildClaudeCmd()`/`buildCodexCmd()` functions. Evolve the manifest schema to store agents generically. After this task, session startup and resume work through the registry — but layouts still use old role names (Task 3 handles that).

## Scope Boundary

**In scope:**
- `tools/party-cli/internal/session/start.go` — Replace `resolveBinary()` calls, delete `buildClaudeCmd()`/`buildCodexCmd()`/`clearClaudeCodeEnv()`/`masterSystemPrompt`, refactor `persistResumeIDs()`/`setResumeEnv()`
- `tools/party-cli/internal/session/launch.go` — Refactor `launchConfig` struct and `launchSession()` to use agent registry
- `tools/party-cli/internal/session/continue.go` — Read `manifest.Agents[]` for resume IDs
- `tools/party-cli/internal/session/service.go` — Add `Registry` field to `Service`
- `tools/party-cli/internal/state/manifest.go` — Add `Agents []AgentManifest` typed field with backward-compat migration
- `tools/party-cli/cmd/start.go` — Pass registry to service

**Out of scope:**
- Layout functions (Task 3)
- TUI changes (Task 5)
- Hook changes (Task 7)
- CLI flag changes (Task 8 — keep `--resume-claude`/`--resume-codex` working for now)

## Reference Files

### Session start (the main file being refactored)

- `tools/party-cli/internal/session/start.go` — **Read the entire file.** Key sections:
  - Lines 17-27: `StartOpts` struct — has `ClaudeResumeID` and `CodexResumeID` fields that become generic
  - Lines 36-128: `Start()` method — the full flow from binary resolution to launch
  - Lines 53-55: `resolveBinary()` calls — replaced by `agent.BinaryEnvVar()` + PATH + `agent.FallbackPath()`
  - Lines 59-66: Manifest creation with `ClaudeBin`, `CodexBin`, `AgentPath` — becomes `Agents[]`
  - Lines 81-97: Writing resume IDs and extra fields to manifest — becomes agent loop
  - Lines 109-123: Building `launchConfig` with `claudeBin`, `codexBin`, `claudeResumeID`, `codexResumeID` — becomes `agentSpecs []AgentLaunchSpec`
  - Lines 172-180: `resolveBinary()` function — keep as utility but providers specify env var + fallback
  - Lines 195-199: `masterSystemPrompt` constant — moves to `Claude.MasterPrompt()`
  - Lines 202-229: `buildClaudeCmd()` and `buildCodexCmd()` — **DELETE** (logic now in providers from Task 1)
  - Lines 231-269: Helper functions — refactor to iterate agents

### Launch config (refactored struct)

- `tools/party-cli/internal/session/launch.go` — **Read the entire file.** Key sections:
  - Lines 8-22: `launchConfig` struct — replace `claudeBin`/`codexBin`/`claudeResumeID`/`codexResumeID` with role→command map
  - Lines 27-81: `launchSession()` — builds commands and delegates to layout. Refactor to iterate agent bindings

### Session continue (resume path)

- `tools/party-cli/internal/session/continue.go` — **Read the entire file.** Key sections:
  - Lines 65-69: Reads `claude_session_id` and `codex_thread_id` from manifest extras — becomes agent loop over `manifest.Agents[]`
  - Lines 82-96: Builds `launchConfig` with per-agent resume IDs

### Service struct

- `tools/party-cli/internal/session/service.go` — Lines 17-28: `Service` struct. Add a `Registry *agent.Registry` field.

### Manifest

- `tools/party-cli/internal/state/manifest.go` — **Read the entire file.** Key sections:
  - Lines 12-28: `Manifest` struct — has `ClaudeBin`, `CodexBin` fields to deprecate
  - Lines 31-36: `knownKeys` map — add `"agents"` to it
  - Lines 39-61: `UnmarshalJSON` — add migration from old fields to `Agents[]`
  - Lines 88-107: `ExtraString()` / `SetExtra()` — still used for non-agent extras

### Agent package (from Task 1)

- `tools/party-cli/internal/agent/` — The `Agent` interface, `Registry`, `RoleBinding` types. `ForRole()` to get agent for a role. `BuildCmd()` to generate the command string.

## Files to Create/Modify

| File | Action | Key Changes |
|------|--------|-------------|
| `tools/party-cli/internal/state/manifest.go` | Modify | Add `AgentManifest` type and `Agents []AgentManifest` field; backward-compat migration in `UnmarshalJSON`; add `"agents"` to `knownKeys` |
| `tools/party-cli/internal/session/start.go` | Modify | Replace binary resolution with registry; delete `buildClaudeCmd`, `buildCodexCmd`, `clearClaudeCodeEnv`, `masterSystemPrompt`; loop agents for resume/env |
| `tools/party-cli/internal/session/launch.go` | Modify | Replace `launchConfig` fields with `agents map[agent.Role]string` (role→command); `launchSession()` iterates bindings |
| `tools/party-cli/internal/session/continue.go` | Modify | Read `manifest.Agents[]` for resume IDs; fallback to old extras if `Agents` empty |
| `tools/party-cli/internal/session/service.go` | Modify | Add `Registry *agent.Registry` field to `Service`; accept in `NewService()` |
| `tools/party-cli/cmd/start.go` | Modify | Create registry, pass to `NewService()`; `StartOpts` uses generic resume map |
| `tools/party-cli/cmd/spawn.go` | Modify | Same registry passing as start.go |
| `tools/party-cli/cmd/continue.go` | Modify | Same registry passing |

## Requirements

### Manifest Schema Addition

```go
// AgentManifest stores per-agent state in the manifest.
type AgentManifest struct {
    Name     string `json:"name"`      // "claude", "codex"
    Role     string `json:"role"`      // "primary", "companion"
    CLI      string `json:"cli"`       // resolved binary path
    ResumeID string `json:"resume_id"` // session/thread ID for resumption
    Window   int    `json:"window"`    // tmux window index
}
```

Add to `Manifest` struct:
```go
Agents []AgentManifest `json:"agents,omitempty"`
```

Add `"agents"` to `knownKeys` map.

### Backward-Compatible Migration

In `UnmarshalJSON`, after parsing, if `Agents` is empty but old fields exist:
```go
if len(m.Agents) == 0 {
    if m.ClaudeBin != "" || m.ExtraString("claude_session_id") != "" {
        // Window depends on session type: master uses window 0 for single-window,
        // sidebar uses window 1 for workspace. Default to 1 (most common case).
        claudeWindow := 1
        if m.SessionType == "master" {
            claudeWindow = 0
        }
        m.Agents = append(m.Agents, AgentManifest{
            Name: "claude", Role: "primary", CLI: m.ClaudeBin,
            ResumeID: m.ExtraString("claude_session_id"), Window: claudeWindow,
        })
    }
    if m.CodexBin != "" || m.ExtraString("codex_thread_id") != "" {
        m.Agents = append(m.Agents, AgentManifest{
            Name: "codex", Role: "companion", CLI: m.CodexBin,
            ResumeID: m.ExtraString("codex_thread_id"), Window: 0,
        })
    }
}
```

**Important:** The top-level `AgentPath` field is preserved as-is (not moved into `AgentManifest`). It's a session-wide PATH string shared by all agents, not per-agent state. New manifests continue to write `agent_path` at the top level.

### Launch Config Refactor

Replace:
```go
type launchConfig struct {
    claudeBin, codexBin, claudeResumeID, codexResumeID string
    // ...
}
```

With:
```go
type launchConfig struct {
    sessionID  string
    cwd        string
    runtimeDir string
    title      string
    agentPath  string
    prompt     string
    master     bool
    worker     bool
    layout     LayoutMode
    // Role→command map: built from registry
    agentCmds  map[agent.Role]string  // e.g. {RolePrimary: "exec claude ...", RoleCompanion: "exec codex ..."}
    // Role→resume ID map: for env vars and runtime files
    agentResume map[agent.Role]resumeInfo
}

type resumeInfo struct {
    agentName string
    envVar    string
    resumeID  string
}
```

### Start() Flow Change

1. Load registry (from service)
2. For each binding in `registry.Bindings()`:
   - Resolve binary: check `agent.BinaryEnvVar()` env → `exec.LookPath(agent.Binary())` → `agent.FallbackPath()`
   - If missing and role is companion: warn, skip. If primary: error.
   - Call `agent.PreLaunchSetup(ctx, client, sessionID)`
   - Build `CmdOpts` from `StartOpts` (resume ID, prompt, title, master)
   - Call `agent.BuildCmd(opts)` → store in `agentCmds[role]`
3. Write `manifest.Agents[]` with resolved info
4. Continue to layout (passes `agentCmds` map)

**CRITICAL**: The `StartOpts` struct still has `ClaudeResumeID`/`CodexResumeID` for now (CLI flag compat — Task 8 changes the flags). Map these to the correct agent by name in `Start()`:
```go
resumeMap := map[string]string{}
if opts.ClaudeResumeID != "" { resumeMap["claude"] = opts.ClaudeResumeID }
if opts.CodexResumeID != ""  { resumeMap["codex"] = opts.CodexResumeID }
```

## Tests

- Start with default registry → `agentCmds` has primary (claude) and companion (codex) commands
- Start with Codex-as-primary registry → `agentCmds[RolePrimary]` contains Codex command
- Start with no companion → `agentCmds` only has primary
- Continue with new manifest (`Agents[]`) → resume IDs correctly passed
- Continue with old manifest (no `Agents[]`, has `claude_session_id` extra) → migration populates `Agents[]`
- Manifest round-trip: write `Agents[]` → read back → fields preserved
- `buildClaudeCmd()` and `buildCodexCmd()` no longer exist (compilation check)
- Existing tests in `session_test.go` that tested `buildClaudeCmd`/`buildCodexCmd`/`persistResumeIDs`/`setResumeEnv`/`clearClaudeCodeEnv` are updated or replaced with equivalent provider tests

**Note on `persistResumeIDs`:** The refactored version should iterate agents and use `agent.ResumeFileName()` to derive the file name (e.g. `"claude-session-id"` → `filepath.Join(rtDir, agent.ResumeFileName())`).

## Acceptance Criteria

- [x] `buildClaudeCmd()` and `buildCodexCmd()` deleted from `start.go`
- [x] `masterSystemPrompt` constant deleted (lives in Claude provider)
- [x] `clearClaudeCodeEnv()` deleted (lives in Claude `PreLaunchSetup()`)
- [x] `launchConfig` uses `agentCmds map[agent.Role]string`
- [x] `Start()` iterates registry bindings
- [x] `Continue()` reads `manifest.Agents[]` with old-format fallback
- [x] `Manifest.Agents` field exists with JSON serialization
- [x] Old manifests migrate to `Agents[]` on read
- [x] All existing session tests still pass
