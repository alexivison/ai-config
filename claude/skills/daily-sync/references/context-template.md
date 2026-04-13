# Daily Context Template

Shared format for the daily context file written by `/daily-sync` and
`/daily-radar`. Consumed by coding agents at session start for orientation.

## Location

`~/.claude/context/<repo-name>/<YYYY-MM-DD>.md`

- `<repo-name>` — from the repo the user is working in. If running outside a
  repo, fall back to the Linear team name from `data-sources.md` (kebab-case).
- `<YYYY-MM-DD>` — today's date.

## Rules

- **Overwrite** if today's file already exists (e.g., radar after sync, or
  mid-day re-runs).
- **~30 lines / ~500 tokens max** — this gets injected into coding sessions.
- **Prune** files older than 14 days in the same directory on write.
- Create the directory if it doesn't exist.

## Format

```markdown
# Daily Context — <YYYY-MM-DD>

## Priority Stack (ordered)
1. TICKET-ID: Title — priority, status, key context (blockers, dependencies, deadlines)
   - Implementation-relevant detail (e.g., "BE provides X API", "scope: FE only")

## Recently Completed (context only)
- TICKET-ID: Title (PR #NNN)

## Key Context
- Cycle info, demo deadlines, team decisions, anything a coding agent should know
```

## Section Guidelines

**Priority Stack:**
- Ordered by priority — most urgent first
- One ticket per numbered item
- Sub-bullets for implementation-relevant details only (not full ticket scope —
  that comes from the ticket itself)
- Include blockers and whether they're cleared

**Recently Completed:**
- Context only — helps coding agents connect dots (e.g., "the BE for this just
  landed"). Not a full changelog.
- Last 2-3 days is plenty.

**Key Context:**
- Cycle dates, demo deadlines, recent team decisions
- Anything that affects priority or approach but isn't ticket-specific

## Anti-Patterns

- **Do NOT** include ticket scope/requirements — that's what the ticket is for
- **Do NOT** prescribe implementation approaches
- **Do NOT** dump Slack threads verbatim — summarize the decision/outcome
