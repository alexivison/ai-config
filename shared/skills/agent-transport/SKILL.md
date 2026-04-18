---
name: agent-transport
description: >-
  Shared tmux transport for cross-agent coordination. Use the role-based
  scripts `tmux-companion.sh` and `tmux-primary.sh` from the shared
  `agent-transport` skill.
user-invocable: false
---

# agent-transport — Coordinate Across Roles via tmux

Use the shared role-based transport scripts:

- `tmux-companion.sh` when sending work to the companion
- `tmux-primary.sh` when sending a reply or completion notice to the primary

Older sessions may still emit `[CLAUDE]` / `[CODEX]` prefixes; the transport continues to recognize those prefixes alongside `[PRIMARY]` / `[COMPANION]`.

## Primary Role

Use `~/.claude/skills/agent-transport/scripts/tmux-companion.sh <mode> [args...]`.

### When to dispatch

**MANDATORY — always dispatch, no exceptions:**
- Plan created → `--plan-review`
- Critics pass on code changes → `--review`
- Stuck on a bug after 2 failed attempts → `--prompt` to investigate

**PROACTIVE — dispatch without being asked:**
- Architecture decision with 2+ viable approaches → `--prompt` for tradeoff analysis
- Unfamiliar code area before major changes → `--prompt` to explain the area
- Complex refactor spanning 3+ files → `--review` for early sanity check

### Common uses

- Request a review after critics pass
- Request a plan review after creating a plan
- Send an investigation or delegated task to the companion
- Record review completion with `--review-complete`
- Signal escalation with `--needs-discussion`

## Modes

### Request code review (non-blocking)
After implementing changes and passing sub-agent critics:
```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --review <work_dir> [base_branch] ["PR title"] [flags...]
```
`work_dir` is **REQUIRED** — the absolute path to the worktree or repo where changes live. `base_branch` defaults to `main`, `PR title` defaults to `Code review`.

**Optional flags** (can appear anywhere after `--review`):
- `--scope "description"` — scope boundaries for the review. The companion omits out-of-scope findings.
- `--dispute /path/to/context.md` — dismissed findings with rationales for re-reviews (see Dispute Resolution below).
- `--prior-findings /path/to/prior.toon` — prior findings file for re-reviews. The companion focuses on whether blocking issues were addressed.

The review prompt is rendered from `templates/review.md`. Conditional sections activate only when the corresponding flag is passed.

This sends a message to the companion pane. You are NOT blocked — continue with non-edit work while the companion reviews. New sessions notify via `[COMPANION] Review complete. Findings at: <path>`; legacy sessions still use `[CODEX]`. Findings are raw TOON (`.toon` file, no markdown fences). Handle either prefix per your `tmux-handler` skill.

### Request plan review (non-blocking)
After creating a plan:
```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --plan-review "<plan_path>" <work_dir>
```
`work_dir` is **REQUIRED**. Plan review is advisory — it is ungated and does not create any evidence. The companion notifies via `[COMPANION] Plan review complete. Findings at: <path>` in new sessions and `[CODEX] ...` in legacy sessions. Findings are raw TOON (`.toon` file, no markdown fences).

### Send a task (non-blocking)
**IMPORTANT:** Prompts with quotes, backticks, or >500 characters risk `unmatched '` shell errors when passed inline. Write to a temp file first:
```bash
cat > /tmp/companion-prompt.md << 'EOF'
Your long prompt here...
EOF
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --prompt "$(cat /tmp/companion-prompt.md)" /path/to/repo
```

Short prompts can be passed directly:
```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --prompt "<task description>" <work_dir>
```
`work_dir` is **REQUIRED**. Returns immediately. The companion notifies via `[COMPANION] Task complete. Response at: <path>` in new sessions and `[CODEX] ...` in legacy sessions. The response path uses `.toon` by convention. If you requested structured findings, expect canonical TOON; if you asked for narrative analysis, plain text is acceptable unless you explicitly required TOON.
Do not poll the response file while waiting. The tmux completion notice is the success signal; read the file only after that notice arrives. Legacy `Response ready at:` notices remain accepted if an older session emits one.

### Record review completion and verdict
**CRITICAL:** The argument is the **full path to the `.toon` findings file** from the `[COMPANION] Review complete. Findings at: <path>` notification (or legacy `[CODEX]`) — NOT a worktree path. Passing a worktree path will fail with "Findings file not found."

```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --review-complete "<findings_file>"
```

This reads the findings file and extracts the verdict the companion wrote:
- If findings contain `VERDICT: APPROVED` → creates the default companion APPROVED evidence (`codex`) directly
- If findings contain `VERDICT: REQUEST_CHANGES` → no evidence created
- If no verdict line found → no evidence created (warning emitted)

**You CANNOT call `--approve` directly.** The gate hard-blocks it. Approval can only come from the companion via the verdict line in the findings file. This prevents workers from self-approving their own fixes.

### Triage override (out-of-scope critic findings)
When critics flag out-of-scope code (e.g., from rebase), you can override with a rationale:
```bash
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --triage-override <type> "rationale"
# Example:
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --triage-override minimizer "Out-of-scope: auth files from PR #65315 landed via rebase, not our changes"
```

Only critic types (`code-critic`, `minimizer`) can be overridden — codex and PR gates cannot. The override is recorded with a rationale in the evidence log for audit trail. Use sparingly and only for genuinely out-of-scope findings.

### Signal escalation
```bash
# Genuine mutual escalation (circular discussion, security-critical dispute, or both agents agree human input is needed)
~/.claude/skills/agent-transport/scripts/tmux-companion.sh --needs-discussion "reason"
```

**Blocking findings?** Fix the code, re-run critics, then dispatch a new `--review`. Editing code invalidates all evidence (diff_hash changes), so the full cascade re-runs naturally. There is no shortcut — the gates enforce it.

### Dispute resolution
See execution-core.md § Dispute Resolution. `--review` accepts `--dispute <file>` for re-reviews with dismissed findings.

## Companion Role

Use `~/.codex/skills/agent-transport/scripts/tmux-primary.sh "<message>"` to notify or question the primary agent. This covers:

- `Review complete. Findings at: <findings_file>`
- `Plan review complete. Findings at: <findings_file>`
- `Task complete. Response at: <response_file>`
- `Question: <text>. Write response to: <response_file>`

When a file path is part of the message, wait for the tmux completion notice before reading the file. Legacy `Response ready at:` notices remain accepted.

## TOON Helper

Use the shared helper at `~/.claude/skills/agent-transport/scripts/toon-transport.sh` (or the matching `~/.codex/...` path). It supports:

- `encode-findings <input.json> <output.toon>`
- `decode <input.toon> [output.json]`
- `validate-findings <input.toon|input.json>`

## Important

- `--review`, `--plan-review`, `--prompt` are NON-BLOCKING.
- `--review-complete` emits the transport sentinel `COMPANION_REVIEW_RAN` after findings exist.
- **Self-approval blocked.** Verdict comes from the companion's `VERDICT:` line in the findings file.
- Workflow skills enforce critics before `--review`. Hook only blocks `--approve`.
- **Blocking findings:** fix → commit → critics → `--review` → `--review-complete`.
