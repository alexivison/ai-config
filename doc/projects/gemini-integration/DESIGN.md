# Gemini Integration Design

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Claude Code (Orchestrator)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  skill-eval.sh ──auto-suggest──┐                                │
│                                │                                │
│  User request ─────────────────┼──► gemini agent                │
│                                │         │                      │
│                                │         ├──► Log analysis mode │
│                                │         │    (gemini-2.5-pro)  │
│                                │         │                      │
│                                └─────────┼──► Web search mode   │
│                                          │    (gemini-2.0-flash)│
│                                          ▼                      │
│                                    Gemini CLI                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Component Design

### 1. Gemini CLI Configuration (`gemini/`)

Use the existing Gemini CLI (already installed at `/Users/aleksituominen/.nvm/versions/node/v24.12.0/bin/gemini`).

**Existing Directory Structure:**
```
gemini/
├── oauth_creds.json     # OAuth credentials (existing)
├── settings.json        # Auth settings (existing)
├── google_accounts.json # Account info (existing)
└── AGENTS.md            # Instructions for Gemini (NEW)
```

**CLI Interface (existing commands):**
```bash
# Non-interactive query
gemini -p "Analyze these logs for error patterns..."

# Large input via stdin (pipe content before -p flag)
cat large.log | gemini -p "Analyze these logs..."

# Model selection
gemini -m gemini-2.0-flash -p "Quick synthesis..."
gemini -m gemini-2.5-pro -p "Deep analysis..."

# Read-only mode (no file modifications by Gemini)
gemini --approval-mode plan -p "Review this code..."
```

**Key Differences from Codex:**
| Codex CLI | Gemini CLI |
|-----------|------------|
| `codex exec -s read-only "..."` | `gemini --approval-mode plan -p "..."` |
| Inline prompt | `-p` flag for prompt |
| N/A | Native stdin support (pipe before command) |

### 2. Agent Definition (`claude/agents/gemini.md`)

```yaml
---
name: gemini
description: "Gemini-powered analysis agent. Uses 2M token context for large logs, Flash model for web search synthesis."
model: haiku
tools: Bash, Glob, Grep, Read, Write, WebSearch, WebFetch
color: green
---
```

**Mode Selection Logic:**

```
IF task involves log analysis:
  - Estimate log size (line count × avg line length)
  - IF < 100K tokens → delegate to standard log-analyzer
  - IF > 100K tokens → use gemini-2.5-pro via stdin

IF task involves web research:
  - Execute WebSearch tool
  - Optionally fetch pages via WebFetch
  - Synthesize with gemini-2.0-flash
```

### 3. skill-eval.sh Updates

Add auto-suggest pattern for web search:

```bash
# Web search triggers
elif echo "$PROMPT_LOWER" | grep -qE '\bresearch\b|\blook up\b|\bfind out\b|\bwhat is the (latest|current)\b|\bhow do (i|we|you)\b.*\b(in 2026|nowadays|currently)\b|\bsearch for\b'; then
  SUGGESTION="RECOMMENDED: Use gemini agent for research queries."
  PRIORITY="should"
```

## Data Flow

### Log Analysis Flow

```
User: "Analyze these production logs"
         │
         ▼
┌─────────────────────┐
│ Main Agent          │
│ - Estimate log size │
│ - > 100K tokens?    │
└─────────┬───────────┘
          │ Yes
          ▼
┌─────────────────────┐
│ gemini agent        │
│ - Read log files    │
│ - gemini -m pro -p  │
│ - Write findings    │
└─────────┬───────────┘
          │
          ▼
   Findings file + summary
```

### Web Search Flow

```
User: "What's the best practice for X in 2026?"
         │
         ▼
┌─────────────────────────┐
│ skill-eval.sh           │
│ "RECOMMENDED: gemini"   │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│ gemini agent            │
│ - WebSearch queries     │
│ - Optional WebFetch     │
│ - gemini -m flash -p    │
│ - Synthesize + cite     │
└─────────┬───────────────┘
          │
          ▼
   Research findings + sources
```

## Configuration

### gemini/AGENTS.md (NEW)

Instructions for Gemini when invoked by Claude Code agents:

```markdown
# Gemini — Specialized Analysis Agent

You are invoked by Claude Code for tasks requiring:
- Large context analysis (up to 2M tokens)
- Fast synthesis (Flash model)

## Output Format

Provide structured, actionable output. Include:
- Clear findings with specifics
- Severity/priority where applicable
- Actionable recommendations

## Boundaries

- Analysis and synthesis only
- No code generation unless specifically requested
- No file modifications
```

### Model Selection

| Use Case | Model | Flag |
|----------|-------|------|
| Log analysis | gemini-2.5-pro | `-m gemini-2.5-pro` |
| Web search synthesis | gemini-2.0-flash | `-m gemini-2.0-flash` |

## Error Handling

| Scenario | Handling |
|----------|----------|
| CLI not found | Error with install instructions |
| Auth expired | Prompt to re-authenticate via `gemini` interactive |
| Rate limit (429) | Retry with exponential backoff |
| Context overflow | Truncate with warning, suggest chunking |
| Empty response | Report "No response generated", suggest prompt adjustment |

## Security Considerations

- OAuth credentials stored in `gemini/` directory (existing)
- No sensitive data in prompts (sanitize if needed)
- **Gemini is read-only:** Uses `--approval-mode plan` for CLI
- **Agent can write reports:** The wrapper agent (Haiku) writes findings to disk; Gemini does analysis only

## Runtime Requirements

- `gemini` CLI available in PATH
- OAuth authenticated (existing)
