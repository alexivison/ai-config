# lean-ctx — Additive Context Compression

LeanCTX is available through MCP tools when configured, and through the `lean-ctx` CLI when installed locally. Use it as an optional compression layer; native tools remain valid.

## MCP tools

| Tool | Purpose |
|------|---------|
| `ctx_read` | Cached/compressed file reads (`auto`, `full`, `map`, `signatures`, `lines:N-M`) |
| `ctx_shell` | Shell commands with compressed output |
| `ctx_search` | Token-efficient code search |
| `ctx_tree` | Compact directory maps |
| `ctx_compress` | Manual context compression |
| `ctx_metrics` | Token-savings diagnostics |

## CLI fallback

Prefix noisy commands with `lean-ctx -c` when compressed output is enough:

```bash
lean-ctx -c "git status"
lean-ctx -c "go test ./..."
lean-ctx -c "npm test"
```

Use native commands when exact uncompressed output is needed.

## Boundaries

- Use native Edit/Write normally.
- Do not run `lean-ctx setup` from inside an agent session.
- Existing memory systems stay primary.
- Do not use `ctx_knowledge`, `ctx_agent`, `ctx_share`, or `ctx_overview` unless the user explicitly asks.
