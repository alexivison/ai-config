# Workflow Layer Research Report

**Date:** 2026-03-21
**Scope:** Skills, hooks, evidence system, rules, Codex integration, code debt
**Method:** Direct codebase analysis + Codex deep reasoning (pending)

---

## Executive Summary

The ai-party workflow layer is a sophisticated but heavyweight system for enforcing quality gates on an AI-assisted development workflow. It comprises **14 skills** (2,579 lines), **11 hooks + 2 libraries** (1,264 lines), **1,987 lines of hook tests**, **7 rule files** (311 unique lines), and a JSONL-based evidence system with diff_hash matching.

**Key findings:**
1. The evidence system is well-designed post-phase-simplification but session-scoped evidence creates friction for branch-hopping workflows
2. `agent-trace-stop.sh` (188L) is doing too much — oscillation detection should be extracted
3. Three workflow skills (task/bugfix/quick-fix) share ~70% DNA via execution-core; consolidation is possible but has tradeoffs
4. The tmux transport is inherently fragile (fire-and-forget, no delivery guarantee)
5. `execution-core.md` is right-sized post-simplification — the decision matrix and violation patterns are actively useful
6. Test-to-code ratio is healthy (1,987 test lines / 1,264 hook lines = 1.57:1)

---

## Skill Inventory

| # | Skill | Lines (SKILL.md) | Total Lines | User-Invocable | Trigger Accuracy | Overlap |
|---|-------|-------------------|-------------|----------------|------------------|---------|
| 1 | plan-workflow | 234 | 234 | yes | Good — "plan", "approach", Linear ticket | None |
| 2 | design-check | 169 | 293 | yes | Good — "matches design", "Figma" | None |
| 3 | party-dispatch | 151 | 151 | yes | Good — "dispatch", "parallel", multiple items | None |
| 4 | codex-transport | 111 | 563 | no | N/A (internal) | None |
| 5 | autoskill | 119 | 119 | yes | Good — "learn from", "remember pattern" | None |
| 6 | task-workflow | 105 | 105 | yes | Good — TASK*.md, "implement" | **High w/ bugfix** |
| 7 | tmux-handler | 104 | 104 | no | N/A — triggered by [CODEX] messages | None |
| 8 | pre-pr-verification | 95 | 95 | no | N/A (internal) | None |
| 9 | quick-fix-workflow | 87 | 87 | yes | Good — "quick fix", "small change" | **Partial w/ task** |
| 10 | write-tests | 83 | 615 | no | Good — "write tests", TDD | None |
| 11 | code-review | 83 | 268 | no | Good — "review" | None |
| 12 | address-pr | 84 | 84 | yes | Good — "PR comments", "review feedback" | None |
| 13 | pr-descriptions | 72 | 72 | no | N/A (internal) | None |
| 14 | bugfix-workflow | 64 | 64 | yes | Good — "bug", "error", "crash" | **High w/ task** |

**Total:** 1,561 lines in SKILL.md files, 2,579 lines including reference docs and scripts.

### Overlap Analysis

**task-workflow ↔ bugfix-workflow:** These share the execution-core sequence entirely. bugfix-workflow is a 64-line "delta document" that says "same as task-workflow but: no checkboxes, investigation gate, regression test first." The separation is conceptually clean (planned work vs reactive fixes) but creates maintenance burden when execution-core changes.

**quick-fix-workflow:** A legitimate separate tier — it explicitly skips critics and Codex. The size gates (≤30L, ≤3 files, 0 new) are a hard boundary. This should stay separate.

### Trigger Accuracy Assessment

All skill descriptions are well-tuned. The frontmatter `description` fields use clear trigger phrases. No false-positive risks identified. The `user-invocable: false` skills correctly prevent direct invocation while remaining available to the workflow.

### SKILL.md Format Efficiency

The format is reasonable. Most overhead comes from:
- Repeated execution-core references (could be a single `@import` if supported)
- Inline code examples in codex-transport (111L, but necessary for correctness)
- plan-workflow is the largest at 234L — largely because it scripts the Codex orchestration dance in detail

**Verdict:** Not bloated. The largest skills (plan-workflow, design-check) are genuinely complex. Reference docs (write-tests: 532L, code-review: 185L) are separate files, keeping SKILL.md focused.

---

## Hook Inventory

