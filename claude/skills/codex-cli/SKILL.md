---
name: codex-cli
description: Procedural CLI invocation details for the Codex agent
user-invocable: false
---

# Codex CLI Procedures

## Safety

Always `-s read-only`. Never write permissions.

## Task Types

| Task | Command |
|------|---------|
| Code review | `codex exec -s read-only "Review changes for bugs, security, maintainability"` |
| Architecture | `codex exec -s read-only "Analyze architecture for patterns and complexity"` |
| Plan review | `codex exec -s read-only "Review plan for: {checklist}"` |
| Design decision | `codex exec -s read-only "Compare approaches: {options}"` |
| Debugging | `codex exec -s read-only "Analyze error: {description}"` |

## Plan Review Checklist

Include in plan review prompts:
- Data flow: ALL transformation points mapped? Fields in ALL converters?
- Standards: Existing patterns referenced? Naming consistent?
- Cross-task: Scope boundaries explicit? Combined coverage complete?
- Bug prevention: Silent field drops? All code paths covered?

## Execution

1. Gather context — read domain rules from `claude/rules/` or `.claude/rules/`
2. Invoke synchronously: `codex exec -s read-only "..."` with `timeout: 300000`
3. Parse output, extract verdict
4. If accidental background execution: use TaskStop to clean up
5. Return structured result

**NEVER** use `run_in_background: true`. Always synchronous.

## Output Format

```markdown
## Codex Analysis

**Task:** {type}
**Scope:** {files/topic}

### Findings
{With file:line references}

### Verdict
**APPROVE** — CODEX APPROVED | **REQUEST_CHANGES** | **NEEDS_DISCUSSION**
{Reason}
```

## Iteration

On iteration 2+: verify previous issues addressed, check for new issues. After 3 without resolution → NEEDS_DISCUSSION.
