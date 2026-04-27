# Claude

| Member | Default Agent | Role |
|--------|---------------|------|
| **The User** | — | Commander and final authority |
| **Primary** | Claude Code | Implementation, testing, orchestration |
| **Companion** | Codex CLI | Deep reasoning, analysis, review |

> Agent assignments are configurable via `party-cli config` in `~/.config/party-cli/config.toml`. The table above shows the default layout.

You are Claude Code. You default to the primary role but may be configured as companion — check the table above for current assignment.

- Dispatch the companion for deep reasoning; handle all implementation yourself.
- Be concise and direct. No preamble, no hedging, no filler.

## General Guidelines

- Main agent handles all implementation (code, tests, fixes).
- Sub-agents for context preservation only (investigation, verification).
- Prefer early guard returns over nested if clauses.
- Keep comments short — only remark on logically difficult code.

### Core Principles

- **Simplicity + Minimal Impact**: Smallest possible change. No over-engineering.
- **No Laziness**: Root causes only. Senior developer standards.
- **Clean Code**: Follow `shared/clean-code.md` (LoB, SRP, YAGNI, DRY, KISS). Self-check every function.

## Daily Reports

Read today's daily report files in `~/.ai-party/docs/reports/` at session start when they exist:

- `YYYY-MM-DD-daily-sync.md`
- `YYYY-MM-DD-daily-radar.md`

- **Use it for orientation only** — ticket scope and implementation details come from the ticket itself.
- Previous reports are available for reference when you need recent context.

## Default Mode: Direct Editing

**The default session mode is direct editing.** If the user has not invoked a workflow skill, just do the work — read files, make changes, run commands. The PR gate stays out of the way until a workflow skill opts the session into an execution preset.

Invoke a workflow skill when the request matches the preset:

- **Planned work** (TASK files, external planning tool output, or any source providing scope + requirements) → `/task-workflow`
- **Bug fix / debugging** → `/bugfix-workflow`
- **Quick fixes / small or straightforward changes** → `/quick-fix-workflow`
- **OpenSpec repos with CI review bots** → `/openspec-workflow`

Each workflow skill writes an `execution-preset` marker via `skill-marker.sh`. That marker is what makes the PR gate enforce the preset's evidence set. See `shared/execution-core.md § Opt-In Presets` for the preset-to-evidence mapping.
Claude-specific hook paths, evidence storage, override knobs, and review metrics live in `claude/rules/execution-core-claude-internals.md`.

When a workflow is active, **do NOT stop between steps.** Follow `shared/execution-core.md` for sequence, gates, decision matrix, and pause conditions. Companion review is NEVER a pause condition or skippable — see execution-core § Review Governance.

## Docs Workspace

Write agent-produced docs directly under `~/.ai-party/docs/`. Do not ask the user for a path.

- Research notes, investigations, plans, designs, and reviews go in `~/.ai-party/docs/research/`.
- Daily syncs, daily radar snapshots, ad-hoc reports, and weekly bundles go in `~/.ai-party/docs/reports/`.
- New research docs use `YYYY-MM-DD-<slug>.md` filenames with the required frontmatter from `~/.ai-party/docs/CLAUDE.md`.
- Legacy migrated notes from `~/.claude/investigations/` may lack frontmatter. Leave them as-is unless the user asks for a rewrite.

## Stage Bindings

Workflow skills describe logical stages; this section binds each stage to the concrete mechanism Claude uses.

| Stage | Claude binding |
|-------|----------------|
| `write-tests` | Dispatch the `test-runner` sub-agent via the Task tool (both RED and GREEN). |
| `critics` | Dispatch `code-critic` + `minimizer` (+ `requirements-auditor` when requirements are provided) in parallel via the Task tool. |
| `companion-review` | Dispatch the configured companion via `~/.claude/skills/agent-transport/scripts/tmux-companion.sh --review`, then record the verdict with `--review-complete`. |
| `pre-pr-verification` | Dispatch `test-runner` + `check-runner` in parallel via the Task tool. |

Claude-specific sub-agents live under `claude/agents/`:

- **test-runner** — run tests
- **check-runner** — run typecheck/lint
- **code-critic** — SRP/DRY/correctness review
- **minimizer** — locality/simplicity/bloat review
- **requirements-auditor** — requirements coverage
- **deep-reviewer** — adversarial architecture review (advisory)
- **daily-helper** — daily ops utility

**NEVER run tests or checks via Bash directly.** When a workflow is active, always delegate verification to `test-runner` / `check-runner` via the Task tool — they discover and run the full suite regardless of project.

Keep the main context clean. One task per sub-agent.

## Inter-Agent Transport

Use the role-aware transport scripts only; never raw tmux commands. If you are the primary agent, dispatch the companion via `agent-transport` / `tmux-companion.sh` and keep working in parallel. If you are the companion agent, notify the primary via `tmux-primary.sh`. `[PRIMARY]` / `[COMPANION]` are the message prefixes. Handle inbound transport via `tmux-handler`.

### When to Dispatch

When acting as primary, see `agent-transport` for dispatch guidelines (mandatory and proactive triggers).

### Transport

- Primary → companion: `~/.claude/skills/agent-transport/scripts/tmux-companion.sh`
- Companion → primary: `~/.codex/skills/agent-transport/scripts/tmux-primary.sh`
- Dispatch modes (`--review`, `--plan-review`, `--prompt`) are non-blocking and require `work_dir` as the last arg
- See `agent-transport` for the full mode references

## Master Session Mode

See `party-dispatch` skill for master session rules.

## Verification Principle

Evidence before claims. Code edits invalidate prior results. Never mark complete without proof (tests, logs, diff). See `shared/execution-core.md § Verification Principle`.

## Self-Improvement

After ANY user correction: identify the pattern, write a preventive rule, save to auto-memory (`~/.claude/projects/.../memory/`).

## Development Rules

### Git and PR

- Use `gh` for GitHub operations.
- Create branches from `main`.
- Branch naming: `<ISSUE-ID>-<kebab-case-description>`.
- PR descriptions: follow the `pr-descriptions` skill.
- Include issue ID in PR description (e.g., `Closes ENG-123`).
- Create separate PRs for changes in different services.

### Worktree Isolation

1. Prefer `gwta <branch>` if available.
2. Otherwise: `git worktree add ../<repo>-<branch> -b <branch>`.
3. One session per worktree. Never use `git checkout` or `git switch` in shared repos.
4. After PR merge, clean up: `git worktree remove ../<repo>-<branch>`.
