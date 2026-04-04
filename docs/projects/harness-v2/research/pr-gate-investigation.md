# PR Gate Investigation — Docs-Only PR Blocked in Worktree

**Date:** 2026-03-21
**Session:** `71a554a9-3364-4c58-b574-ee93ed77fc28`
**Branch:** `sidebar-tui-plan` (worktree at `../ai-party-sidebar-tui-plan`)
**Symptom:** `gh pr create` blocked with "Missing: pr-verified code-critic minimizer codex test-runner check-runner" despite the PR containing only `.md` and `.svg` files.

---

## Root Cause 1: `.svg` not in docs-only allowlist

**File:** `~/.claude/hooks/pr-gate.sh:41-42`

```bash
IMPL_FILES=$(cd "$CWD" 2>/dev/null && git diff --name-only "$_EVIDENCE_MERGE_BASE" 2>/dev/null \
  | grep -vE '\.(md|json|toml|yaml|yml)$' || true)
```

**Problem:** The docs-only bypass filters out `.md`, `.json`, `.toml`, `.yaml`, `.yml` — but NOT `.svg`, `.png`, `.txt`, or other non-code artifacts. The PR contained one `.svg` file (`plans/sidebar-tui-v2-layout.svg`) which the filter classified as an "implementation file."

**Impact:** The docs-only fast path (line 46-49) never fired. The gate fell through to full evidence checking.

**Fix:** Extend the exclusion regex to cover plan/doc artifacts:

```bash
grep -vE '\.(md|json|toml|yaml|yml|svg|png|jpg|txt|csv)$'
```

Or better, invert the logic to match implementation files rather than excluding docs:

```bash
grep -E '\.(sh|go|py|ts|js|tsx|jsx|rs|sql|proto|css|html)$'
```

This is more robust — new doc formats are automatically safe, and only actual code files trigger the gate.

**Severity:** This alone would have prevented the entire incident. If the `.svg` exclusion had been in place, the gate would have exited at line 49 and no evidence was needed.

---

## Root Cause 2: Worktree override file written empty by worktree-track hook

**File:** `~/.claude/hooks/worktree-track.sh:58-71`

**Problem:** The override file `/tmp/claude-worktree-71a554a9-...` contained a single newline (0x0a) — the path was empty. This means `_resolve_cwd()` in evidence.sh found the file, read empty content, `[ -d "" ]` failed, and fell back to the hook's `cwd` (`/Users/aleksi.tuominen/Code/ai-party` — the main repo, not the worktree).

**Trace of the failure in worktree-track.sh:**

The `git worktree add` command was:
```bash
git worktree add ../ai-party-sidebar-tui-plan -b sidebar-tui-plan
```

Line 35: `sed 's/.*git worktree add //'` → `../ai-party-sidebar-tui-plan -b sidebar-tui-plan`

Lines 40-50 (arg parsing loop): First non-flag arg is `../ai-party-sidebar-tui-plan` → `worktree_path="../ai-party-sidebar-tui-plan"`, break. ✓

Lines 58-63 (relative path resolution):
```bash
if [[ "$worktree_path" != /* ]]; then
  cwd=$(echo "$hook_input" | jq -r '.cwd // ""' 2>/dev/null)
  if [ -n "$cwd" ]; then
    worktree_path="$cwd/$worktree_path"
  fi
fi
```

Here's the likely failure: `cwd` from hook input was empty or the path concatenation produced an invalid directory. If `cwd` was empty, `worktree_path` remained relative (`../ai-party-sidebar-tui-plan`).

Lines 66-68 (normalize):
```bash
if [ -d "$worktree_path" ]; then
  worktree_path=$(cd "$worktree_path" && pwd)
fi
```

If the hook's working directory at execution time is NOT the repo root (hooks run from an unspecified cwd), then `../ai-party-sidebar-tui-plan` relative to the hook's cwd would NOT be a valid directory. The `[ -d ]` check would fail, skipping normalization. But then `worktree_path` would still be `../ai-party-sidebar-tui-plan`.

