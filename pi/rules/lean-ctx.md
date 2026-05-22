# lean-ctx — Additive Context Compression
<!-- lean-ctx-additive -->

LeanCTX is installed through `pi-lean-ctx` as optional `ctx_*` tools. Pi built-ins (`read`, `bash`, `grep`, `find`, `ls`, `edit`, `write`) remain valid.

Use when it helps reduce context:
- `ctx_read` for large/repeated file reads.
- `ctx_grep`/`ctx_find`/`ctx_ls` for compact search and directory exploration.
- `ctx_shell` for noisy shell commands.
- `lean_ctx` for LeanCTX diagnostics such as `gain` or `stats`.

Keep native tools available:
- Use native tools when exact uncompressed output is needed.
- Do not set `LEAN_CTX_PI_MODE=replace` unless the user explicitly asks.
- Do not enable LeanCTX MCP bridge (`LEAN_CTX_PI_ENABLE_MCP=1`) unless the user explicitly asks.

Memory boundary:
- Existing memory systems stay primary.
- Do not use LeanCTX knowledge/agent/share features unless the user explicitly asks.
<!-- /lean-ctx -->
