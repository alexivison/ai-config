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
- **Target ~10-20 lines / ~250 tokens.** Hard cap at 30 lines. Injected into
  every coding session — every line must earn its keep.
- **Omit empty sections entirely.** Don't write "None" or "No pending reviews."
  Absence of signal isn't signal.
- **Prune** files older than 14 days in the same directory on write.
- Create the directory if it doesn't exist.

## Format

```markdown
## Priority Stack
1. TICKET-ID: Title — priority/urgency, status, cycle/deadline if relevant
   - Blocker status (cleared/pending), key API/dependency handoff, scope boundary

## In Flight (omit if none)
- TICKET-ID: Title — PR #NNN, CI status, what's needed next

## Watch Out (omit if none)
- File/area collisions ("X is also touching Y"), broken/flaky things, recent
  architectural shifts with implications ("shared hook Z now exists — reuse it")
```

## Section Guidelines

**Priority Stack:**
- Ordered most urgent first — the numbered list implies it
- Sub-bullets for what a coding agent needs to know to start work: is the
  blocker cleared, what API landed, what's in scope vs out
- Inline deadlines/cycle into the ticket line, not a separate section

**In Flight:**
- Only the user's own open PRs that need attention (CI red, review requested,
  needs rebase). Skip clean green PRs awaiting review from others.
- Prevents coding agents starting fresh on a ticket when an in-flight branch
  should be finished first.

**Watch Out:**
- File-level collision risk from parallel workstreams
- Known-broken things (CI on main red, flaky test suite)
- Implications of recently-landed work ("shared chat input hook exists — use
  it, don't duplicate")
- Only when non-empty — don't invent items to fill the section.

## Anti-Patterns

- **Do NOT** include ticket scope/requirements — that's what the ticket is for
- **Do NOT** prescribe implementation approaches
- **Do NOT** restate team, milestones, architecture, or cadence — already in
  `project-context.md` auto-memory
- **Do NOT** include a `# Daily Context — <date>` H1 — the date is in the
  filename and wastes a line
- **Do NOT** dump Slack threads verbatim — summarize the decision/outcome
- **Do NOT** include a "recently completed" log — if a handoff matters, put it
  in the relevant Priority Stack sub-bullet; otherwise `gh pr list` is cheap
  on-demand
