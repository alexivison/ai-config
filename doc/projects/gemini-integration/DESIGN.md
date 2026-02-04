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

Use the existing Gemini CLI (already installed at `$(npm root -g)/@google/gemini-cli/bin/gemini`).

**Existing Directory Structure:**
```
gemini/
├── oauth_creds.json     # OAuth credentials (existing)
├── settings.json        # Auth settings (existing)
└── google_accounts.json # Account info (existing)
```

**Note:** Unlike Codex, Gemini does NOT use an AGENTS.md file. Instructions are passed inline via the `-p` flag.

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
1. Check for explicit mode override:
   - "mode:log" → LOG ANALYSIS
   - "mode:web" → WEB SEARCH

2. Fall back to keyword heuristics if no explicit mode

IF task involves log analysis:
  - Estimate log size: bytes=$(wc -c < "$LOG_FILE"); tokens=$((bytes / 4))
  - IF < 500K tokens → delegate to standard log-analyzer
  - IF > 500K tokens → use gemini-2.5-pro via stdin
  - IF > 1.6M tokens → warn, apply time-range filter or chunking

IF task involves web research:
  - Execute WebSearch tool
  - Optionally fetch pages via WebFetch
  - Synthesize with gemini-2.0-flash
```

**CLI Path Resolution:**
```bash
GEMINI_CMD="${GEMINI_PATH:-$(command -v gemini 2>/dev/null || echo '$(npm root -g)/@google/gemini-cli/bin/gemini')}"
```

### 3. skill-eval.sh Updates

Add auto-suggest pattern for web search (narrowed to avoid overlap with coding questions):

```bash
# Web search triggers (explicit external intent only)
elif echo "$PROMPT_LOWER" | grep -qE '\bresearch (online|the web|externally)\b|\blook up (online|externally)\b|\bsearch the web\b|\bwhat is the (latest|current) version\b|\bwhat do (experts|others|people) say\b|\bfind external (info|documentation)\b'; then
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
│ - > 500K tokens?    │
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

### Inline Instructions

Unlike Codex (which reads from AGENTS.md), Gemini receives instructions directly in the prompt via `-p`. The gemini agent includes analysis instructions in each invocation:

```bash
gemini --approval-mode plan -m gemini-2.5-pro -p "Analyze these logs. Provide:
- Clear findings with specifics
- Severity/priority ratings
- Actionable recommendations

Logs:
$(cat /path/to/logs.log)"
```

### Model Selection

| Use Case | Model | Flag |
|----------|-------|------|
| Log analysis | gemini-2.5-pro | `-m gemini-2.5-pro` |
| Web search synthesis | gemini-2.0-flash | `-m gemini-2.0-flash` |

## Error Handling

| Scenario | Handling |
|----------|----------|
| CLI not found | Check `GEMINI_PATH` env, then `command -v`, then absolute NVM path |
| Auth expired | Prompt to re-authenticate via `gemini` interactive |
| Rate limit (429) | Retry with exponential backoff (verify CLI behavior during implementation) |
| Context overflow (>1.6M tokens) | Apply time-range filter if timestamps present, else chunk sequentially |
| Empty response | Report "No response generated", suggest prompt adjustment |
| Mode ambiguity | Default to log analysis if file paths present, else web search |

## Security Considerations

- OAuth credentials stored in `gemini/` directory (existing)
- No sensitive data in prompts (sanitize if needed)
- **Gemini is read-only:** Uses `--approval-mode plan` for CLI
- **Agent can write reports:** The wrapper agent (Haiku) writes findings to disk; Gemini does analysis only

## Runtime Requirements

- `gemini` CLI available via one of:
  - `GEMINI_PATH` environment variable
  - System PATH (`command -v gemini`)
  - Absolute path: `$(npm root -g)/@google/gemini-cli/bin/gemini`
- OAuth authenticated (existing)
