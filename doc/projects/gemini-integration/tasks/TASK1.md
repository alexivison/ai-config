# TASK1: gemini Agent

**Issue:** gemini-integration-agent
**Depends on:** TASK0

## Objective

Create a single CLI-based Gemini agent that handles both large-scale log analysis and web search synthesis.

## Required Context

Read these files first:
- `claude/agents/log-analyzer.md` — Current log analyzer (inherit patterns)
- `claude/agents/codex.md` — Agent definition pattern
- `gemini/GEMINI.md` — Gemini instructions (from TASK0)
- Run `gemini --help` to understand CLI options

## Files to Create

| File | Action |
|------|--------|
| `claude/agents/gemini.md` | Create |

## Implementation Details

### claude/agents/gemini.md

**Frontmatter:**
```yaml
---
name: gemini
description: "Gemini-powered analysis agent. Uses 2M token context for large logs (gemini-2.5-pro), Flash model for web search synthesis (gemini-2.0-flash)."
model: haiku
tools: Bash, Glob, Grep, Read, Write, WebSearch, WebFetch
color: green
---
```

**Mode Detection Logic:**

```
1. Check for explicit mode override (case-insensitive):
   - "mode:log" or "mode:logs" → LOG ANALYSIS
   - "mode:web" or "mode:search" → WEB SEARCH

2. Keyword heuristics (if no explicit mode):

   LOG ANALYSIS triggers:
   - File path with log extension: *.log, *.jsonl, /var/log/*
   - Phrases: "analyze logs", "production logs", "error logs", "log file"
   - Pattern: path ending in .log + "analyze" or "investigate"
   - Regex: /\b(analyze|investigate|check)\s+(the\s+)?(logs?|\.log)\b/i

   WEB SEARCH triggers (require explicit external qualifier):
   - Phrases: "research online", "research the web", "research externally"
   - Phrases: "look up online", "look up externally", "search the web"
   - Phrases: "what is the latest version", "what is the current version"
   - Phrases: "what do experts say", "what do others say"
   - Phrases: "find external info", "find external documentation"
   - Regex: /\b(research|look up|search)\s+(online|the web|externally)\b/i

   IMPORTANT: Bare "research" alone does NOT trigger web search
   (avoids overlap with codebase research tasks).

3. LOG ANALYSIS MODE:
   a. Estimate log size using byte count (more accurate than line count):
      bytes=$(wc -c < "$LOG_FILE")
      estimated_tokens=$((bytes / 4))
   b. Routing (threshold: 500K tokens, ~2MB):
      - IF estimated_tokens < 500K → delegate to standard log-analyzer
      - IF estimated_tokens > 500K → use Gemini
      - IF estimated_tokens > 1.6M → warn about potential truncation
   c. Context overflow strategy:
      - Filter by time range if timestamps available
      - Or chunk into segments and analyze sequentially
   d. Gemini invocation (stdin for large content):
      GEMINI_CMD="${GEMINI_PATH:-$(command -v gemini || echo '$(npm root -g)/@google/gemini-cli/bin/gemini')}"
      cat /path/to/logs.log | "$GEMINI_CMD" --approval-mode plan -m gemini-2.5-pro -p "Analyze..."

4. WEB SEARCH MODE:
   a. Formulate search queries from user question
   b. Execute WebSearch tool for results
   c. Optionally WebFetch for full page content
   d. Synthesize with Gemini Flash:
      "$GEMINI_CMD" --approval-mode plan -m gemini-2.0-flash -p "Synthesize these search results..."
```

**CLI Path Resolution:**
```bash
# Robust CLI resolution with fallback
GEMINI_CMD="${GEMINI_PATH:-$(command -v gemini 2>/dev/null || echo '$(npm root -g)/@google/gemini-cli/bin/gemini')}"
if [[ ! -x "$GEMINI_CMD" ]]; then
  echo "Error: Gemini CLI not found. Install via: npm install -g @google/gemini-cli"
  exit 1
fi
```

**Log Analysis Invocation:**
```bash
# CORRECT: Pipe logs via stdin
cat /path/to/logs.log | gemini --approval-mode plan -m gemini-2.5-pro -p "Analyze these logs. Identify:
- Error patterns and frequencies
- Time-based clusters/spikes
- Correlations between error types
- Root cause hypotheses"

# WRONG: Never embed large content in argument (shell limit ~256KB)
# gemini -p "$(cat large.log)" ← DO NOT DO THIS
```

**Web Search Synthesis:**
```bash
# After gathering search results, synthesize with Flash
gemini --approval-mode plan -m gemini-2.0-flash -p "Based on these search results, provide a comprehensive answer to: {question}

Search Results:
{formatted_results}

Include:
- Direct answer to the question
- Key findings from multiple sources
- Source citations with URLs
- Any conflicting information noted"
```

**Output Formats:**

For log analysis (same as log-analyzer.md):
```markdown
## Log Analysis Report

**Source:** {log_path}
**Lines analyzed:** {count}
**Time range:** {start} to {end}

### Summary
{key findings}

### Error Patterns
| Pattern | Count | Severity |
|---------|-------|----------|
...

### Recommendations
- {actionable items}
```

For web search:
```markdown
## Research Findings

**Query:** {original_question}

### Answer
{synthesized answer}

### Key Points
- {bullet points}

### Sources
1. [{title}]({url}) - {brief description}
2. ...
```

## Verification

```bash
# Agent file exists and has correct frontmatter
grep -q "name: gemini" claude/agents/gemini.md

# Check for mode detection logic
grep -qE "LOG ANALYSIS|WEB SEARCH|log-analysis|web-search" claude/agents/gemini.md

# Check for correct CLI invocation pattern (stdin piping)
grep -qE "cat.*\| gemini" claude/agents/gemini.md

# Check for model selection
grep -q "gemini-2.5-pro" claude/agents/gemini.md
grep -q "gemini-2.0-flash" claude/agents/gemini.md
```

## Acceptance Criteria

- [ ] Agent definition created at `claude/agents/gemini.md`
- [ ] Mode detection:
  - [ ] Supports explicit mode override (`mode:log`, `mode:web`)
  - [ ] Falls back to keyword heuristics when no explicit mode
- [ ] Log analysis mode:
  - [ ] Size estimation uses byte count (`wc -c`) ÷ 4 for tokens
  - [ ] Threshold at 500K tokens (~2MB) for Gemini delegation
  - [ ] Falls back to standard log-analyzer for small logs
  - [ ] Warns if logs exceed 1.6M tokens (potential truncation)
  - [ ] Context overflow: time-range filtering or chunking strategy
  - [ ] Uses `cat logs | gemini -p` pattern (stdin piping)
  - [ ] Uses gemini-2.5-pro model
  - [ ] Uses `--approval-mode plan` for read-only
  - [ ] Output format matches existing log-analyzer
- [ ] CLI resolution:
  - [ ] Uses `GEMINI_PATH` env var if set
  - [ ] Falls back to `command -v gemini`
  - [ ] Falls back to `$(npm root -g)/@google/gemini-cli/bin/gemini`
- [ ] Web search mode:
  - [ ] Uses WebSearch tool for queries (agent has this tool)
  - [ ] Optionally uses WebFetch for full page content
  - [ ] Synthesizes results with gemini-2.0-flash model
  - [ ] Includes source citations with URLs
- [ ] Verification tests:
  - [ ] Log analysis: Test with file >2MB, verify Gemini invoked
  - [ ] Log analysis: Test with file <2MB, verify log-analyzer delegation
  - [ ] Web search: Test with explicit "search the web" query
  - [ ] CLI: Verify all three resolution paths work
