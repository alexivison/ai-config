# Evidence Log Migration + Quick-Fix Skill + skill-eval Removal

## Context

The current PR gate system uses 7 marker files in `/tmp/` to track workflow completion state. When code is edited, `marker-invalidate.sh` deletes all markers, forcing full re-review. This works but has problems:
- Marker files are fragile (race conditions, no audit trail, no metadata)
- Invalidation is all-or-nothing (editing one file wipes all evidence)
- No way to implement tiered gates (small fixes requiring fewer checks)
- Adding the quick-fix-workflow skill requires a lighter gate path

**Solution:** Replace marker files with a single JSONL evidence log per session. Each entry records a `diff_hash` (SHA-256 of the branch diff from merge-base). Gate hooks compute the current diff hash and only accept evidence with a matching hash. This eliminates `marker-invalidate.sh` entirely — stale evidence is automatically ignored.

## Implementation Plan

### Step 1: Create shared evidence library
**New file: `claude/hooks/lib/evidence.sh`**

Sourced by all writer/reader hooks. Functions:

- `evidence_file(session_id)` → `/tmp/claude-evidence-${session_id}.jsonl`
- `compute_diff_hash(cwd)` → SHA-256 of `git diff $(git merge-base $default_branch HEAD)..HEAD -- . ':!*.md' ':!*.log' ':!*.jsonl' ':!*.tmp'`
  - Returns `"clean"` if merge-base equals HEAD (no branch diff)
  - Returns `"unknown"` if not a git repo or cwd missing
  - Detects default branch (main vs master)
- `append_evidence(session_id, type, result, cwd)` → computes diff_hash, appends JSONL line
- `check_evidence(session_id, type, cwd)` → returns 0 if matching type+diff_hash exists
- `check_all_evidence(session_id, types_string, cwd)` → checks multiple types, outputs missing ones to stdout
- `diff_stats(cwd)` → outputs `lines files new_files` for tiered gate decisions

### Step 2: Create evidence library tests
**New file: `claude/hooks/tests/test-evidence.sh`**

Tests in a temp git repo (mktemp -d, git init, trap cleanup):
- `compute_diff_hash` consistency, change detection, .md exclusion, clean state
- `append_evidence` creates valid JSONL
- `check_evidence` matches/rejects on diff_hash and type
- `check_all_evidence` returns missing types
- `diff_stats` returns correct counts

### Step 3a: Migrate `agent-trace-stop.sh`
**Modify: `claude/hooks/agent-trace-stop.sh` (lines 94-112)**

- Add `source "$(dirname "$0")/lib/evidence.sh"` after line 13
- Replace 4 `touch` blocks with `append_evidence` calls
- Verdict detection (lines 30-68) and trace logging (lines 70-92) unchanged

### Step 3b: Migrate `codex-trace.sh`
**Modify: `claude/hooks/codex-trace.sh` (lines 54-72)**

- Add `source` of evidence.sh
- Extract `cwd` from hook input
- Replace `touch` with `append_evidence` for codex-ran and codex types
- Replace `[ -f marker ]` prerequisite check with `check_evidence` for codex-ran

### Step 3c: Migrate `skill-marker.sh`
**Modify: `claude/hooks/skill-marker.sh` (lines 25-29)**

- Add `source` of evidence.sh
- Extract `CWD` from input
- Replace `touch` with `append_evidence` for pr-verified type

### Step 4a: Migrate `pr-gate.sh` with tiered gate
**Modify: `claude/hooks/pr-gate.sh` (lines 46-73)**

- Add `source` of evidence.sh
- Keep docs-only bypass (lines 27-44) as-is
- After docs-only check, compute diff_stats
- **Tiered gate:** if `lines ≤ 30 AND files ≤ 3 AND new_files == 0` → require only `test-runner check-runner`
- **Full gate:** otherwise → require `pr-verified code-critic minimizer codex test-runner check-runner`
- Use `check_all_evidence` to find missing types
- Same deny JSON format as current

### Step 4b: Migrate `codex-gate.sh`
**Modify: `claude/hooks/codex-gate.sh` (lines 27-70)**

- Add `source` of evidence.sh
- Extract `CWD` from input
- Replace `[ -f marker ]` checks with `check_evidence`/`check_all_evidence`

### Step 5: Update existing tests
**Modify: `claude/hooks/tests/test-agent-trace.sh`**
- Replace marker file assertions (`[ -f /tmp/claude-* ]`) with JSONL grep checks
- Setup: create temp git repo for diff_hash computation, pass as cwd in test inputs
- Cleanup: remove evidence JSONL files

