---
name: party-dispatch
description: >-
  Dispatch multiple tickets or tasks to parallel party sessions, each running a
  specified skill. Takes the first item in the current session and spawns
  detached party sessions for the rest via party.sh. Use when the user wants to
  fix multiple bugs at once, work on several tickets in parallel, spawn parties
  for a batch of issues, or says things like "fix these tickets", "party
  bugfix", "spawn parties for these", "work on all of these", "dispatch these
  tasks". Supports Linear URLs/IDs and local file paths (e.g., TASK*.md).
user-invocable: true
---

# Party Dispatch

Dispatch multiple work items to parallel party sessions. Each session gets its
own Paladin + Wizard pair running the specified skill autonomously.

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

### Step 4 — Spawn worker windows for remaining items

First, discover the current tmux session name:

```bash
tmux display-message -p '#{session_name}'
```

For each remaining item, construct a prompt and spawn a worker window in the
current session:

```bash
~/Code/ai-config/session/party.sh --parent <session-name> --prompt "<prompt>" "<title>"
```

The `<title>` becomes the tmux window name (e.g., the ticket ID).

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
```

For file-based items:

```
Run /task-workflow on the task file at: <absolute-path>

Read the file first to understand the scope, then execute the workflow.
```

Spawn workers **sequentially** (one Bash call at a time, not parallel).
Wait for each spawn to complete before starting the next.

### Step 5 — Report

After spawning, report to the user:

- Which item you are handling in this window
- Which items were dispatched to worker windows (with window names)
- How to switch between them: `Alt-1`, `Alt-2`, etc. (tmux window keys)

Then proceed with your own item's workflow — do not wait.

## Important

- The spawned parties run `claude --dangerously-skip-permissions`, so they
  execute autonomously. The prompt is all they get — make it complete.
- Each party creates its own worktree (per bugfix/task-workflow convention),
  so there are no git conflicts between sessions.
- If a Linear fetch fails, warn the user and skip that item (don't block the rest).
- Keep prompts under 500 characters to avoid shell quoting issues. For longer
  context, write the prompt to a temp file and use `--prompt "$(cat /tmp/party-prompt-N.md)"`.
