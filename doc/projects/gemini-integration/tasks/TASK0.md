# TASK0: Gemini CLI Configuration

**Issue:** gemini-integration-config

## Objective

Configure the existing Gemini CLI for use by Claude Code agents. The CLI is already installed and authenticated.

## Required Context

Read these files first:
- `gemini/settings.json` — Existing auth configuration
- `codex/AGENTS.md` — Reference for agent instructions pattern
- Run `gemini --help` to verify CLI is available

## Files to Create

| File | Purpose |
|------|---------|
| `gemini/AGENTS.md` | Instructions for Gemini when invoked by agents |

**Note:** The Gemini CLI is already installed and authenticated. We only need to add agent instructions.

## Implementation Details

### Verify CLI Installation

```bash
# Check CLI is available
which gemini
# Expected: /Users/aleksituominen/.nvm/versions/node/v24.12.0/bin/gemini

# Check version
gemini --version

# Verify authentication
gemini -p "Hello, respond with 'OK'" 2>&1 | head -5
```

### gemini/AGENTS.md

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

### CLI Usage Patterns

| Pattern | Command |
|---------|---------|
| Simple query | `gemini -p "prompt"` |
| Large input via stdin | `cat file.log \| gemini -p "Analyze..."` |
| Read-only mode | `gemini --approval-mode plan -p "..."` |
| Model selection | `gemini -m gemini-2.0-flash -p "..."` |

## Verification

```bash
# Check AGENTS.md created
test -f gemini/AGENTS.md && echo "AGENTS.md exists"

# Test CLI invocation
gemini -p "Respond with only: GEMINI_OK" 2>&1 | grep -q "GEMINI_OK" && echo "CLI works"

# Test stdin input
echo "test content" | gemini -p "Echo the input content" 2>&1 | head -3
```

## Acceptance Criteria

- [ ] `gemini/AGENTS.md` created with agent instructions
- [ ] CLI responds to `-p` flag queries
- [ ] Stdin input works (pipe content to gemini)
- [ ] Model selection works (`-m` flag)
- [ ] Existing OAuth credentials NOT modified
