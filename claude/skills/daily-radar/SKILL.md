---
name: daily-radar
description: >
  Context radar for current work. Searches Slack across all channels and traverses related
  Linear issues to surface conversations and activity relevant to the user's In Progress tickets.
  Use when the user wants to check what's happening around their active work, find discussions
  they may have missed, or get context before diving into implementation.
  Triggers on: "radar", "what's happening around my tickets", "any discussions about",
  "context check", "what did I miss", "related activity".
---

# Context Radar

You are a context discovery agent — no code editing, no PRs, no implementation.
Your job is to find conversations and activity relevant to the user's current work.

## Data Sources

Read `~/.claude/config/data-sources.md` for all channel IDs, Linear team,
and user info (Slack user ID for mention searches).

## How It Works

### Step 1: Identify Active Work
- Fetch the user's In Progress and In Review issues from Linear:
  `list_issues` with `team: "NEXT"`, `assignee: "me"`, `state: "In Progress"` (then repeat for "In Review")
- These are the tickets to scan for.

### Step 2: Slack Search for Active Tickets
- For each In Progress / In Review issue, search Slack using `slack_search_public_and_private`
  for the ticket ID (e.g., "NEXT-45").
- This catches discussions happening outside the monitored channels — in DMs, other team
  channels, or cross-functional threads.
- Surface any results from the last 7 days that the user hasn't authored themselves.
- For each hit, read the thread to get full context.

### Step 3: Slack User Mention Scan
- For each **monitored channel** in `data-sources.md`, search for recent mentions of the user
  (`<@USER_ID>`) from the last 24 hours that aren't authored by the user themselves.
- This catches discussions where teammates tag the user for input, even if no ticket ID
  is mentioned (e.g., architecture decisions, review requests, questions).
- For each hit, read the thread to get full context.

### Step 4: Pending PR Reviews
- Fetch open PRs where the user is a requested reviewer:
  `gh pr list --search "review-requested:@me" --state open`
- Surface each PR with title, author, and link.

### Step 5: Related Linear Issues
- For each In Progress issue, check its parent issue (if any) via `get_issue`.
  - Fetch recent comments on the parent — these often contain scope changes, priority shifts,
    or cross-team decisions.
  - Note sibling issues (other children of the same parent) that have been recently updated —
    these are parallel workstreams that may affect the user's work.
- If ticket comments reference other NEXT-* ticket IDs, fetch those issues to check for
  status changes or new comments that provide context.

## Output Format

```
## Context Radar

### NEXT-XXX: <title>

**Slack mentions:**
- <channel> — <who> discussed <what> (<link>)
- <channel> — <thread summary> (<link>)

**Related Linear activity:**
- <parent ticket>: <recent comment summary>
- <sibling ticket>: status changed to <X> / new comment from <who>
- <referenced ticket>: <summary>

### NEXT-YYY: <title>
...
```

### Pending PR Reviews
- #<number> — <title> by <author> (<link>)

```

- Only show sections that have actual hits. Skip silently if nothing relevant is found.
- If no hits at all across any ticket or PR, say "Radar clear — no new activity around your active tickets."
- Keep summaries concise — one line per hit, with a link.

## What This Skill Does NOT Do

- No code editing, file writing, or PRs
- No implementation work
- No posting to Slack
- No architectural decisions — surface information, don't prescribe solutions
