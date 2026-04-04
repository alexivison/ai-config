---
name: codex-transport
description: >-
  Transport layer for communicating with Codex CLI via tmux. Provides modes for
  code review (review), plan review (plan-review), ad-hoc tasks (prompt),
  review evidence (review-complete), and escalation (needs-discussion).
  Wizard approval flows through the findings file verdict — workers cannot
  self-approve. Use whenever dispatching work to The Wizard, recording review
  evidence, or signaling escalation.
user-invocable: false
---

# codex-transport — Communicate with The Wizard via tmux

## When to contact The Wizard

- **For code review**: After implementing changes and passing sub-agent critics, request Wizard review
- **For tasks**: When you need The Wizard to investigate or work on something in parallel
- **For verdict**: After triaging The Wizard's findings, signal your decision

## How to contact The Wizard

Use the party-cli transport subcommand:
```bash
party-cli transport <mode> [args...]
```

## Modes

### Request code review (non-blocking)
After implementing changes and passing sub-agent critics:
```bash
party-cli transport review <work_dir> [base_branch] ["PR title"] [flags...]
```
`work_dir` is **REQUIRED** — the absolute path to the worktree or repo where changes live. `base_branch` defaults to `main`, `PR title` defaults to `Code review`.

**Optional flags** (can appear anywhere after `review`):
- `--scope "description"` — scope boundaries for the review. Codex omits out-of-scope findings.
- `--dispute /path/to/context.md` — dismissed findings with rationales for re-reviews (see Dispute Resolution below).
- `--prior-findings /path/to/prior.toon` — prior findings file for re-reviews. Codex focuses on whether blocking issues were addressed.

The review prompt is rendered from `templates/review.md`. Conditional sections activate only when the corresponding flag is passed.

This sends a message to The Wizard's pane. You are NOT blocked — continue with non-edit work while The Wizard reviews. The Wizard will notify you via `[CODEX] Review complete. Findings at: <path>` when done. Findings are raw TOON (`.toon` file, no markdown fences). Handle that message per your `tmux-handler` skill.

### Request plan review (non-blocking)
After creating a plan:
```bash
party-cli transport plan-review "<plan_path>" <work_dir>
```
`work_dir` is **REQUIRED**. Plan review is advisory — it is ungated and does not create any evidence. The Wizard will notify via `[CODEX] Plan review complete. Findings at: <path>` when done. Findings are raw TOON (`.toon` file, no markdown fences).

### Send a task (non-blocking)
**IMPORTANT:** Prompts with quotes, backticks, or >500 characters risk shell errors when passed inline. Write to a temp file first:
```bash
cat > /tmp/codex-prompt.md << 'EOF'
Your long prompt here...
EOF
party-cli transport prompt "$(cat /tmp/codex-prompt.md)" /path/to/repo
```

Short prompts can be passed directly:
```bash
party-cli transport prompt "<task description>" <work_dir>
```
`work_dir` is **REQUIRED**. Returns immediately. The Wizard will notify via `[CODEX] Task complete. Response at: <path>` when done. The response path uses `.toon` by convention. If you requested structured findings, expect canonical TOON; if you asked for narrative analysis, plain text is acceptable unless you explicitly required TOON.

### Record review completion and verdict
**CRITICAL:** The argument is the **full path to the `.toon` findings file** from the `[CODEX] Review complete. Findings at: <path>` notification — NOT a worktree path. Passing a worktree path will fail with "Findings file not found."

```bash
party-cli transport review-complete "<findings_file>"
```

This reads the findings file and extracts the verdict The Wizard wrote:
- If findings contain `VERDICT: APPROVED` → creates `codex` APPROVED evidence directly
- If findings contain `VERDICT: REQUEST_CHANGES` → no evidence created
- If no verdict line found → no evidence created (warning emitted)

**You CANNOT call `approve` directly.** The gate hard-blocks it. Approval can only come from The Wizard via the verdict line in the findings file. This prevents workers from self-approving their own fixes.

### Triage override (out-of-scope critic findings)
When critics flag out-of-scope code (e.g., from rebase), you can override with a rationale:
```bash
party-cli transport triage-override <type> "rationale"
# Example:
party-cli transport triage-override minimizer "Out-of-scope: auth files from PR #65315 landed via rebase, not our changes"
```

Only critic types (`code-critic`, `minimizer`) can be overridden — codex and PR gates cannot. The override is recorded with a rationale in the evidence log for audit trail. Use sparingly and only for genuinely out-of-scope findings.

### Signal escalation
```bash
# Genuine mutual escalation (circular discussion, security-critical dispute, or both agents agree human input is needed)
party-cli transport needs-discussion "reason"
```

**Blocking findings?** Fix the code, re-run critics, then dispatch a new `review`. Editing code invalidates all evidence (diff_hash changes), so the full cascade re-runs naturally. There is no shortcut — the gates enforce it.

### Dispute resolution
For out-of-scope Codex findings or NEEDS_DISCUSSION, see [execution-core.md § Dispute Resolution](~/.claude/rules/execution-core.md#dispute-resolution). The `review` mode accepts an optional `--dispute <file>` flag for this flow.

## Important

- `review`, `plan-review`, and `prompt` are NON-BLOCKING. Continue working while The Wizard processes.
- `review-complete` emits `CODEX_REVIEW_RAN` only after findings exist.
- `needs-discussion` is instant — outputs a sentinel for hook detection.
- **You cannot self-approve.** The Wizard decides the verdict via the `VERDICT:` line in the findings file.
- Workflow skills enforce running critics before `review`. The hook only blocks `approve`.
- `plan-review` is ungated — no evidence required or affected.
- **Blocking Wizard findings:** fix code → commit → re-run critics → new `review` → `review-complete`.