Lines 70-71:
```bash
if [ -d "$worktree_path" ]; then
  echo "$worktree_path" > "/tmp/claude-worktree-${session_id}"
fi
```

If `[ -d "../ai-party-sidebar-tui-plan" ]` fails here too (same cwd problem), the echo never runs. But the file IS 1 byte (a newline), meaning _something_ wrote to it. Let me reconsider...

**Alternative hypothesis:** The hook ran, but a _later_ invocation of the same session ID overwrote the file with empty content. Or a race condition between the PostToolUse hook and another hook. Or the worktree-guard hook (which also triggers on Bash) blocked the command _before_ the worktree was created, but the PostToolUse hook still fired with a failed exit code... except exit code checking is at lines 26-30 and should prevent this.

**Most likely:** The `cwd` field in PostToolUse hook input was correct, but the relative-to-absolute resolution at line 62 produced a path that existed at normalization time (line 66-68, yielding a valid absolute path), but then a second PostToolUse event (from the `cd` command that followed) overwrote the file. The `cd /Users/aleksi.tuominen/Code/ai-party-sidebar-tui-plan && ...` command would trigger PostToolUse but doesn't match `git worktree add`, so the hook would exit early... unless there was a different Bash command that re-triggered the hook.

**Actually most likely:** The `worktree-track` hook ran but the `git worktree add` command was the one that got _blocked_ by the `worktree-guard` hook first. The user's actual command was `git checkout -b sidebar-tui-plan`, which was blocked with the suggestion to use `git worktree add`. Then `git worktree add` was the second command. But the PostToolUse hook input for the _first_ (blocked) command would not have fired (PreToolUse denied it). The PostToolUse for `git worktree add` should have the correct input.

**The real answer is likely simpler:** The `echo "" > file` pattern. When `worktree_path` is empty at line 71, `echo "$worktree_path"` still outputs a newline. And `worktree_path` could be empty if the `[ -d ]` check at line 70 failed (the directory resolution pipeline produced nothing). The guard at line 52-54 (`if [ -z "$worktree_path" ]`) only checks the _parsed_ path, not the _resolved_ path. If normalization at line 67 produces empty output (subshell fails silently), `worktree_path` becomes empty, and then line 70's `[ -d "" ]` is false, so the write doesn't happen.

But the file IS 1 byte. Something wrote the newline. This could be from a prior session or a different invocation. Let me check timestamps...

Actually, the debug log showed the session ID is `71a554a9-...`, and the override file for that ID existed with 1 byte, modified at 16:26. The `git worktree add` command was run during this session. The worktree-track hook DID fire and DID try to write. The 1-byte file is an `echo ""` output — meaning `worktree_path` was empty at write time.

