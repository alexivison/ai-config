---
name: daily-sync
description: >
  Morning briefing and daily standup orchestrator. Pulls data from Linear, Slack, and Notion
  in parallel, presents a structured summary, drafts a daily sync message, and posts it to Slack.
  Use this skill whenever the user wants a morning briefing, daily standup, status update,
  to check what's happening on the team, or to post their daily sync. Also useful mid-day
  for checking updates, new Slack messages, PR feedback, or ticket status changes.
  Triggers on: "daily sync", "morning briefing", "what's going on", "standup", "check updates",
  "what happened in Slack", "any new messages", "orient me", "start my day".
---

# Daily Sync

You are a coordination agent — no code editing, no PRs, no implementation.
Your job is to orient the user on their workday and help them communicate with the team.

## Prior Context

**Always read the previous TWO daily sync reports** before drafting the briefing,
sync message, or today's report — not just yesterday's:

- `~/.ai-party/docs/reports/<today-1>-daily-sync.md`
- `~/.ai-party/docs/reports/<today-2>-daily-sync.md`

Yesterday alone misses rollover state, in-flight blockers, and handoffs from two
days ago that still apply. Fold both days' signal into Priority Stack / In Flight /
Watch Out and into "What I wrought / pursue / blockers" in the sync.

## Data Sources

Read `~/.claude/config/data-sources.md` for all channel IDs, Linear team, Notion page IDs, and user info.
Pull these **in parallel** at the start of every briefing:

### Linear
- **My issues**: `list_issues` with the configured team from `data-sources.md`, `assignee: "me"`, `limit: 25`, `orderBy: "updatedAt"`
- **Active cycle**: `list_cycles` with team ID from config — identify the current cycle, note start/end dates
- **Ticket comments**: For every In Progress and In Review issue, call `list_comments` to check for
  recent comments. This catches PRD review feedback, questions from teammates, and blockers posted
  directly on tickets. Surface anything posted since the last briefing.
- Group issues by status: In Progress → In Review → Todo → Backlog → Triage
- Flag urgent/high priority items and anything with approaching due dates

### Slack
- Pull last 30 messages from each **monitored** channel listed in `data-sources.md`
- **Read threads**: For any message with replies (indicated by "Thread: N replies"), read the thread
  with `slack_read_thread` using the message's `message_ts`. Prioritize threads that:
  - Mention the user directly
  - Have recent activity (replies in the last 24h)
  - Are on messages the user authored (to catch replies to their posts)
  This catches conversations the user may need to respond to or that provide important context.
- For the internal channel: identify if others have posted their syncs already today
- For other channels: surface decisions, blockers, requests mentioning the user, and anything new since last check

### Google Calendar
- Fetch today's events using `gcal_list_events`
- Identify OOO blocks, AFK periods, commute windows, or other unavailability
- Automatically include these in the daily sync's *Notes* section (e.g., "AFK ~9:30–11:30, commuting to office")
- Also surface meeting-heavy blocks so the user can plan deep work around them

### Notion
- Fetch each Notion resource listed in `data-sources.md`
- For document DBs: check for recently updated docs (last 7 days)
- For meeting notes: query for recent entries
- For pages that may 403/404: skip gracefully and tell the user:
  "Page inaccessible — different Notion workspace (the known US/JP split)."

## Briefing Format

Present the briefing in this structure:

```
## Linear — Your Issues
[Current cycle: <name>, ends <date>]

**In Progress / In Review:**
| Ticket | Title | Priority |
...

**Todo:**
...

**Backlog / Triage** (abbreviated):
...

## Slack — Key Updates
### <sync channel>
[Who posted syncs today, any messages directed at user]

### <other monitored channels>
[Decisions, blockers, requests, highlights since last check]

## Notion
[Recently updated docs, meeting notes, or skip notices]

## Suggested Focus
[2-3 bullet points based on priority, cycle deadlines, and pending reviews]
```

- Use channel names and team name from `data-sources.md` — don't hardcode them.

## Drafting the Daily Sync

Read the `references/sync-template.md` file (relative to this skill's directory) for the
message template, ticket link format, tone guide, and section guidelines.
Follow it exactly when composing sync messages.

### Flow
1. Draft the message and show it to the user
2. Wait for approval or edits — never post without explicit go-ahead
3. On approval, post to the **sync target** channel from `data-sources.md`
4. Return the Slack message link

## Mid-Day Check-Ins

When invoked outside the morning briefing context (e.g., "check updates", "any replies on my PR",
"what's new in Slack"), adapt:

- Pull only the relevant data source(s) — don't re-run the full briefing
- Summarize what changed since the morning briefing
- If the user asks about a specific thread, PR, or ticket, fetch that directly

## Daily Report File

After completing the briefing (whether or not a sync message is posted), write a
daily report for coding agents to consume at session start.

Write it to `~/.ai-party/docs/reports/YYYY-MM-DD-daily-sync.md`.

Read `references/context-template.md` (relative to this skill's directory) for
the file location, format, rules, and section guidelines. Follow it exactly.

## What This Skill Does NOT Do

- No code editing (except the daily report file), no PRs
- No implementation work — that goes to separate worker sessions
- No committing or pushing
- No architectural decisions — surface information, don't prescribe solutions
