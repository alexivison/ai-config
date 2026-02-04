# TASK3: Documentation Updates

**Issue:** gemini-integration-docs
**Depends on:** TASK1

## Objective

Update documentation to reflect the new gemini agent.

## Required Context

Read these files first:
- `claude/agents/README.md` — Agent documentation
- `claude/CLAUDE.md` — Main configuration with sub-agents table
- `claude/agents/gemini.md` — New agent (from TASK1)

## Files to Modify

| File | Action |
|------|--------|
| `claude/agents/README.md` | Modify |
| `claude/CLAUDE.md` | Modify |

## Implementation Details

### claude/agents/README.md

Add entry for gemini agent in the appropriate section:

```markdown
### gemini

**Purpose:** Gemini-powered analysis for large-scale log analysis and web research synthesis.

**When to use:**
- Log files exceeding 100K tokens (uses Gemini's 2M context)
- Research queries requiring web search and synthesis

**Modes:**
| Mode | Model | Trigger |
|------|-------|---------|
| Log analysis | gemini-2.5-pro | Logs > 100K tokens |
| Web search | gemini-2.0-flash | Research queries |

**Note:** Falls back to standard log-analyzer for small logs.
```

### claude/CLAUDE.md

Add entry to the sub-agents table:

```markdown
| gemini | Large log analysis, web search | Logs > 100K tokens, research queries |
```

Place after existing analysis agents (e.g., log-analyzer).

## Verification

```bash
# Check README.md updated
grep -q "gemini" claude/agents/README.md && echo "README updated"

# Check CLAUDE.md updated
grep -q "gemini.*Large log" claude/CLAUDE.md && echo "CLAUDE.md updated"
```

## Acceptance Criteria

- [ ] `claude/agents/README.md` updated with gemini agent documentation
- [ ] `claude/CLAUDE.md` sub-agents table includes gemini
- [ ] Documentation explains both modes (log analysis, web search)
- [ ] Fallback behavior documented (standard log-analyzer for small logs)