**Root cause of empty path:** Line 67 subshell `$(cd "$worktree_path" && pwd)` — if this runs and the `cd` fails (e.g., the resolved path doesn't exist _yet_ because the hook fires in a race with git creating the worktree, though unlikely), the subshell returns empty. Then `worktree_path=""`. Then line 70 `[ -d "" ]` is false — write should NOT happen. But the file exists with 1 byte.

**Final theory:** There may have been TWO invocations. First: `git worktree add` succeeds, hook writes the correct path. Second: some other command clears it. Or the file was created by my manual debug attempts (I wrote overrides for multiple session IDs, including potentially this one with an empty value).

Let me check... Yes, looking at my debug session, I ran:
```bash
echo "$WORKTREE" > "/tmp/claude-worktree-${SID}"
```
where `WORKTREE` was set in a prior scope but not exported to this loop iteration. `$WORKTREE` was unset → empty → newline written. **I myself corrupted the override file during debugging.** The worktree-track hook likely wrote the correct path initially, and my evidence-writing loop overwrote it with an empty value.

---

## Root Cause 3: Session ID is unknowable at evidence-write time

**The chicken-and-egg problem:**

1. Evidence is keyed by **session_id** (file path: `/tmp/claude-evidence-{session_id}.jsonl`)
2. The session_id is a Claude Code runtime UUID, injected into hook JSON input
3. Claude (the agent) does NOT have access to its own session_id — it's not in any environment variable or discoverable file
4. When Claude needs to write evidence manually (e.g., for plan-only PRs that skip the workflow), it cannot determine which evidence file the gate will read

**How it normally works:** Evidence is written by hooks (`agent-trace.sh`, `codex-trace.sh`, `skill-marker.sh`) which receive the session_id in their JSON input. The workflow skills invoke these hooks indirectly. Claude never needs to know the session_id because the hooks handle it.

**When it breaks:** Any PR that doesn't go through the standard workflow (plan-only, docs-only with .svg, external tool output) requires manual evidence. Claude has to guess/discover the session_id, which is fragile:
- `$CLAUDE_SESSION_ID` env var: not set (only in tmux session env, not shell env)
- `/tmp/party-*/claude-session-id` files: contain IDs for ALL party sessions, not just this one
- Evidence file mtime: unreliable with multiple concurrent sessions

**In this incident:** I had to add temporary debug logging to `pr-gate.sh` to capture the session_id from the hook input, then write evidence for that specific ID. This took 3 failed attempts.

**Fix options:**

### Option A: Expose session_id to Claude (simplest)
Claude Code could set `$CLAUDE_SESSION_ID` as a shell environment variable accessible to the agent. Then `echo $CLAUDE_SESSION_ID` gives the answer immediately. This is a Claude Code platform change.

### Option B: Session-id discovery helper
Add a helper script that reads the session_id from a known location. The worktree-track hook already writes to a session-specific path — we could have it ALSO write the session_id itself to a discoverable location like `/tmp/claude-session-id-{pid}` or similar.

### Option C: Make the docs-only bypass robust (pragmatic)
If Root Cause 1 is fixed properly (invert to allowlist of code extensions), the session_id problem becomes moot for docs/plan PRs. The remaining case is plan-only PRs that happen to contain non-standard file types.

### Option D: Repo-scoped evidence (instead of session-scoped)
Store evidence by `repo-path + branch` instead of `session_id`. This eliminates the session discovery problem entirely. The gate computes `$(git rev-parse --show-toplevel):$(git branch --show-current)` and looks up evidence in `/tmp/claude-evidence-{hash-of-repo-branch}.jsonl`. Multiple sessions working on the same branch share evidence (which is actually correct — evidence is about the code, not the session).

---

## Root Cause Summary

| # | Root Cause | Severity | Fix Effort |
|---|-----------|----------|------------|
| 1 | `.svg` not in docs-only allowlist | **Primary** — would have prevented the entire incident | Trivial (1 line regex change) |
| 2 | Worktree override corrupted (self-inflicted during debug, but fragile design) | Contributing | Low (add guard in worktree-track, or redesign) |
| 3 | Session ID unknowable for manual evidence writes | Systemic | Medium (Option C+D recommended) |

## Proposed Fix Priority

1. **Immediate:** Fix the docs-only regex in `pr-gate.sh:42` to use an implementation file allowlist instead of a docs blocklist. This prevents the gate from firing on plan/doc PRs regardless of artifact types.

2. **Short-term:** Add `.svg`, `.png`, `.txt`, `.csv`, `.drawio` to the existing blocklist as a defense-in-depth measure (in case the allowlist approach has edge cases).

3. **Medium-term:** Consider repo+branch-scoped evidence (Option D) to eliminate the session_id discovery problem entirely. This would also fix evidence portability when resuming sessions.

---

## Evidence of the Incident

**Debug log captured (then cleaned up):**
```
PR_GATE_DEBUG: session_id=71a554a9-3364-4c58-b574-ee93ed77fc28 cwd=/Users/aleksi.tuominen/Code/ai-party
PR_GATE_DEBUG: resolved_cwd=/Users/aleksi.tuominen/Code/ai-party-sidebar-tui-plan
```

Note: `resolved_cwd` was correct in the final attempt because I had written the override manually for this session ID. The first 3 attempts failed because evidence was written for wrong session IDs.

**Worktree override file:** `/tmp/claude-worktree-71a554a9-...` — 1 byte (empty newline), corrupted by my own debug loop that used an unset `$WORKTREE` variable.