**Modify: `claude/hooks/tests/test-codex-trace.sh`**
- Same pattern: replace `touch`/`[ -f ]` with `append_evidence`/JSONL grep
- Temp git repo setup for cwd
- Workflow simulation: evidence log instead of marker files

**Modify: `claude/hooks/tests/test-codex-gate.sh`**
- Replace `touch` marker setup with `append_evidence` calls
- Temp git repo for diff_hash

### Step 6: Create PR gate tests
**New file: `claude/hooks/tests/test-pr-gate.sh`**

- Full gate: blocks when evidence missing, allows when all present
- Full gate: blocks on stale diff_hash
- Tiered gate: small diff needs only test-runner + check-runner
- Tiered gate: large diff (>30 lines) requires full evidence
- Tiered gate: new files require full evidence
- Docs-only bypass still works

### Step 7: Remove obsolete hooks and wiring
**Modify: `claude/settings.json`**
- Remove `Edit|Write` PostToolUse entry (marker-invalidate.sh) — lines 155-163
- Remove `UserPromptSubmit` entry (skill-eval.sh) — lines 85-93

**Delete: `claude/hooks/marker-invalidate.sh`**
**Delete: `claude/hooks/tests/test-marker-invalidate.sh`**
**Delete: `claude/hooks/skill-eval.sh`**

### Step 8: Update session cleanup
**Modify: `claude/hooks/session-cleanup.sh`**
- Add `find /tmp -maxdepth 1 -name "claude-evidence-*.jsonl" -mtime +1 -delete`
- Keep old marker cleanup for transition

### Step 9: Create quick-fix-workflow skill
**New file: `claude/skills/quick-fix-workflow/SKILL.md`**

Frontmatter: name, description, user-invocable: true

Flow:
1. Pre-gate: working tree must be clean (or use --worktree)
2. Implement the change
3. Size guardrail: compute diff stats. If >30 lines / >3 files / new files → warn, suggest task-workflow/bugfix-workflow
4. Run test-runner sub-agent
5. Run check-runner sub-agent
6. Commit and create PR (tiered gate allows this)

Non-goals: no RED phase, no critics, no codex, no adversarial review, no pre-pr-verification

## Dependency Order

```
Step 1 (evidence.sh)
  ↓
Step 2 (test-evidence.sh)        ← verify foundation
  ↓
Steps 3a, 3b, 3c (writers)      ← parallel
  ↓
Steps 4a, 4b (readers)          ← parallel
  ↓
Steps 5, 6 (test updates)       ← parallel
  ↓
Step 7 (remove old hooks)
  ↓
Step 8 (cleanup)
  ↓
Step 9 (quick-fix-workflow skill)
```

## Verification

1. Run `bash ~/.claude/hooks/tests/run-all.sh` — all tests pass
2. Manual: simulate agent-trace-stop with code-critic APPROVED → check JSONL entry exists with diff_hash
3. Manual: edit a file → re-run agent-trace-stop → new entry has different diff_hash → old evidence ignored by gate
4. Manual: test tiered gate with small diff → only test-runner + check-runner required
5. Manual: test full gate with large diff → all 6 evidence types required

## Files Summary

| Action | File |
|--------|------|
| NEW | `claude/hooks/lib/evidence.sh` |
| NEW | `claude/hooks/tests/test-evidence.sh` |
| NEW | `claude/hooks/tests/test-pr-gate.sh` |
| NEW | `claude/skills/quick-fix-workflow/SKILL.md` |
| MODIFY | `claude/hooks/agent-trace-stop.sh` |
| MODIFY | `claude/hooks/codex-trace.sh` |
| MODIFY | `claude/hooks/skill-marker.sh` |
| MODIFY | `claude/hooks/pr-gate.sh` |
| MODIFY | `claude/hooks/codex-gate.sh` |
| MODIFY | `claude/hooks/tests/test-agent-trace.sh` |
| MODIFY | `claude/hooks/tests/test-codex-trace.sh` |
| MODIFY | `claude/hooks/tests/test-codex-gate.sh` |
| MODIFY | `claude/hooks/session-cleanup.sh` |
| MODIFY | `claude/settings.json` |
| DELETE | `claude/hooks/marker-invalidate.sh` |
| DELETE | `claude/hooks/tests/test-marker-invalidate.sh` |
| DELETE | `claude/hooks/skill-eval.sh` |
