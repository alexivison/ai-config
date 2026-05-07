# Claude

Roles (primary, companion) are configurable per session via `party-cli config` — any installed agent (Claude, Codex, Pi) can fill either role. Use `party-cli config set-companion pi` or `party-cli config set-primary pi` to select Pi; see `docs/pi-companion.md` for current limitations.

You are Claude Code. In a party session, follow the role assigned by the session/config. In a standalone session, act as the primary implementer.

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
- **Clean Code**: Follow `shared/reference/clean-code.md` (LoB, SRP, YAGNI, DRY, KISS). Self-check every function.

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

Each workflow skill writes an `execution-preset` marker via `skill-marker.sh`. That marker is what makes the PR gate enforce the preset's evidence set. See `shared/reference/execution-core.md § Opt-In Presets` for the preset-to-evidence mapping.
Claude-specific hook paths, evidence storage, override knobs, and review metrics live in `claude/rules/execution-core-claude-internals.md`.

When a workflow is active, **do NOT stop between steps.** Follow `shared/reference/execution-core.md` for sequence, gates, decision matrix, and pause conditions. Companion review is NEVER a pause condition or skippable — see execution-core § Review Governance.

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
| `companion-review` | Dispatch the configured companion via the `agent-transport` skill, then record the verdict with `--review-complete`. |
| `pre-pr-verification` | Dispatch `test-runner` + `check-runner` in parallel via the Task tool. |

**NEVER run tests or checks via Bash directly.** When a workflow is active, always delegate verification to `test-runner` / `check-runner` via the Task tool — they discover and run the full suite regardless of project.

Keep the main context clean. One task per sub-agent.

## Inter-Agent Transport

When in a party session, use the `agent-transport` skill to coordinate with the configured companion or primary. Party-cli injects role-specific transport rules at launch.

## Master Session Mode

When running as a master, use the `party-dispatch` skill. Party-cli injects master-specific rules at launch.

## Verification Principle

Evidence before claims. Code edits invalidate prior results. Never mark complete without proof (tests, logs, diff). See `shared/reference/execution-core.md § Verification Principle`.

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

**Always create a dedicated worktree before editing any file**, including in direct-edit mode with no workflow active. Bypassing a workflow gate does NOT exempt you from this. Never edit in another session's cwd — concurrent workers in the same worktree trample each other's diffs.

`main` is always the source of truth. When syncing or resolving conflicts, current `main` behavior/specs win. Reapply only your narrow ticket delta on top of latest `main`; never revive stale branch behavior.

1. Prefer `gwta <branch>` if available.
2. Otherwise: `git worktree add ../<repo>-<branch> -b <branch>`.
3. One session per worktree. Never use `git checkout` or `git switch` in shared repos.
4. After PR merge, clean up: `git worktree remove ../<repo>-<branch>`.
