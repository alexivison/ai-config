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
| `check-runner` | Runs typecheck/lint, returns only errors (isolates verbose output) |
| `log-analyzer` | Analyzes logs, returns error summary (isolates verbose output) |
| `security-scanner` | Scans for secrets, vulnerabilities, OWASP issues before PR |
| `code-critic` | Autonomous code review loop using `/code-review` guidelines |

## Skills

| Skill | Triggers |
|-------|----------|
| `brainstorm` | New features with unclear requirements, multiple approaches |
| `plan-implementation` | Feature planning, creating specs |
| `write-tests` | "write tests", "add test coverage" |
| `code-review` | PR reviews, code quality checks |
| `pre-pr-verification` | Before creating PR, verifying all checks pass |
| `minimize` | Identifies bloat and unnecessary complexity |
| `address-pr` | "address PR comments", "check feedback" |
| `autoskill` | "learn from this session", "remember this pattern", `/autoskill` |

## Workflow

Standard development workflow (discipline-based, documented in CLAUDE.md):

```
Single Task (most common):
  Pick up task → read requirements → /write-tests (if needed) → implement
  → code-critic loop (autonomous) → test-runner + check-runner + security-scanner
  → /pre-pr-verification → PR → wait for review → /address-pr (if comments) → merge

New Feature:
  project-researcher (if unfamiliar)
  → /brainstorm (if unclear requirements)
  → /plan-implementation (if substantial)
  → implementation
  → code-critic loop (autonomous, max 3 iterations)
  → test-runner + check-runner + security-scanner (parallel)
  → /pre-pr-verification
  → PR
  → /minimize (if PR large)

Bug Fix:
  debug-investigator (if complex)
  → implementation
  → code-critic loop (autonomous)
  → test-runner + check-runner + security-scanner (parallel)
  → /pre-pr-verification
  → PR
```

Key principles:
- **Evidence before claims** — never state "tests pass" without running them
- **RED phase for tests** — watch new tests fail before implementation
- **Verification before PR** — run `/pre-pr-verification` before every PR
- **Auto-invoke skills** — skills trigger automatically based on context

## Scripts

| Script | Purpose |
|--------|---------|
| `context-bar.sh` | Status line display |
| `weekly-report.sh` | Generate weekly summary of investigations and projects |
| `agent-stats.sh` | Summarize sub-agent activity (today/week/all) |

### Scheduling weekly-report.sh

Run manually anytime:
```bash
~/.claude/scripts/weekly-report.sh
```

Or schedule automatically:

**macOS (launchd):**
```bash
# Create plist in ~/Library/LaunchAgents/com.claude.weekly-report.plist
# with StartCalendarInterval for desired schedule, then:
launchctl load ~/Library/LaunchAgents/com.claude.weekly-report.plist
```

**Linux (cron):**
```bash
# Run Fridays at 4:30pm
crontab -e
30 16 * * 5 ~/.claude/scripts/weekly-report.sh
```

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session-cleanup.sh` | SessionStart | Cleans old PR gate markers (>24h) |
| `skill-eval.sh` | UserPromptSubmit | Detects skill triggers, injects MANDATORY/SHOULD suggestions |
| `worktree-guard.sh` | PreToolUse (Bash) | Prevents branch switching in shared repos |
| `pr-gate.sh` | PreToolUse (Bash) | Blocks `gh pr create` without verification markers |
| `agent-trace.sh` | PostToolUse (Task) | Logs sub-agent invocations, creates security-scanner marker |
| `skill-marker.sh` | PostToolUse (Skill) | Creates /pre-pr-verification marker |

## Ignored (local-only)

These stay local and aren't version controlled:

- `settings.local.json` - Machine-specific settings
- `cache/`, `image-cache/` - Temporary data
- `history.jsonl` - Conversation history
- `plugins/`, `projects/` - Per-machine data
- `scripts/*.plist` - macOS LaunchAgent configs
- `plans/` - Local planning files
- `investigations/` - Debug-investigator output
- `logs/` - Log-analyzer output
