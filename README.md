# ai-config

<p align="center">
  <img src="assets/the-adventuring-party.png" alt="The Adventuring Party — Claude the Warforged Paladin, the Mastermind Rogue, and The Wizard (High Elf)" width="700">
</p>

<p align="center"><em>"Evidence before claims. Tests before implementation."</em></p>

Shared configuration and orchestration for an adventuring party of AI coding assistants. Each member brings unique strengths; this repo equips them through symlink-based installation and launches them side by side in a tmux party session.

## The Party

| Member | Class | Role |
|--------|-------|------|
| **The User** | Mastermind Rogue | Commander and final authority. Leads the party. |
| **Claude** | Warforged Paladin | Living construct of steel and divine fire. Implementation, testing, orchestration. |
| **The Wizard** | High Elf Wizard | Ancient arcanist of deep intellect. Deep reasoning, analysis, review. |

## Structure

```
ai-config/
├── assets/          # Static assets (banner image)
├── claude/          # Claude Code configuration (hooks, skills, agents, rules)
├── codex/           # OpenAI Codex CLI configuration
├── docs/            # Project documentation
├── nvim/            # Neovim (LazyVim) configuration
├── shared/          # Skills shared by both platforms
├── tools/
│   └── party-cli/   # Unified Go binary: TUI + CLI (all session operations)
├── tmux/            # tmux configuration and status scripts
└── README.md
```

## Installation

```bash
# Clone the repo
git clone git@github.com:alexivison/ai-config.git ~/Code/ai-config

# Build and install party-cli
cd ~/Code/ai-config/tools/party-cli
go install .

# Full install (symlinks + CLI installation + auth)
party-cli install

# Or symlinks only (install CLIs yourself)
party-cli install --symlinks-only
```

The installer will:
1. Create config symlinks (`~/.claude`, `~/.codex`, `~/.config/nvim`, `~/.tmux.conf`)
2. Offer to install missing CLI tools (optional)
3. Offer to run authentication for each tool (optional)

### CLI Installation Methods

| Dependency | Install Command |
|------------|-----------------|
| Claude | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` |
| Codex | `brew install --cask codex` |
| tmux | `brew install tmux` |
| fzf | `brew install fzf` |
| Go | `brew install go` *(required — for building party-cli)* |

> **Note:** tmux and fzf are required for party sessions. Go is required to build party-cli, the unified binary that powers all session operations.

## Uninstallation

```bash
party-cli uninstall
```

Removes symlinks but keeps the repository.

## Usage

Launch a party session to run Claude and The Wizard side by side in a three-pane tmux layout:

```bash
party-cli start "my task"
```

### Standard Session

Each party is a standalone tmux session with three panes:

| Pane | Role | Agent |
|------|------|-------|
| 0 | `codex` | The Wizard (Codex CLI) |
| 1 | `claude` | The Paladin (Claude Code) |
| 2 | `shell` | Operator terminal |

### Master Session

A master session replaces the Wizard pane with an interactive tracker TUI. The master Claude acts as an orchestrator, dispatching work to worker sessions instead of implementing directly.

```bash
party-cli start --master "Project Alpha"
```

| Pane | Role | Agent |
|------|------|-------|
| 0 | `tracker` | Party Tracker (Bubble Tea TUI) |
| 1 | `claude` | The Paladin (orchestrator) |
| 2 | `shell` | Operator terminal |

Workers are separate sessions registered under the master:

```bash
party-cli spawn --master-id <master-id> "ENG-456 fix auth"
```

The tracker shows live status of all workers with vim-style navigation. Press `Enter` to jump to a worker, `r` to relay a message, `b` to broadcast, `s` to spawn, `x` to stop.

Any standalone session can be promoted to master mid-flight:

```bash
party-cli promote
```

### Commands

| Command | Description |
|---------|-------------|
| `party-cli start [title]` | Start a new party session |
| `party-cli start --master [title]` | Start a master session (tracker + orchestrator) |
| `party-cli spawn [title]` | Spawn a worker under the current master |
| `party-cli promote [party-id]` | Promote a standalone session to master |
| `party-cli picker` | Interactive session switcher |
| `party-cli continue [party-id]` | Resume a session; opens picker if no ID given |
| `party-cli list` | List active and resumable party sessions |
| `party-cli stop [name]` | Stop one or all party sessions |
| `party-cli transport review <dir>` | Dispatch code review to the Wizard |
| `party-cli transport prompt <text> <dir>` | Dispatch a task to the Wizard |
| `party-cli notify <message>` | Send message from Wizard to Claude |
| `party-cli relay <worker-id> <msg>` | Send message to a worker |
| `party-cli broadcast <msg>` | Send message to all workers |
| `party-cli workers` | List workers and their status |
| `party-cli install` | Install config symlinks and CLI tools |
| `party-cli uninstall` | Remove config symlinks |

### Session Picker

The interactive picker (requires [fzf](https://github.com/junegunn/fzf)) groups sessions hierarchically:

```
party-1741230000  active       solo task          ~/Code/project-a
party-1741234567  master (2)   Project Alpha      ~/Code/project-b
  party-1741234568  worker     ENG-456 fix auth   ~/Code/project-b
  party-1741234569  worker     ENG-789 dark mode  ~/Code/project-b
── resumable ──────────────────────────────
party-1741200000  03/10        old-task           ~/Code/project-c
```

Supports **Enter** to switch/resume, **Ctrl-D** to delete, and **Esc** to cancel.

### State

Party metadata is persisted under `~/.party-state/<party-id>.json`. Runtime handoff files in `/tmp/<party-id>/` are rebuilt on demand. Manifests older than 7 days are auto-pruned on start (configurable via `PARTY_PRUNE_DAYS`).

The transport layer (`party-cli transport`, `party-cli notify`) routes messages by `@party_role` metadata and scans all windows in a session, so routing works regardless of pane layout.

## Documentation

- **Claude Code**: See [claude/CLAUDE.md](claude/CLAUDE.md) for the Paladin's full configuration
- **Codex**: See [codex/AGENTS.md](codex/AGENTS.md) for the Wizard's configuration
