---
name: codex-cli
description: Procedural CLI invocation details for the Codex agent
user-invocable: false
---

# Codex CLI Procedures

## Safety

- `codex review`: inherently read-only, no sandbox flag needed.
- `codex exec`: always `-s read-only`. Never write permissions.

## Task Types

### Code Review (use `codex review`)

```bash
codex review --base main --title "{PR title or change summary}"
```

- `--base main` diffs the current branch against `main` (uses merge-base).
- `--title` gives GPT-5.3 context about the intent of the changes.
- **No custom prompt** — GPT-5.3 uses its own built-in review logic at `xhigh` reasoning. This is intentional: it eliminates prompt-direction loss through the Haiku relay.
- Output: prioritized, actionable findings on stdout.

### Non-Review Tasks (use `codex exec`)

Use structured, slot-filled prompts. Never relay vague natural-language descriptions.

| Task | Command |
|------|---------|
| Architecture | `codex exec -s read-only "TASK: Architecture analysis. SCOPE: {files/modules}. EVALUATE: 1) Pattern consistency 2) Coupling/cohesion 3) Complexity hotspots. OUTPUT: Findings with file:line refs, then verdict."` |
| Plan review | `codex exec -s read-only "TASK: Plan review. PLAN: {summary}. CHECKLIST: 1) Data flow — all transformation points mapped, fields in all converters? 2) Standards — existing patterns referenced, naming consistent? 3) Cross-task — scope boundaries explicit, combined coverage complete? 4) Bug prevention — silent field drops, all code paths covered? OUTPUT: Pass/fail per checklist item, then verdict."` |
| Design decision | `codex exec -s read-only "TASK: Design comparison. OPTIONS: A) {option_a} B) {option_b}. CRITERIA: 1) Complexity 2) Maintainability 3) Performance 4) Risk. OUTPUT: Pros/cons matrix, recommendation with rationale."` |
| Debugging | `codex exec -s read-only "TASK: Error analysis. ERROR: {error_message}. CONTEXT: {file:line, stack trace snippet}. ANALYZE: 1) Root cause 2) Contributing factors 3) Fix options. OUTPUT: Diagnosis with evidence, ranked fixes."` |

### Prompt Template Rules

- **Always use TASK/SCOPE/OUTPUT structure** — gives GPT-5.3 clear framing.
- **Fill all slots** before invocation — `{placeholders}` must be replaced with actual values.
- **Never paraphrase the user's request** as a bare sentence — always decompose into structured fields.
- **Keep prompts under 300 chars** — concise prompts reduce drift.

## Execution

### For `codex review`:
1. Gather context — determine base branch (usually `main`)
2. Invoke synchronously: `codex review --base main --title "..."` with `timeout: 300000`
3. Capture full stdout output
4. If accidental background execution: use TaskStop to clean up
5. Return using passthrough format (see Output Rules below)

### For `codex exec`:
1. Gather context — read domain rules from `claude/rules/` or `.claude/rules/`
2. Build prompt using structured template (TASK/SCOPE/OUTPUT)
3. Invoke synchronously: `codex exec -s read-only "..."` with `timeout: 300000`
4. Capture full stdout output
5. If accidental background execution: use TaskStop to clean up
6. Return using passthrough format (see Output Rules below)

**NEVER** use `run_in_background: true`. Always synchronous.

## Output Rules

**Pass through the full Codex output verbatim.** Do NOT summarize, reformat, or drop findings. The main agent needs the complete analysis from GPT-5.3 — any lossy summarization by this wrapper defeats the purpose.

Return format:

```markdown
## Codex Analysis

**Task:** {type}

### Full Output
{Paste the COMPLETE Codex CLI stdout here — every finding, every line, unchanged}

### Verdict
**APPROVE** — CODEX APPROVED | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
```

Rules:
- **NEVER summarize** Codex findings — include them all verbatim.
- **NEVER drop** file:line references, severity labels, or context from the raw output.
- **NEVER paraphrase** — if Codex said it, pass it through exactly.
- The only thing you add is the verdict line based on the overall findings.

## Iteration

On iteration 2+: verify previous issues addressed, check for new issues. After 3 without resolution → NEEDS_DISCUSSION.