| # | Hook | Trigger | Lines | Complexity | Purpose |
|---|------|---------|-------|------------|---------|
| 1 | evidence.sh (lib) | N/A (sourced) | 353 | **High** | Evidence JSONL: diff_hash, append, check, triage override, worktree resolution, atomic locking |
| 2 | agent-trace-stop.sh | SubagentStop | 188 | **High** | Verdict detection, evidence creation, oscillation detection (same-hash + cross-hash) |
| 3 | worktree-guard.sh | PreToolUse(Bash) | 152 | Medium | Block branch switching in main worktree, block sed -i/awk inplace |
| 4 | session-id-helper.sh (lib) | N/A (sourced) | 112 | Medium | Discover session ID from party state / worktree overrides / evidence files |
| 5 | pr-gate.sh | PreToolUse(Bash) | 93 | Medium | Block `gh pr create` without required evidence at current diff_hash |
| 6 | codex-trace.sh | PostToolUse(Bash) | 89 | Medium | Detect codex approval/triage-override from tmux-codex.sh stdout sentinels |
| 7 | worktree-track.sh | PostToolUse(Bash) | 82 | Low | Write worktree override file after `git worktree add` |
| 8 | codex-gate.sh | PreToolUse(Bash) | 49 | Low | Hard-block `--approve`, allow all other tmux-codex.sh commands |
| 9 | agent-trace-start.sh | SubagentStart | 45 | Low | Log sub-agent spawn events to trace JSONL |
| 10 | register-agent-id.sh | SessionStart | 34 | Low | Write Claude session ID to party state |
| 11 | skill-marker.sh | PostToolUse(Skill) | 34 | Low | Create `pr-verified` evidence when pre-pr-verification skill completes |
| 12 | session-cleanup.sh | SessionStart | 17 | Low | Delete stale evidence files (>24h) |
| 13 | push-lint-reminder.sh | PreToolUse(Bash) | 16 | Low | Non-blocking reminder before `git push` |

**Total:** 1,264 lines (hooks + libs), 1,987 lines (tests)

### Complexity Budget Analysis

**Over-budget:**
- `evidence.sh` (353L): This is a full library, not a hook. It handles diff computation, atomic locking (flock + mkdir fallback), worktree CWD resolution, evidence append/check, triage overrides, and stale diagnostics. It's well-factored internally but is approaching monolith territory. The `_resolve_cwd` function alone (30L) handles 4 edge cases.
- `agent-trace-stop.sh` (188L): Does three distinct jobs: (1) verdict detection via regex matching, (2) evidence creation for 4 agent types, (3) oscillation detection with two modes. The oscillation detection alone is 68 lines of complex logic (fingerprinting, cross-hash comparison, readarray). This should be a separate module.

**Right-sized:**
- `worktree-guard.sh` (152L): Complex but necessarily so — parsing git checkout/switch args with flags, validating refs, suggesting worktree alternatives. Each branch of logic handles a real edge case.
- `pr-gate.sh` (93L): Clean and focused. Two-tier logic is straightforward.
- `codex-trace.sh` (89L): Sentinel parsing is inherently messy but contained.

**Lean:**
- `codex-gate.sh` (49L), `skill-marker.sh` (34L), `push-lint-reminder.sh` (16L), `session-cleanup.sh` (17L): All appropriately simple.

### Hook Interactions and Race Conditions

**PreToolUse(Bash) chain:** `worktree-guard` → `codex-gate` → `pr-gate` → `push-lint-reminder`. These fire sequentially (settings.json array order). No race conditions possible — they read different state.

**PostToolUse(Bash) chain:** `codex-trace` → `worktree-track`. Independent state — no conflicts.

**SubagentStop → evidence writes:** `agent-trace-stop.sh` uses `_atomic_append()` with flock/mkdir locking. This correctly handles concurrent sub-agents (code-critic + minimizer in parallel) writing to the same evidence file. No race condition.

**Potential issue:** `evidence.sh` `_atomic_append()` has a spin-lock fallback (mkdir-based) with a 0.5s max wait. On a loaded system with many concurrent sub-agents, this could silently drop evidence. In practice, sub-agent concurrency is bounded to 2-3, so the risk is low.

### Test Suite Assessment

