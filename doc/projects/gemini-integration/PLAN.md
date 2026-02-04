# Gemini Integration Implementation Plan

> **Goal:** Add a Gemini-powered agent for large-scale log analysis and web research synthesis.
>
> **Architecture:** Single CLI-based agent using existing Gemini CLI (already installed and authenticated). Two modes: log analysis (gemini-2.5-pro) and web search (gemini-2.0-flash).
>
> **Tech Stack:** Gemini CLI, WebSearch/WebFetch tools
>
> **Specification:** [SPEC.md](./SPEC.md) | **Design:** [DESIGN.md](./DESIGN.md)

## Task Overview

| Task | Description | Dependencies |
|------|-------------|--------------|
| TASK0 | Gemini CLI configuration | None |
| TASK1 | gemini agent definition | TASK0 |
| TASK2 | skill-eval.sh integration | TASK1 |
| TASK3 | Documentation updates | TASK1 |

## Dependency Graph

```
TASK0 (CLI config)
  │
  └──► TASK1 (gemini agent)
            │
            ├──► TASK2 (skill-eval.sh)
            │
            └──► TASK3 (documentation)
```

## Task Details

### TASK0: Gemini CLI Configuration
- [ ] Verify CLI is installed and authenticated
- [ ] Create `gemini/AGENTS.md` instructions

**Deliverables:** Verified CLI + agent instructions

### TASK1: gemini Agent
- [ ] Create `claude/agents/gemini.md`
- [ ] Implement mode detection (log analysis vs web search)
- [ ] Implement size estimation logic for logs
- [ ] Add fallback to standard log-analyzer for small logs
- [ ] Test with large log files and web queries

**Deliverables:** Single agent handling both log analysis and web search

### TASK2: skill-eval.sh Integration
- [ ] Add web search trigger patterns
- [ ] Test auto-suggestion behavior
- [ ] Ensure no conflicts with existing patterns

**Deliverables:** Auto-suggestion for research queries

### TASK3: Documentation Updates
- [ ] Update `claude/agents/README.md` with new agent
- [ ] Update `claude/CLAUDE.md` sub-agents table

**Deliverables:** Complete documentation for new capability

## Implementation Notes

### Gemini CLI Usage Pattern

The Gemini CLI is already installed at `/Users/aleksituominen/.nvm/versions/node/v24.12.0/bin/gemini`:

| Codex CLI | Gemini CLI |
|-----------|------------|
| `codex exec -s read-only "..."` | `gemini --approval-mode plan -p "..."` |
| Model selection | `gemini -m gemini-2.0-flash -p "..."` |
| Large input | `cat logs \| gemini -p "Analyze..."` |

### Testing Strategy

| Mode | Test Approach |
|------|---------------|
| Log analysis | Generate large synthetic log, verify analysis |
| Web search | Query with known answer, verify synthesis quality |

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Gemini CLI rate limits | CLI handles retry internally |
| Context overflow | Truncate with clear warning |

## Future Iterations

### gemini-ui-debugger (Deferred)

Multimodal UI debugging requires Gemini API (curl + base64) rather than CLI. Will be implemented separately when:
- Need arises for screenshot-to-Figma comparison
- Gemini CLI adds native image support via extensions
