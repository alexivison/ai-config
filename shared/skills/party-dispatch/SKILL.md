---
name: party-dispatch
description: >-
  Dispatch one or more tasks to parallel party worker sessions. Promotes to
  master and delegates ALL items to workers — the master orchestrates but never
  implements. Supports freeform prompts (single worker), skill-based dispatch
  (multiple workers). Use when the user wants to spawn a worker, fix
  bugs, work on tickets in parallel, or says things like "spawn a worker to do
  X", "fix these tickets", "party bugfix", "dispatch these tasks", "send this
  to a worker", "party spawn". Supports Linear URLs/IDs, local file paths, and
  freeform prompts.
user-invocable: true
---

# Party Dispatch

Dispatch one or more work items to parallel party worker sessions. The master
promotes itself to orchestrator mode and delegates ALL items to workers — it
never takes an item for itself.

Works for any number of items: a single freeform task or a batch of tickets.

## Usage

**Single freeform task** (replaces the old `/party-spawn`):

```
/party-dispatch <title> <prompt>
```

**Multiple items with a skill**:

```
/party-dispatch <skill> <item1> <item2> [item3 ...]
```

- `<skill>` — the slash command to invoke (e.g., `/bugfix-workflow`, `/task-workflow`)
- `<title>` — short kebab-case name for a single freeform worker (e.g., `fix-auth-bug`)
- `<itemN>` — a Linear URL, Linear issue ID (e.g., `ENG-123`), or a local file path

If no arguments are provided, ask the user what they want to dispatch.

## Execution

### Step 1 — Parse and classify

Determine the dispatch mode from the arguments:

**Freeform mode** (single worker, no skill): The first argument is the title
(kebab-case), everything after is the prompt. Triggered when the first argument
doesn't look like a slash command and the intent is a single task.

**Skill mode** (one or more workers): The first argument is a skill name,
remaining arguments are work items. Classify each item:

| Pattern | Type | Example |
|---------|------|---------|
| `https://linear.app/...` | Linear URL | `https://linear.app/team/issue/ENG-123/title` |
| `TEAM-123` (letters-digits) | Linear ID | `ENG-456` |
| Anything else | File path | `libraries/.../TASK-01.md` |

### Step 2 — Gather context

- **Linear URL/ID**: Extract the issue identifier (the `TEAM-123` segment
  after `/issue/`). Fetch details via the current agent's available Linear
  integration or MCP tool. Extract: title, description, labels, priority,
  assignee. Fetch all in parallel when the mechanism supports it.
- **File path**: Read the file for context (title, scope, description).
- **Freeform**: The user's prompt is the context — no fetching needed.

### Step 3 — Promote to master

Discover the current tmux session name:

```bash
tmux display-message -p '#{session_name}'
```

Check if already a master by reading the manifest:

```bash
jq -r '.session_type' ~/.party-state/<session-name>.json
```

If not already a master, promote:

```bash
party-cli promote <session-name>
```

This replaces the companion pane with the tracker and sets `session_type=master`.
If already a master, this is a no-op.

### Step 4 — Construct prompts and spawn workers

Spawn each item as a **detached worker session** registered with the master:

```bash
party-cli spawn <session-name> "<title>" --prompt "<prompt>"
```

The `<title>` becomes the worker session's window name.
Spawn workers **sequentially** (one Bash call at a time, not parallel).
Wait for each spawn to complete before starting the next.
Capture the output to extract the worker session ID.

#### Prompt construction

The prompt must be self-contained — the spawned primary agent has zero prior context.

**For skill-based items (Linear tickets):**

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
party-cli report "done: <one-line summary> | PR: <url or 'none'>"
```

**For file-based items:**

```
Run /task-workflow on the task file at: <absolute-path>

Read the file first to understand the scope, then execute the workflow.

When done, report completion to the master:
party-cli report "done: <one-line summary> | PR: <url or 'none'>"
```

**For freeform tasks:**

Build a self-contained prompt from the user's description. Always include the
repo working directory so the worker knows where to operate. If the prompt
references files, use absolute paths.

**CRITICAL — Every worker prompt MUST end with the report-back instruction:**

```
When done, report completion to the master:
party-cli report "done: <one-line summary> | PR: <url or 'none'>"
```

Workers that don't receive this instruction will silently finish without
notifying the master.

For small deliverables where the answer itself matters (a joke, title, short
diagnosis, one-line recommendation), tell the worker to include the actual
deliverable in the `party-cli report` message rather than a placeholder summary.

**Short prompts** (under 400 characters total): pass inline via `--prompt`.

**Long prompts** (400+ characters): write to a temp file and use shell
substitution:

```bash
cat > /tmp/party-prompt-N.md <<'PROMPT_EOF'
<full prompt text>
PROMPT_EOF

