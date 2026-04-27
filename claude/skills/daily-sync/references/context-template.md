# Daily Report Template

Shared format for the daily report file written by `/daily-sync` and
`/daily-radar`. Consumed by coding agents at session start for orientation.

## Locations

- `/daily-sync` → `~/.ai-party/docs/reports/<YYYY-MM-DD>-daily-sync.md`
- `/daily-radar` → `~/.ai-party/docs/reports/<YYYY-MM-DD>-daily-radar.md`
- Use today's date for `<YYYY-MM-DD>`.

## Rules

- **Read the previous TWO reports from the same series before writing today's.**
  For `/daily-sync`, read the previous two `*-daily-sync.md` files. For
  `/daily-radar`, read the previous two `*-daily-radar.md` files. Yesterday
  alone misses rollover state, in-flight blockers, and handoffs from two days
  ago. Fold both days' still-relevant signal into today's Priority Stack /
  In Flight / Watch Out.
- **Overwrite** if today's file already exists (e.g., a later rerun the same day).
- **Target ~10-20 lines / ~250 tokens.** Hard cap at 30 lines. Injected into
  every coding session — every line must earn its keep.
- **Omit empty sections entirely.** Don't write "None" or "No pending reviews."
  Absence of signal isn't signal.
- Preserve older reports. Do **not** prune historical files.
- Create the reports directory if it doesn't exist.

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
- **Do NOT** include a `# Daily Report — <date>` H1 — the date is in the
  filename and wastes a line
- **Do NOT** dump Slack threads verbatim — summarize the decision/outcome
- **Do NOT** include a "recently completed" log — if a handoff matters, put it
  in the relevant Priority Stack sub-bullet; otherwise `gh pr list` is cheap
  on-demand
