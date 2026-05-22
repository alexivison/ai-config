# lean-ctx — Additive Context Compression
<!-- lean-ctx-additive -->

LeanCTX is installed as an optional context-compression layer.

Use when it helps reduce context:
- `ctx_read(path, mode)` for large/repeated file reads (`auto`, `full`, `map`, `signatures`, `lines:N-M`).
- `ctx_search(pattern, path)` for compact search results.
- `ctx_tree(path)` for compact directory maps.
- `ctx_shell(command)` or `lean-ctx -c "..."` for compressed shell output.

Keep native tools available:
- Use native Edit/Write/StrReplace normally.
- Use native reads/search/shell when exact uncompressed output is needed.
- Do not run `lean-ctx setup` from inside an agent session.

Memory boundary:
- Existing memory systems are primary.
- Do not use `ctx_knowledge`, `ctx_agent`, `ctx_share`, or `ctx_overview` unless the user explicitly asks.
<!-- /lean-ctx -->
