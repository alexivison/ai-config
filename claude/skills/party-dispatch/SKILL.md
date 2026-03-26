---
name: party-dispatch
description: >-
  Batch-dispatch multiple tickets or tasks to parallel party sessions, each
  running a specified skill. Promotes to master and dispatches ALL items to
  workers — the master orchestrates but never implements. Requires 2+ items; for
  a single freeform task use /party-spawn instead. Use when the user wants to fix
  multiple bugs at once, work on several tickets in parallel, spawn parties for a
  batch of issues, or says things like "fix these tickets", "party bugfix",
  "spawn parties for these", "work on all of these", "dispatch these tasks".
  Supports Linear URLs/IDs and local file paths (e.g., TASK*.md).
user-invocable: true
---

# Party Dispatch

Batch-dispatch multiple work items to parallel party sessions. The master
promotes itself to orchestrator mode and delegates ALL items to workers — it
never takes an item for itself.

For spawning a single worker with a freeform prompt, use `/party-spawn`.

## Usage

```
/party-dispatch <skill> <item1> <item2> [item3 ...]
```

- `<skill>` — the slash command to invoke (e.g., `/bugfix-workflow`, `/task-workflow`)
- `<itemN>` — a Linear URL, Linear issue ID (e.g., `ENG-123`), or a local file path

## Execution

### Step 1 — Parse and classify items

Separate arguments into the skill name and work items. Classify each item:

| Pattern | Type | Example |
|---------|------|---------|
| `https://linear.app/...` | Linear URL | `https://linear.app/team/issue/ENG-123/title` |
| `TEAM-123` (letters-digits) | Linear ID | `ENG-456` |
| Anything else | File path | `libraries/.../TASK-01.md` |

### Step 2 — Gather context for each item

- **Linear URL/ID**: Extract the issue identifier from the URL (the `TEAM-123` segment after `/issue/`). Fetch details via `mcp__claude_ai_Linear__get_issue` with the identifier. Extract: title, description, labels, priority, assignee.
- **File path**: Read the file to get context (title, scope, description).

Fetch all Linear tickets in parallel (multiple tool calls in one turn).

### Step 3 — Promote to master

Discover the current tmux session name:

```bash
tmux display-message -p '#{session_name}'
```

Always promote to master so workers register back and the tracker pane activates:

```bash
~/Code/ai-config/session/party.sh --promote <session-name>
```

This replaces the Codex pane with the tracker and sets `session_type=master`.
If already a master, this is a no-op.

### Step 4 — Spawn workers for ALL items

Spawn each item as a **detached worker session** registered with the master:

```bash
~/Code/ai-config/session/party.sh --detached --master-id <session-name> --prompt "<prompt>" "<title>"
```

The `<title>` becomes the worker session's window name (e.g., the ticket ID).
Each worker is an independent tmux session with its own manifest, resumable via `--continue`.

Spawn workers **sequentially** (one Bash call at a time, not parallel).
Wait for each spawn to complete before starting the next.

#### Prompt construction

The prompt must be self-contained — the spawned Claude has no prior context.
Build it like this:

```
Run /<skill> on this issue.

**Ticket:** <ID>
**Title:** <title>
**Description:**
<description>

**Labels:** <labels>
**Priority:** <priority>

Work in the repo at <absolute-cwd>.

When done, report completion to the master:
~/Code/ai-config/session/party-relay.sh --report "done: <one-line summary> | PR: <url or 'none'>"
```

For file-based items:

```
Run /task-workflow on the task file at: <absolute-path>

Read the file first to understand the scope, then execute the workflow.

When done, report completion to the master:
~/Code/ai-config/session/party-relay.sh --report "done: <one-line summary> | PR: <url or 'none'>"
```

### Step 5 — Create tracker and report

After spawning all workers, create a task list to track each worker's progress
using `TaskCreate`. Each task should include the worker session name, item ID,
and current status:

```
- [ ] party-1234 | ENG-123 — Fix auth bug | dispatched
- [ ] party-1235 | ENG-124 — Update config | dispatched
- [ ] party-1236 | TASK-01.md — Add retry logic | dispatched
```

Then report to the user:

- All dispatched workers (session names and items)
- How to check on workers: `party-relay.sh --read <worker-id>`
- How to switch between them: `party.sh --switch` or `prefix + s` (tmux session picker)
- Point to the task list for live tracking

Do not wait for workers — proceed to orchestration immediately.

## Ongoing Orchestration

After dispatch the master session stays active to coordinate workers through
their entire lifecycle. The master is an orchestrator, never an implementor.

### Monitoring workers

- **Check status**: `party-relay.sh --list` to see all workers and their state
- **Read scrollback**: `party-relay.sh --read <worker-id>` (default 50 lines)
  or `--read <worker-id> --lines 200` for deeper history
- **Watch tracker pane**: the left pane shows real-time worker status

### Handling worker reports

Workers report back via `[WORKER:<session-id>]` prefixed messages. When a
report arrives:

1. Read the report content
2. Update the corresponding task via `TaskUpdate` (mark completed, add summary)
3. If the worker opened a PR, note the PR URL in the task
4. Check if all workers are done — if so, proceed to final summary

### Relaying follow-up instructions

When a worker needs guidance or additional work:

```bash
~/Code/ai-config/session/party-relay.sh <worker-id> "instruction text"
```

Always include investigation context (file paths, line numbers, root cause
analysis) so the worker can act immediately without re-investigating.

For broadcasts to all workers:

```bash
~/Code/ai-config/session/party-relay.sh --broadcast "message"
```

### Reviewing worker PRs

When a worker completes and opens a PR:

1. Read the PR: `gh pr view <number>` and `gh pr diff <number>`
2. Check CI status: `gh pr checks <number>`
3. If CI fails, read the scrollback and relay fix instructions to the worker
4. Run `/code-review` on the PR diff to get a structured quality review
5. If the review finds blocking issues, relay the findings to the worker with
   file paths and line numbers so they can fix without re-investigating
6. If the review passes and CI is green, approve and merge the PR
7. Update the task list with the final status

### Handling worker failures

If a worker appears stuck or reports an error:

1. Read scrollback: `party-relay.sh --read <worker-id> --lines 200`
2. Diagnose the issue from the output
3. Relay fix instructions with context: `party-relay.sh <worker-id> "..."`
4. If the worker is unrecoverable, note it in the task list and consider
   spawning a replacement via `/party-spawn`

### Final summary

When all workers have reported back (all tasks completed):

1. Summarize results: which items succeeded, which failed, PR URLs
2. List any follow-up items that need attention
3. Report the final status to the user

### Rules

- **Investigate freely** — Read, Grep, Glob, Bash (read-only commands), and
  MCP queries are all fine. Gathering context to relay to workers is core
  orchestration work.
- **Never edit production code** — Do not use Edit or Write on source files.
  All code changes must be delegated to a worker via `party-relay.sh`.
  This applies in every scenario: new bugs found during testing, quick
  one-line fixes, "obvious" changes — no exceptions.
- **Relay with context** — When relaying new work to a worker, include your
  investigation findings (file paths, line numbers, root cause analysis) so
  the worker can act immediately.

## Important

- The spawned parties run `claude --dangerously-skip-permissions`, so they
  execute autonomously. The prompt is all they get — make it complete.
- Each party creates its own worktree (per bugfix/task-workflow convention),
  so there are no git conflicts between sessions.
- If a Linear fetch fails, warn the user and skip that item (don't block the rest).
- Keep prompts under 500 characters to avoid shell quoting issues. For longer
  context, write the prompt to a temp file and use `--prompt "$(cat /tmp/party-prompt-N.md)"`.