| Test File | Lines | Covers |
|-----------|-------|--------|
| test-evidence.sh | 402 | evidence.sh library (core) |
| test-agent-trace.sh | 353 | agent-trace-stop.sh (verdict detection, oscillation) |
| test-pr-gate.sh | 287 | pr-gate.sh (tiered gates, docs bypass) |
| test-codex-trace.sh | 229 | codex-trace.sh (sentinel parsing) |
| test-harness-hardening.sh | 192 | Cross-cutting: shell guard, hook resilience |
| test-toon-format.sh | 158 | TOON format validation |
| test-codex-gate.sh | 121 | codex-gate.sh (approve block) |
| test-session-id-helper.sh | 119 | session-id-helper.sh |
| test-worktree-track.sh | 98 | worktree-track.sh |
| run-all.sh | 28 | Test runner |

**Test-to-code ratio:** 1.57:1 (1,987 test / 1,264 code). Healthy.

**Coverage gaps:**
- `worktree-guard.sh` (152L) has no dedicated test file. This is the 3rd largest hook.
- `register-agent-id.sh` and `push-lint-reminder.sh` have no tests (acceptable — trivial hooks).
- `session-cleanup.sh` has no test (acceptable — just `find -delete`).

**Maintainability:** Tests are bash scripts using a simple pass/fail pattern. No test framework — just functions and assertions. This is appropriate for shell hooks but makes test discovery/selection harder. The `run-all.sh` runner is only 28 lines.

---

## Evidence System Assessment

### Post-Phase-Simplification State (PR #58)

