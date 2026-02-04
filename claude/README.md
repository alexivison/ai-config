# Claude Code Configuration

Personal configuration for [Claude Code](https://claude.ai/claude-code) CLI.

> **Installation**: See [../README.md](../README.md) for installation instructions.

## Contents

| Path | Description |
|------|-------------|
| `CLAUDE.md` | Global instructions loaded in every session |
| `settings.json` | Global settings (model, permissions, hooks) |
| `agents/` | Custom sub-agents for specialized tasks |
| `skills/` | Context-aware skills triggered by task type |
| `rules/` | Execution rules and development guidelines |
| `hooks/` | Shell scripts that run on Claude events |
| `scripts/` | Utility scripts (e.g., status line) |
| `commands/` | Custom slash commands |

## Agents

| Agent | Purpose |
|-------|---------|
| `test-runner` | Runs tests, returns only failures (isolates verbose output) |
| `check-runner` | Runs typecheck/lint, returns only errors (isolates verbose output) |
| `log-analyzer` | Analyzes logs, returns error summary (isolates verbose output) |
| `security-scanner` | Scans for secrets, vulnerabilities, OWASP issues (optional) |
| `code-critic` | Iterative code review using `/code-review` guidelines |
| `codex` | Deep reasoning via Codex CLI for code/architecture review, design decisions, debugging |

> **Note:** `debug-investigator` has been replaced by `codex` which provides combined debugging + analysis via Codex CLI.

> **Note:** `architecture-critic` has been replaced by `codex` which provides combined code + architecture review.

## Skills

### User-Invocable

| Skill | Triggers |
|-------|----------|
| `brainstorm` | New features with unclear requirements, multiple approaches |
| `plan-implementation` | Feature planning, creating specs |
| `minimize` | Identifies bloat and unnecessary complexity |
| `address-pr` | "address PR comments", "check feedback" |
| `autoskill` | "learn from this session", "remember this pattern", `/autoskill` |

### Workflow Orchestrators (auto-invoked)

| Skill | Triggers |
|-------|----------|
| `task-workflow` | TASK*.md execution, "pick up task", "from the plan" |
| `feature-workflow` | "implement", "build", "create", "add new" |
| `bugfix-workflow` | "bug", "broken", "error", "debug", "fix" |

### Reference Skills (loaded by agents/workflows)

| Skill | Purpose |
|-------|---------|
| `write-tests` | Test writing methodology (invoked by workflows) |
| `code-review` | Code quality guidelines (preloaded by code-critic) |
| `architecture-review` | Architecture guidelines (reference; codex handles architecture review) |
| `pre-pr-verification` | PR verification checklist (invoked before PR creation) |

## Commands

| Command | Purpose |
|---------|---------|
| `deploy-k8s` | Deploy services to Kubernetes via ArgoCD/Kustomize overlays |

## Rules

| Rule | Purpose |
|------|---------|
| `execution-core.md` | Core sequence, decision matrix, verification principle |
| `autonomous-flow.md` | Continuous execution rules, valid pause conditions |
| `development.md` | Git conventions, PRs, worktrees, task management |

## Workflow

Core sequence: `/write-tests` → implement → checkboxes → code-critic → codex → /pre-pr-verification → commit → PR

Key principles:
- **Evidence before claims** — never state "tests pass" without running them
- **Autonomous flow** — no stopping between steps unless blocked
- **Code-critic mandatory** — for all TASK*.md implementations
- **Codex mandatory** — for combined code + architecture review before PR

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
| `session-cleanup.sh` | SessionStart | Cleans old markers (>24h) |
| `skill-eval.sh` | UserPromptSubmit | Detects skill triggers, injects MANDATORY/SHOULD suggestions |
| `worktree-guard.sh` | PreToolUse (Bash) | Prevents branch switching in shared repos |
| `pr-gate.sh` | PreToolUse (Bash) | Blocks `gh pr create` without verification markers |
| `agent-trace.sh` | PostToolUse (Task) | Logs to agent-trace.jsonl, creates agent markers |
| `skill-marker.sh` | PostToolUse (Skill) | Logs to skill-trace.jsonl, creates skill markers |

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
