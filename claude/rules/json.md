---
paths: ["**/*.json"]
---

# TOON Compression

When reading large JSON files (>50 lines or arrays of 5+ objects), prefer `cat file.json | toon` via Bash over raw Read. TOON saves ~50% tokens on tabular data (arrays of uniform objects), ~25% on flat objects.

Skip TOON when:
- Editing JSON (need exact syntax for Edit tool)
- File is <50 lines (overhead not worth it)
- File is a lockfile, schema, or generated artifact
- You need to parse specific nested paths (use `jq` instead)

The `toon` CLI is installed at `/opt/homebrew/bin/toon`. Use `--stats` to see savings.
