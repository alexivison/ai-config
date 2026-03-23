---
name: party-dispatch
description: >-
  Batch-dispatch multiple tickets or tasks to parallel party sessions, each
  running a specified skill. Requires 2+ items — for dispatching a single
  freeform task use /party-spawn instead. Takes the first item in the current
  session and spawns detached party sessions for the rest via party.sh. Use when
  the user wants to fix multiple bugs at once, work on several tickets in
  parallel, spawn parties for a batch of issues, or says things like "fix these
  tickets", "party bugfix", "spawn parties for these", "work on all of these",
  "dispatch these tasks". Supports Linear URLs/IDs and local file paths (e.g.,
  TASK*.md).
user-invocable: true
---

# Party Dispatch

Batch-dispatch multiple work items to parallel party sessions. Each session gets
its own Paladin + Wizard pair running the specified skill autonomously.

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

### Step 3 — Take the first item yourself

Invoke the specified skill directly in the current session. Pass the gathered
context as arguments. For example:

- `/bugfix-workflow` with the Linear ticket context pasted
- `/task-workflow` with the file path

### Step 4 — Spawn workers for remaining items

First, discover the current tmux session name:

```bash
tmux display-message -p '#{session_name}'
```

Check if this is a **master session** (`session_type == "master"` in manifest).

**If not a master**, promote it first so workers register back:

```bash
~/Code/ai-config/session/party.sh --promote <session-name>
```

This replaces the Codex pane with the tracker and sets `session_type=master`.

**Master session mode**: Dispatch ALL items to workers (keep none for self).

Spawn each remaining item as a **detached worker session** registered with the master:

```bash
~/Code/ai-config/session/party.sh --detached --master-id <session-name> --prompt "<prompt>" "<title>"
```

The `<title>` becomes the worker session's window name (e.g., the ticket ID).
Each worker is an independent tmux session with its own manifest, resumable via `--continue`.

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
~/Code/ai-config/session/party-relay.sh --report "done: <one-line summary of what was completed>"
```

For file-based items:

```
Run /task-workflow on the task file at: <absolute-path>

Read the file first to understand the scope, then execute the workflow.

When done, report completion to the master:
~/Code/ai-config/session/party-relay.sh --report "done: <one-line summary of what was completed>"
```

Spawn workers **sequentially** (one Bash call at a time, not parallel).
Wait for each spawn to complete before starting the next.

### Step 5 — Report

After spawning, report to the user:

- Which item you are handling in this window
- Which items were dispatched to worker sessions (with session names)
- How to switch between them: `party.sh --switch` or `prefix + s` (tmux session picker)

Then proceed with your own item's workflow — do not wait.

## Ongoing Orchestration

After dispatch the master session stays active to coordinate workers. During
this phase:

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
