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
- [x] Verify CLI is installed and authenticated
- [x] Verify GEMINI.md auto-discovery (project directory)
- [x] Create `gemini/GEMINI.md` with instructions
- [x] Test `-p`, `-m`, and `--approval-mode plan` flags
- [x] Verify `.gitignore` excludes credentials

**Deliverables:** `gemini/GEMINI.md` with agent instructions

**Note:** GEMINI.md is auto-discovered from project directory (verified). Skills require explicit installation and are not used for this integration.

### TASK1: gemini Agent
- [x] Create `claude/agents/gemini.md`
- [x] Implement mode detection (log analysis vs web search)
- [x] Implement size estimation logic for logs
- [x] Smart model selection: flash for small logs, pro for large logs
- [x] Test with both small and large log files, and web queries

**Deliverables:** Single agent handling ALL log analysis and web search (replaces log-analyzer)

### TASK2: skill-eval.sh Integration
- [x] Add web search trigger patterns
- [x] Test auto-suggestion behavior
- [x] Ensure no conflicts with existing patterns

**Deliverables:** Auto-suggestion for research queries

### TASK3: Documentation Updates
- [x] Update `claude/agents/README.md` with new agent
- [x] Update `claude/CLAUDE.md` sub-agents table
- [x] Mark log-analyzer as deprecated in all docs
- [x] Add deprecation notice to `claude/agents/log-analyzer.md`

**Deliverables:** Complete documentation for new capability + log-analyzer deprecation

## Implementation Notes

### Key Thresholds

**Token Estimation Formula:**
```bash
bytes=$(wc -c < "$LOG_FILE")
estimated_tokens=$((bytes / 4))
```

| Metric | Value | Rationale |
|--------|-------|-----------|
| Model switch threshold | 500K tokens (~2MB) | Below: use flash (faster). Above: use pro (large context) |
| Warning threshold | 1.6M tokens (~6.4MB) | Approaching Gemini's 2M limit |

### Gemini CLI Resolution

3-tier fallback chain:
1. `GEMINI_PATH` environment variable (if set)
2. `command -v gemini` (system PATH)
3. `$(npm root -g)/@google/gemini-cli/bin/gemini` (absolute fallback)

### Gemini CLI Usage Pattern

| Codex CLI | Gemini CLI |
|-----------|------------|
| `codex exec -s read-only "..."` | `gemini --approval-mode plan -p "..."` |
| Model selection | `gemini -m gemini-2.0-flash -p "..."` |
| Large input | `cat logs \| gemini -p "Analyze..."` |

### Testing Strategy

| Mode | Test Approach |
|------|---------------|
| Log analysis | Generate large synthetic log (>500K tokens), verify analysis |
| Web search | Query with known answer, verify synthesis quality |

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Gemini CLI rate limits | CLI handles retry internally (verify during implementation) |
| Context overflow (>1.6M tokens) | Time-range filtering if timestamps present, else sequential chunking |
| Mode ambiguity | Explicit `mode:log`/`mode:web` override, else keyword heuristics |

## Future Iterations

### gemini-ui-debugger (Deferred)

Multimodal UI debugging requires Gemini API (curl + base64) rather than CLI. Will be implemented separately when:
- Need arises for screenshot-to-Figma comparison
- Gemini CLI adds native image support via extensions
