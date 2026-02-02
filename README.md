# ai-config

Unified configuration repository for AI coding assistants. Houses configurations for multiple tools with symlink-based installation.

## Structure

```
ai-config/
├── claude/          # Claude Code configuration
├── gemini/          # Google Gemini (placeholder)
├── codex/           # OpenAI Codex (placeholder)
├── install.sh       # Create symlinks
├── uninstall.sh     # Remove symlinks
└── README.md
```

## Installation

```bash
# Clone the repo
git clone git@github.com:alexivison/ai-config.git ~/Code/ai-config

# Create symlinks
cd ~/Code/ai-config
./install.sh
```

This creates:
- `~/.claude` → `~/Code/ai-config/claude`
- `~/.gemini` → `~/Code/ai-config/gemini`
- `~/.codex` → `~/Code/ai-config/codex`

## Uninstallation

```bash
cd ~/Code/ai-config
./uninstall.sh
```

Removes symlinks but keeps the repository.

## Adding a New Tool

1. Create a directory for the tool: `mkdir -p newtool`
2. Add the tool to the `TOOLS` array in `install.sh` and `uninstall.sh`
3. Run `./install.sh` to create the symlink

## Tool Documentation

- **Claude Code**: See [claude/README.md](claude/README.md) for Claude-specific configuration
- **Gemini**: Placeholder for future configuration
- **Codex**: Placeholder for future configuration
