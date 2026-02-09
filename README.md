# ai-config-claude

Unified configuration repository for AI coding assistants. Houses configurations for multiple tools with symlink-based installation.

## Structure

```
ai-config-claude/
├── claude/          # Claude Code configuration
├── gemini/          # Google Gemini CLI configuration
├── codex/           # OpenAI Codex CLI configuration
├── install.sh       # Install CLIs and create symlinks
├── uninstall.sh     # Remove symlinks
└── README.md
```

## Installation

```bash
# Clone the repo
git clone git@github.com:alexivison/ai-config-claude.git ~/Code/ai-config-claude

# Full install (symlinks + CLI installation + auth)
cd ~/Code/ai-config-claude
./install.sh

# Or symlinks only (install CLIs yourself)
./install.sh --symlinks-only
```

The installer will:
1. Create config symlinks (`~/.claude`, `~/.gemini`, `~/.codex`)
2. Offer to install missing CLI tools (optional)
3. Offer to run authentication for each tool (optional)

### CLI Installation Methods

| Tool | Install Command |
|------|-----------------|
| Claude | `curl -fsSL https://cli.anthropic.com/install.sh \| sh` |
| Gemini | `npm install -g @google/gemini-cli` |
| Codex | `brew install --cask codex` |

## Uninstallation

```bash
cd ~/Code/ai-config-claude
./uninstall.sh
```

Removes symlinks but keeps the repository.

## Adding a New Tool

1. Create a directory for the tool: `mkdir -p newtool`
2. Add a `setup_newtool()` function in `install.sh`
3. Add the tool to `uninstall.sh`
4. Run `./install.sh` to create the symlink

## Tool Documentation

- **Claude Code**: See [claude/README.md](claude/README.md) for Claude-specific configuration
- **Gemini**: Google Gemini CLI settings and credentials
- **Codex**: OpenAI Codex CLI settings, skills, and agents