PR #58 replaced the two-phase model with a single-phase model. The evidence system now:
- Uses a single JSONL log per session at `/tmp/claude-evidence-{session_id}.jsonl`
- Each entry has a `diff_hash` (SHA-256 of committed diff from merge-base)
- Evidence at a stale hash is automatically ignored (no invalidation needed)
- Oscillation detection was added (PR #56): same-hash alternation + cross-hash fingerprinting
- Triage overrides allow dismissing out-of-scope critic findings with rationale

### Diff-Hash Robustness

**Strengths:**
- Committed-only diffs (`merge-base..HEAD`) mean in-progress edits don't invalidate evidence while critics run
- SHA-256 of full diff content is collision-resistant
- Exclusion pattern (`':!*.md' ':!*.log' ':!*.jsonl' ':!*.tmp'`) prevents docs-only changes from invalidating code evidence

**Fragility points:**
- `merge-base` computation assumes a clean main/master branch. Rebasing main changes the merge-base, invalidating all evidence even if the PR diff is identical
- `shasum -a 256` availability is assumed (present on macOS/Linux but not guaranteed in all envs)
- The diff excludes file list (`_DIFF_EXCLUDES`) is hardcoded. A new non-code file type would need a code change

### Session-Scoped vs Repo+Branch-Scoped

**Current model:** Session-scoped. Each Claude Code session gets its own evidence file. Restarting the session (new terminal, crashed process) loses all evidence.

**Arguments for repo+branch-scoped:**
- Evidence survives session restarts
- Multiple sessions working on the same branch see each other's evidence
- More natural for long-lived branches

**Arguments for session-scoped (current):**
- Simpler — no coordination between sessions
- Clean separation prevents cross-contamination
- Session restart is a natural "start fresh" boundary (if evidence is stale, re-running is cheap)
- The worktree model means sessions ≈ branches in practice

**Verdict:** Session-scoped is correct for this architecture. The worktree isolation model (one session per worktree per branch) makes session ≈ branch already. The main gap is session restart losing evidence — this could be mitigated by naming evidence files after branch instead of session ID, but the added complexity isn't worth it given how cheap re-running critics is.

### Minimal Evidence System Design

If redesigned from scratch, the minimum viable evidence system would be:

```
1. A single file per branch: /tmp/claude-evidence-{repo}-{branch}.json
2. Contains: { critic_ok: bool, codex_ok: bool, tests_ok: bool, checks_ok: bool, diff_hash: string }
3. PR gate reads the file, checks diff_hash matches current, checks all bools
4. Any code edit resets all bools (new diff_hash)
```

That's ~50 lines vs the current ~350 (evidence.sh). The delta buys:
- Atomic locking for concurrent writes (real value)
- Triage overrides with audit trail (nice to have)
- Oscillation detection (questionable value — could be simpler)
- Stale evidence diagnostics (nice UX)
- Worktree CWD resolution (necessary complexity)

**Recommendation:** The current system is ~2x the minimal size. The extra complexity is defensible except for oscillation detection, which should be extracted.

---

## Rules Assessment

### execution-core.md (161 lines)

**Sections:**
1. Core Sequence (1 line of truth + 3 lines context)
2. RED Evidence Gate (5 lines)
3. Feature Flag Gate (5 lines)
4. Minimality Gate (7 lines)
5. Evidence System (14 lines)
6. Tiered Execution (7 lines)
7. Review Governance (20 lines)
8. Decision Matrix (22 lines — table)
9. Dispute Resolution (16 lines)
10. Valid Pause Conditions (2 lines)
11. Sub-Agent Behavior (3 lines)
12. Verification Principle (5 lines)
13. PR Gate (6 lines)
14. Violation Patterns (17 lines — table)

**Assessment:** Post-simplification, this is well-structured. The decision matrix is the most valuable section — it's the lookup table workers actually consult. The violation patterns table catches real anti-patterns (behavior change without RED, chase nits 2+ rounds, etc.).

**Worker compliance:** Based on session reports, workers follow execution-core reliably. The main pain points were:
1. ~~Two-phase review~~ (eliminated by PR #58)
2. Evidence invalidation on any edit (by design, but frustrating during iterations)
3. Dispute resolution complexity (rarely triggered in practice)

**Is it right-sized?** Yes. Every section serves a purpose. The document reads as a reference spec, not a tutorial — this is appropriate for agent consumption. Removing sections would create ambiguity that leads to workflow violations.

### Other Rule Files

| File | Lines | Purpose | Needed? |
|------|-------|---------|---------|
| general.md | 4 | Early returns, minimal comments | **Marginal** — could be in CLAUDE.md |
| json.md | 15 | TOON compression rules | **Yes** — prevents token waste on large JSON |
| backend/go.md | 52 | Go style, forbidden deps, project structure | **Yes** — project-specific |
| backend/python.md | 40 | Python style, tooling, project structure | **Yes** — project-specific |
| frontend/react.md | 26 | React patterns, useEffect rules | **Yes** — prevents common mistakes |
| frontend/typescript.md | 13 | TypeScript strictness | **Yes** — prevents `any` creep |

**general.md** at 4 lines is barely worth a file. Could merge into CLAUDE.md's "Core Principles" section.

---

## Codex Integration Assessment

### Transport Architecture (tmux-codex.sh)

The transport works by:
1. Discovering the party session and Codex pane via `party-lib.sh`
2. Rendering a template with placeholders
3. Sending the message by typing into the Codex tmux pane via `tmux_send`
4. Codex processes and writes findings to a `.toon` file
5. Codex notifies Claude via `tmux-claude.sh` (reverse channel)
6. Claude reads findings and runs `--review-complete`

**Failure modes:**
- **Pane busy:** `tmux_send` is best-effort. If Codex is processing, the message is dropped. The script prints `CODEX_REVIEW_DROPPED` but this requires the caller to handle it.
- **Long messages:** Shell quoting issues with backticks, quotes, or >500 chars. The SKILL.md warns about this and suggests writing to a temp file first — a workaround, not a fix.
- **Tmux buffer limits:** Very long messages may be truncated by tmux's paste buffer.
- **No delivery confirmation:** Fire-and-forget. No way to know if Codex received the full message.
- **Session discovery:** Relies on `party-lib.sh` which reads party state files. If party state is stale, discovery fails.

**Could it be simpler?** Yes, but with tradeoffs:
- **Named pipes (FIFO):** Reliable delivery, no tmux dependency. But requires Codex to poll or use inotify.
- **Unix domain sockets:** Bidirectional, reliable. Requires a daemon or socket server.
- **Shared file + inotify:** Write prompt to file, Codex watches for changes. Simple but polling-based.
- **Direct API call:** Bypass tmux entirely, call Codex API directly. Loses the tmux visual observability.

The tmux approach's main advantage is **observability** — you can see what Codex is doing in real-time by watching the pane. This is high-value during development. The fragility is acceptable for a developer-local tool.

### TOON Format

TOON (Table-Oriented Object Notation) is used for Codex findings files. It's a compact representation of structured data. Based on `test-toon-format.sh` (158L), it has defined rules for serialization/deserialization.

The format is ad-hoc but internally consistent. It's used because:
1. It's more token-efficient than JSON/YAML for tabular data
2. It's human-readable in tmux panes
3. The `toon` CLI tool handles conversion

**Concern:** TOON is a custom format with a learning curve. JSON with `jq` would be universally understood. The token savings (~25-50% per the json.md rule) may not justify the cognitive overhead for a findings file that's typically <100 lines.

---

## Vibe Code Debt Inventory

### TODO/FIXME/HACK Comments

**None found.** Full grep of all tracked files returned zero TODO, FIXME, HACK, XXX, TEMP, or TEMPORARY comments. The codebase is clean.

### Dead Code & Transition Artifacts

1. **`session-cleanup.sh` line 15:** `find /tmp -maxdepth 1 -name "claude-*" -not -name "claude-evidence-*" -mtime +1 -delete` — Comment says "Keep old marker cleanup for transition period." The marker-based system was replaced by JSONL evidence months ago. This line cleans up artifacts that no longer exist.

2. **`tmux-codex.sh --approve` mode (lines 173-178):** Deliberately kept as an error message. Dead code in the sense that codex-gate.sh blocks it at the hook level, but serves as defense-in-depth. Acceptable.

3. **`tmux-codex.sh` backward-compat for 4th positional arg as dispute file** (line 65-67) — old calling convention preserved. Should be removed in favor of `--dispute` flag only.

4. **`codex-transport/references/prompt-templates.md`:** Exists alongside `templates/` directory. Potentially orphaned reference doc.

### Stale Task Metadata

- **`claude/tasks/24a915d2-*/`:** 4 pending task JSON files from Feb 2025 describing work that has already been completed (create codex-trace.sh, delete wizard.md, etc.). The task metadata was never marked complete.

### Orphaned / Untracked Files

1. **`docs/projects/phase-simplification/`:** Untracked directory containing PLAN.md and 4 TASK files for the recently completed phase simplification (PR #58). Should be committed as project documentation or removed.

2. **`.claude/` directory:** Untracked. Contains runtime state (symlinks to tracked skills/hooks, session artifacts, logs). Expected to be untracked.

### Session Artifacts (Disk Space)

| Artifact | Size | Location | Action |
|----------|------|----------|--------|
| Claude shell snapshots | ~7 MB | `claude/shell-snapshots/` | Prune >30 days |
| Codex shell snapshots | ~2.9 MB | `codex/shell_snapshots/` | Prune >60 days |
| Project session history | ~1.2 GB | `claude/projects/` | Archive old sessions |
| Hook error log | ~1 KB | `claude/logs/hook-errors.log` | Clear (all entries from Feb 26 testing) |
| Empty debug logs | 0 KB | `claude/logs/hook-debug-*.log` | Delete stubs |
| Settings backups | ~225 KB | `claude/backups/.claude.json.backup.*` | Auto-rotate |

### Git Log: No "Quick Fix" or "Temporary" Commits

No commits matching "quick fix", "temporary", "workaround", or "hack" were found in git history. Commit hygiene is clean.

---

## Consolidation Opportunities (Ranked by Value)

### 1. Extract Oscillation Detection from agent-trace-stop.sh [HIGH VALUE]

**Current:** 68 lines of oscillation logic embedded in agent-trace-stop.sh
**Proposed:** Move to `lib/oscillation.sh` sourced by agent-trace-stop.sh
**Benefit:** agent-trace-stop.sh drops from 188L to ~120L. Oscillation logic becomes independently testable. The cross-hash fingerprinting is complex enough to warrant its own module.
**Risk:** Low — pure extraction, no behavior change.

### 2. Merge general.md into CLAUDE.md [LOW EFFORT, LOW RISK]

**Current:** 4-line file with two rules (early returns, minimal comments)
**Proposed:** Add to CLAUDE.md "Core Principles" section
**Benefit:** One fewer file to load. Marginal.
**Risk:** None.

### 3. Unify task-workflow and bugfix-workflow [MEDIUM VALUE, MEDIUM RISK]

**Current:** Two skills, bugfix is a 64-line "delta" document referencing task-workflow
**Proposed:** Single `workflow` skill with `--mode task|bugfix` parameter
**Benefit:** Single source of truth. No risk of delta document drifting from base.
**Tradeoff:** Skill trigger routing becomes harder — "bug" vs "task" is currently clean skill-level routing. A unified skill would need internal mode detection.
**Recommendation:** Keep separate. The trigger routing value outweighs the maintenance cost. bugfix-workflow at 64 lines is cheap.

### 4. Remove session-cleanup.sh Marker Cleanup [LOW EFFORT]

**Current:** Line 15 cleans up old marker files that no longer exist
**Proposed:** Remove the line, keep only JSONL/lock cleanup
**Benefit:** Removes transition-period code that's been superseded.
**Risk:** None — markers haven't been created since evidence system v3.

### 5. Simplify evidence.sh Stale Diagnostics [MEDIUM VALUE]

**Current:** `check_all_evidence()` has a 35-line diagnostic block that checks for stale vs missing evidence
**Proposed:** Simplify to "evidence missing at current hash" without the stale-hash hint
**Tradeoff:** Loses the helpful "exists at stale hash — re-run to refresh" message
**Recommendation:** Keep the diagnostics. They save user time when evidence is stale after a rebase.

### 6. Replace TOON with JSON for Codex Findings [DEBATABLE]

**Current:** Custom TOON format for structured findings
**Proposed:** JSON with jq for parsing
**Benefit:** Universal tooling, no learning curve
**Tradeoff:** Higher token cost (~25-50% more), less readable in tmux
**Recommendation:** Keep TOON for now. The token savings matter at scale. Consider JSON if TOON causes Codex formatting errors.

---

## Recommendations (Concrete, Actionable)

### Immediate (This Week)

1. **Extract oscillation detection** from agent-trace-stop.sh into lib/oscillation.sh
2. **Remove marker cleanup** from session-cleanup.sh (line 15)
3. **Commit or remove** docs/projects/phase-simplification/ (untracked)
4. **Add worktree-guard.sh tests** — it's the 3rd largest hook with no test file

### Short-Term (Next Sprint)

5. **Merge general.md** into CLAUDE.md
6. **Verify codex-transport/references/prompt-templates.md** is referenced; remove if orphaned
7. **Add delivery confirmation** to tmux transport — have Codex echo back a received-ACK sentinel
8. **Remove backward-compat** 4th positional arg in tmux-codex.sh --review (line 65-67)

### Medium-Term (Next Quarter)

9. **Consider branch-scoped evidence naming** — `/tmp/claude-evidence-{repo}-{branch}.jsonl` would survive session restarts while maintaining isolation
10. **Evaluate named-pipe transport** as tmux-codex.sh alternative for reliability
11. **Create a hook/skill documentation site** — the system is complex enough that a structured reference would help onboarding

### Do Not Do

- **Do NOT merge task-workflow and bugfix-workflow** — trigger routing is more valuable than DRY
- **Do NOT replace TOON with JSON** — token savings matter at scale
- **Do NOT further simplify execution-core.md** — it's right-sized post-phase-simplification
- **Do NOT make evidence repo+branch-scoped** — session ≈ branch in worktree model, added complexity not worth it

---

## Appendix: System Architecture Summary

```
                     ┌─────────────────┐
                     │   CLAUDE.md     │ ← Paladin identity + core principles
                     │   (global)      │
                     └────────┬────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────▼───────┐ ┌────▼────┐  ┌───────▼────────┐
     │  Rules (7)      │ │ Skills  │  │   Hooks (13)   │
     │  execution-core │ │  (14)   │  │  evidence.sh   │
     │  go/py/ts/react │ │         │  │  session-id    │
     │  json, general  │ │         │  │  agent-trace   │
     └────────────────┘ └────┬────┘  └───────┬────────┘
                              │               │
                    ┌─────────┼─────────┐     │
                    │         │         │     │
              ┌─────▼──┐ ┌───▼───┐ ┌───▼─────▼──┐
              │Workflow │ │Review │ │  Evidence   │
              │  Skills │ │Skills │ │   System    │
              │task/bug │ │code-  │ │ JSONL+hash  │
              │quick-fix│ │review │ │ /tmp/       │
              └────┬────┘ │write- │ └──────┬─────┘
                   │      │tests  │        │
                   │      └───────┘   ┌────▼────┐
                   │                  │ PR Gate │
                   └──────────────────► (final  │
                   via evidence       │  check) │
                                      └─────────┘

              ┌──────────────────────────────────┐
              │        Codex Transport           │
              │  tmux-codex.sh → tmux pane       │
              │  tmux-claude.sh ← notification   │
              │  .toon findings files            │
              └──────────────────────────────────┘
```

---

*Codex deep analysis pending — will be appended when the Wizard completes.*
