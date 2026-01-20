# Claude Code Configuration

Personal configuration for [Claude Code](https://claude.ai/claude-code) CLI.

## Setup

Clone to `~/.claude` on a new machine:

```bash
git clone git@github.com:alexivison/claude-config.git ~/.claude
```

Or if `~/.claude` already exists, clone elsewhere and symlink:

```bash
git clone git@github.com:alexivison/claude-config.git ~/dotfiles/claude
ln -sf ~/dotfiles/claude/* ~/.claude/
```

## Contents

| Path | Description |
|------|-------------|
| `CLAUDE.md` | Global instructions loaded in every session |
| `settings.json` | Global settings (model, permissions, hooks) |
| `agents/` | Custom sub-agents for specialized tasks |
| `skills/` | Context-aware skills triggered by task type |
| `rules/` | Language/framework-specific coding rules |
| `hooks/` | Shell scripts that run on Claude events |
| `scripts/` | Utility scripts (e.g., status line) |
| `commands/` | Custom slash commands |

## Agents

| Agent | Purpose |
|-------|---------|
| `debug-investigator` | Systematic bug investigation, returns root cause analysis |
| `project-researcher` | Gathers project context from Notion/Figma/Slack |
| `test-runner` | Runs tests, returns only failures (isolates verbose output) |

## Skills

| Skill | Triggers |
|-------|----------|
| `write-tests` | "write tests", "add test coverage" |
| `code-review` | PR reviews, code quality checks |
| `minimize` | Identifies bloat and unnecessary complexity |
| `plan-implementation` | Feature planning, creating specs |
| `address-pr` | "address PR comments", "check feedback" |
| `autoskill` | "learn from this session", "remember this pattern", `/autoskill` |

## Ignored (local-only)

These stay local and aren't version controlled:

- `settings.local.json` - Machine-specific settings
- `cache/`, `image-cache/` - Temporary data
- `history.jsonl` - Conversation history
- `plugins/`, `projects/` - Per-machine data
