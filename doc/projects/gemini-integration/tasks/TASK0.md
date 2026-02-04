# TASK0: Gemini CLI Verification

**Issue:** gemini-integration-config

## Objective

Verify the existing Gemini CLI is installed and authenticated for use by Claude Code agents.

## Required Context

Read these files first:
- `gemini/settings.json` — Existing auth configuration
- Run `gemini --help` to verify CLI is available

## Files to Create

None — this task is verification only.

**Note:** The Gemini CLI is already installed and authenticated. Unlike Codex, Gemini does NOT use an AGENTS.md file. Instructions are passed directly via the `-p` flag.

## Implementation Details

### Verify CLI Installation

```bash
# Check CLI is available
which gemini || command -v gemini
# Expected: in PATH or $(npm root -g)/@google/gemini-cli/bin/gemini

# Check version
gemini --version

# Verify authentication
gemini -p "Hello, respond with 'OK'" 2>&1 | head -5
```

### CLI Usage Patterns

| Pattern | Command |
|---------|---------|
| Simple query | `gemini -p "prompt"` |
| Large input via stdin | `cat file.log \| gemini -p "Analyze..."` |
| Read-only mode | `gemini --approval-mode plan -p "..."` |
| Model selection | `gemini -m gemini-2.0-flash -p "..."` |

### Key Difference from Codex

| Feature | Codex | Gemini |
|---------|-------|--------|
| Instructions file | `codex/AGENTS.md` | None (inline via `-p`) |
| Prompt flag | Inline string | `-p "prompt"` |
| Read-only mode | `-s read-only` | `--approval-mode plan` |

## Verification

```bash
# Test CLI invocation
gemini -p "Respond with only: GEMINI_OK" 2>&1 | grep -q "GEMINI_OK" && echo "CLI works"

# Test stdin input
echo "test content" | gemini -p "Echo the input content" 2>&1 | head -3

# Test model selection
gemini -m gemini-2.0-flash -p "Say 'Flash OK'" 2>&1 | head -3
```

## Acceptance Criteria

- [ ] CLI responds to `-p` flag queries
- [ ] Stdin input works (pipe content to gemini)
- [ ] Model selection works (`-m` flag)
- [ ] `--approval-mode plan` works for read-only
- [ ] Existing OAuth credentials NOT modified
