---
name: party-spawn
description: >-
  Spawn a single worker session with a freeform prompt. Auto-promotes to master
  if needed. Use when the user wants to send one task to a worker while
  continuing in the current session, says things like "spawn a worker to do X",
  "send this to a worker", "party spawn", or wants to delegate a single piece of
  work without batch dispatch.
user-invocable: true
---

# Party Spawn

Spawn a single detached worker session with a freeform task prompt. The master
session continues working while the worker executes autonomously.

For batch dispatch of multiple items to parallel workers, use `/party-dispatch`.

## Usage

```
/party-spawn <title> <prompt>
```

- `<title>` — short kebab-case name for the worker session (e.g., `fix-auth-bug`)
- `<prompt>` — the task description (inline or multi-line)

If no arguments are provided, ask the user for a title and prompt.

## Execution

### Step 1 — Parse arguments

Extract the title (first argument) and the prompt (everything after).

If no arguments were provided, ask the user:
1. What should the worker do? (the prompt)
2. A short title for the session (suggest one based on the prompt)

### Step 2 — Ensure master mode

Discover the current tmux session name:

```bash
tmux display-message -p '#{session_name}'
```

Check if this is a **master session** by reading the manifest:

```bash
cat ~/Code/ai-config/session/manifests/<session-name>.json | jq -r '.session_type'
```

**If not a master**, promote first:

```bash
~/Code/ai-config/session/party.sh --promote <session-name>
```

### Step 3 — Construct the worker prompt

Build a self-contained prompt. The spawned Claude has zero prior context — the
prompt is everything it knows.

**Always append the report-back instruction:**

```
When done, report completion to the master:
~/Code/ai-config/session/party-relay.sh --report "done: <one-line summary> | PR: <url or 'none'>"
```

**Short prompts** (under 400 characters total): pass inline via `--prompt`.

**Long prompts** (400+ characters): write to a temp file and pass via shell
substitution:

```bash
cat > /tmp/party-spawn-prompt.md <<'PROMPT_EOF'
<full prompt text>
PROMPT_EOF

~/Code/ai-config/session/party.sh --detached --master-id <session-name> \
  --prompt "$(cat /tmp/party-spawn-prompt.md)" "<title>"
```

### Step 4 — Spawn the worker

```bash
~/Code/ai-config/session/party.sh --detached --master-id <session-name> \
  --prompt "<constructed-prompt>" "<title>"
```

Capture the output to extract the worker session ID.

### Step 5 — Report to user

Tell the user:
- Worker session name and title
- How to check on it: `party-relay.sh --read <worker-id>`
- How to switch to it: `party.sh --switch` or `prefix + s`
- That the worker will report back via `[WORKER:<id>]` when done

Then continue with whatever the master was doing — do not wait for the worker.

## Handling Worker Completion

When the worker reports back via `[WORKER:<id>]` with a PR URL:

1. Read the PR: `gh pr view <number>` and `gh pr diff <number>`
2. Check CI status: `gh pr checks <number>`
3. If CI fails, relay fix instructions to the worker via `party-relay.sh`
4. Run `/code-review` on the PR diff for a structured quality review
5. If blocking issues found, relay findings with file:line context to the worker
6. If review passes and CI is green, approve and merge the PR

## Important

- The spawned worker runs `claude --dangerously-skip-permissions` — make the
  prompt complete and unambiguous.
- Each worker creates its own worktree (per workflow conventions), so there are
  no git conflicts.
- Always include the repo working directory in the prompt so the worker knows
  where to operate.
- If the prompt references files, use absolute paths.
- Never spawn more than one worker per invocation — use `/party-dispatch` for
  batch work.