party-cli spawn <session-name> "<title>" --prompt "$(cat /tmp/party-prompt-N.md)"
```

### Step 5 — Create tracker and report

After spawning all workers, create a task list or tracker entry using the
current agent's available task-tracking mechanism. Each task should include the
worker session name, item ID, and current status:

```
- [ ] party-1234 | ENG-123 — Fix auth bug | dispatched
- [ ] party-1235 | fix-config — Freeform: update config paths | dispatched
```

Then report to the user:

- All dispatched workers (session names and items)
- How to check on workers: `party-cli read <worker-id>`
- How to switch between them: use the tracker or tmux session picker
- Point to the task list for live tracking

Do not wait for workers — proceed to orchestration immediately.

## Ongoing Orchestration

After dispatch the master session stays active to coordinate workers through
their entire lifecycle. The master is an orchestrator, never an implementor.

### Monitoring workers

- **Check status**: `party-cli workers` to see all workers and their state
- **Read scrollback**: `party-cli read <worker-id>` (default 50 lines)
  or `party-cli read <worker-id> --lines 200` for deeper history
- **Watch tracker pane**: the left pane shows real-time worker status

### Handling worker reports

Workers report back via `[WORKER:<session-id>]` prefixed messages. When a
report arrives:

1. Read the report content
2. Update the corresponding task/tracker entry with the current agent's available mechanism (mark completed, add summary)
3. If the worker opened a PR, note the PR URL in the task
4. **ALWAYS review the PR** — proceed to "Reviewing worker PRs" below
5. Check if all workers are done — if so, proceed to final summary

### Relaying follow-up instructions

When a worker needs guidance or additional work:

```bash
party-cli relay <worker-id> "instruction text"
```

**Relay observations, not prescriptions.** The worker is a primary agent
with its own judgement — give it what it needs to decide, not the decision.
By default, a relay should carry:

- **What's wrong or what's needed** — one sentence
- **Pointers** — file:line citations, log excerpts, links, or a path to a
  findings file. Forward evidence; don't rewrite it as fix instructions.
- **Constraints / scope** — must not touch X; stay within Y
- **Done when** — how the worker (and you) will know it's resolved

Only prescribe an approach when one of these is true:

- The worker asked for direction
- The change is mechanical with a single correct fix (typo, rename, missing
  null check on a path you already verified)
- The worker is stuck after 2+ attempts on the same point and a hint will
  unblock it

When you do prescribe, mark it as `Approach hint:` so authorship of the
decision stays with the worker.

For broadcasts to all workers:

```bash
party-cli broadcast "message"
```

### Reviewing worker PRs (MANDATORY)

**Every PR from a worker MUST be reviewed by the master before approving.**
This applies regardless of how many workers were spawned — single or batch.
No exceptions.

When a worker completes and opens a PR:

1. **Read the PR**: `gh pr view <number>` and `gh pr diff <number>`
2. **Check CI status**: `gh pr checks <number>`
3. **If CI fails**: read the failure logs, capture the relevant excerpts and
   the failing file:line, and relay those observations to the worker. Let the
   worker diagnose and choose the fix — don't pre-write it.
4. **Run `/companion-review`** on the PR diff for a structured quality review
5. **If blocking issues found**: forward the findings file path plus any
   scope guidance. The findings already contain file:line and a verdict — let
   the worker triage like any primary agent would. Wait for the worker to
   push fixes and re-review.
6. **If review passes and CI is green**: approve and merge the PR
7. **Update the task list** with the final status (merged, or needs-rework)

**Do NOT skip review for "simple" or "obvious" PRs.** The review obligation
is unconditional.

### Handling worker failures

If a worker appears stuck or reports an error:

1. Read scrollback: `party-cli read <worker-id> --lines 200`
2. Identify what the worker can't see for itself — a different error
   elsewhere, a missing constraint, an unread file
3. Relay the missing observation, not a fix. If the worker has been stuck
   on the same point for 2+ attempts, an `Approach hint:` is appropriate;
   before that, more context usually unblocks better than prescription.
4. If the worker is unrecoverable, note it in the task list and consider
   spawning a replacement worker

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
  All code changes must be delegated to a worker via `party-cli relay`.
  This applies in every scenario: new bugs found during testing, quick
  one-line fixes, "obvious" changes — no exceptions.
- **Relay observations, not prescriptions** — Forward the evidence the
  worker needs (file:line, log excerpts, findings paths, scope) and let it
  choose the fix. Prescribe only when the worker asks, the change is
  mechanical with one correct fix, or the worker is stuck after 2+ attempts.
  Mark prescriptions as `Approach hint:` so authorship stays with the worker.
- **Review every PR** — No worker PR gets merged without a master review.

## Master Session Mode

Any party session can be promoted to master: `party-cli promote [party-id]`. This replaces the companion pane with a tracker pane and sets `session_type` to `master`. Promotion is non-destructive and works mid-session.

When running in a master session (`session_type == "master"` in manifest):
- You are an **orchestrator**, not an implementor.
- **HARD RULE:** Never use Edit or Write on production code. Investigation (Read, Grep, Glob, read-only Bash) is fine — all code changes go to a worker. No exceptions: not for "quick fixes", not for bugs found during testing, not for "obvious" one-liners.
- There is **no companion pane** — the agent-transport script `tmux-companion.sh` will return `COMPANION_NOT_AVAILABLE`.
- Skip companion review/plan-review/prompt steps entirely.
- Use `/party-dispatch` to dispatch any number of tasks to workers (single freeform, batch tickets, or mixed).
- Monitor workers via the tracker pane (left pane).

**Communication with workers:**
- `party-cli relay <worker-id> "instruction"` — send a message to a worker's primary pane
- `party-cli broadcast "message"` — send to all workers
- `party-cli read <worker-id>` — read the last 50 lines of a worker's primary pane
- `party-cli read <worker-id> --lines 200` — read more scrollback
- `party-cli workers` — show all workers and their status
- Workers report back via `[WORKER:<session-id>]` prefixed messages to your pane

**Worker report-back and PR review obligations** are defined in the "Ongoing Orchestration" section above — follow those rules for every dispatch.

## Important

- The spawned workers run whatever CLI is configured for the primary role,
  so they execute autonomously. The prompt is all
  they get — make it complete.
- Each worker creates its own worktree (per workflow conventions), so there
  are no git conflicts between sessions.
- If a Linear fetch fails, warn the user and skip that item (don't block the rest).
- Keep prompts under 500 characters to avoid shell quoting issues. For longer
  context, write the prompt to a temp file and use `--prompt "$(cat /tmp/party-prompt-N.md)"`.
