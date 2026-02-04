# Gemini Integration Specification

## Overview

Integrate Google Gemini into the autonomous workflow as a complementary model for tasks that benefit from its unique capabilities: massive context windows (2M tokens) and fast inference.

## Goals

1. **Leverage Gemini's 2M token context** for log analysis that exceeds other models' limits
2. **Add research capability** via web search synthesis using Gemini Flash

## Non-Goals

- Replacing existing agents (Codex, code-critic, etc.)
- Using Gemini for code review or implementation tasks
- Creating a general-purpose Gemini wrapper
- Multimodal UI debugging (deferred to future iteration)

## Agent

### gemini

**Purpose:** Single CLI-based agent that leverages Gemini for tasks requiring large context or fast synthesis.

**Modes:**

| Mode | Trigger | Model | Use Case |
|------|---------|-------|----------|
| log-analysis | Log size > 100K tokens | gemini-2.5-pro | Massive log files |
| web-search | Research queries (auto-suggested) | gemini-2.0-flash | Fast synthesis |

**Capabilities:**

1. **Log Analysis Mode:**
   - Ingest logs up to 2M tokens (~8MB of text)
   - All existing log-analyzer capabilities (format detection, aggregation, patterns)
   - Cross-reference logs from multiple sources simultaneously
   - Falls back to standard log-analyzer for small logs

2. **Web Search Mode:**
   - Perform web searches via WebSearch tool
   - Synthesize multiple search results into coherent answer
   - Cite sources with URLs
   - Identify when information is outdated or conflicting

**Output:**
- Log analysis: Same format as current log-analyzer (`~/.claude/logs/{identifier}.md`)
- Web search: Structured research findings with sources

## Technical Requirements

### Gemini CLI

Use the existing Gemini CLI (already installed and authenticated):
- Located at `/Users/aleksituominen/.nvm/versions/node/v24.12.0/bin/gemini`
- OAuth credentials in `gemini/` directory
- Add `gemini/AGENTS.md` for agent instructions

### CLI Usage

```bash
# Non-interactive query
gemini -p "prompt"

# Model selection
gemini -m gemini-2.0-flash -p "prompt"   # Fast synthesis
gemini -m gemini-2.5-pro -p "prompt"     # Deep analysis

# Read-only mode
gemini --approval-mode plan -p "prompt"

# Large input via stdin
cat large.log | gemini -p "Analyze these logs..."
```

### Integration Points

| Integration | Purpose |
|-------------|---------|
| WebSearch tool | Web research for synthesis |
| skill-eval.sh | Auto-suggest for research queries |
| agent-trace.sh | Marker creation (if needed) |

## Acceptance Criteria

1. **Log Analysis:**
   - [ ] Successfully analyzes logs > 500K tokens
   - [ ] Produces same output format as current log-analyzer
   - [ ] Falls back to standard log-analyzer for small logs

2. **Web Search:**
   - [ ] Auto-suggested by skill-eval.sh for research queries
   - [ ] Synthesizes multiple search results
   - [ ] Cites sources with URLs
   - [ ] Returns structured findings

3. **Infrastructure:**
   - [ ] Existing Gemini CLI verified working
   - [ ] `gemini/AGENTS.md` created with agent instructions
   - [ ] Agent definition at `claude/agents/gemini.md`

## Future Iterations

### gemini-ui-debugger (Deferred)

Multimodal UI debugging requires Gemini API (curl + base64) rather than CLI. Deferred to separate implementation when:
- Need arises for screenshot-to-Figma comparison
- Gemini CLI adds native image support via extensions
