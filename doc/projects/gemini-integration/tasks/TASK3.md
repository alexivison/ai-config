# TASK3: Documentation Updates

**Issue:** gemini-integration-docs
**Depends on:** TASK1

## Objective

Update documentation to reflect the new gemini agent and deprecate log-analyzer.

## Required Context

Read these files first:
- `claude/agents/README.md` — Agent documentation
- `claude/CLAUDE.md` — Main configuration with sub-agents table
- `claude/agents/gemini.md` — New agent (from TASK1)
- `claude/agents/log-analyzer.md` — Agent to deprecate

## Files to Modify

| File | Action |
|------|--------|
| `claude/agents/README.md` | Modify (add gemini, mark log-analyzer deprecated) |
| `claude/CLAUDE.md` | Modify (update sub-agents table) |
| `claude/agents/log-analyzer.md` | Modify (add deprecation notice) |

## Implementation Details

### claude/agents/README.md

Add entry for gemini agent:

```markdown
### gemini

**Purpose:** Gemini-powered analysis for log analysis and web research synthesis.

**When to use:**
- ALL log analysis tasks (replaces log-analyzer)
- Research queries requiring web search and synthesis

**Modes:**
| Mode | Model | Trigger |
|------|-------|---------|
| Log analysis (small) | gemini-2.0-flash | Logs < 500K tokens |
| Log analysis (large) | gemini-2.5-pro | Logs >= 500K tokens |
| Web search | gemini-2.0-flash | Research queries |

**Note:** This agent replaces log-analyzer for all log analysis tasks.
```

Mark log-analyzer as deprecated:

```markdown
### log-analyzer (DEPRECATED)

> **DEPRECATED:** Use `gemini` agent instead. This agent will be removed in a future version.

**Purpose:** Analyze application logs for errors, patterns, and anomalies.
...
```

### claude/CLAUDE.md

Update the sub-agents table:

```markdown
| gemini | Log analysis, web search | All log analysis, research queries |
| ~~log-analyzer~~ | ~~Analyze logs~~ | DEPRECATED - use gemini |
```

### claude/agents/log-analyzer.md

Add deprecation notice at the top:

```markdown
---
name: log-analyzer
description: "DEPRECATED - Use gemini agent instead. Analyze logs for errors and patterns."
...
---

> **⚠️ DEPRECATED:** This agent is deprecated. Use the `gemini` agent for all log analysis tasks.
> The gemini agent provides the same capabilities with additional benefits:
> - 2M token context for massive log files
> - Smart model selection (Flash for small logs, Pro for large logs)
>
> This agent will be removed in a future version.

...
```

## Verification

```bash
# Check README.md updated
grep -q "gemini" claude/agents/README.md && echo "README updated"
grep -q "DEPRECATED" claude/agents/README.md && echo "Deprecation noted"

# Check CLAUDE.md updated
grep -q "gemini.*Log analysis" claude/CLAUDE.md && echo "CLAUDE.md updated"

# Check log-analyzer marked deprecated
grep -q "DEPRECATED" claude/agents/log-analyzer.md && echo "log-analyzer deprecated"
```

## Migration Path

When deprecating log-analyzer:

1. **Update references:**
   - `claude/agents/README.md` — Add deprecation notice to log-analyzer section
   - `claude/CLAUDE.md` — Strike through log-analyzer in sub-agents table
   - Any rules mentioning log-analyzer → update to reference gemini

2. **skill-eval.sh:**
   - Remove any auto-suggestions for log-analyzer (if present)
   - Ensure log analysis queries suggest gemini instead

3. **Timeline:**
   - log-analyzer remains functional but deprecated
   - Will be removed in a future version after gemini is stable

## Acceptance Criteria

- [ ] `claude/agents/README.md` updated with gemini agent documentation
- [ ] `claude/agents/README.md` marks log-analyzer as deprecated
- [ ] `claude/CLAUDE.md` sub-agents table includes gemini
- [ ] `claude/CLAUDE.md` sub-agents table marks log-analyzer as deprecated
- [ ] `claude/agents/log-analyzer.md` has deprecation notice at top
- [ ] Documentation explains both modes (log analysis, web search)
- [ ] No references to "fallback to log-analyzer"
- [ ] Migration path documented and followed
