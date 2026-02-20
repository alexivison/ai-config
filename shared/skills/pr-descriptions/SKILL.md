---
name: pr-descriptions
description: Rules for writing PR descriptions useful to human and agent reviewers. Covers template discovery, section content, and what to avoid.
user-invocable: false
---

# PR Description Rules

How to fill PR descriptions so they are useful to both human and agent reviewers.

## Template Discovery

1. Check for templates in this order:
   - `.github/PULL_REQUEST_TEMPLATE.md` (single file — takes precedence)
   - `.github/PULL_REQUEST_TEMPLATE/` (directory — use default template if one file, skip if multiple and no convention exists)
2. If a template exists, use it exactly — preserve all headings, do not add or remove sections
3. If no template exists, use a minimal structure: Summary, How to Verify, Related Issues

## Filling Template Sections

Regardless of section name (Summary, Description, etc.), follow these content rules:

### State facts, not impressions

| Bad | Good |
|-----|------|
| "Improved error handling" | "Changed `auth.ts:45` to throw on null instead of returning undefined" |
| "Refactored the service" | "Extracted `validateInput()` from `handleRequest()` in `user-service.go`" |
| "Fixed a bug" | "Fixed off-by-one in pagination query — page 2 was returning page 1 results" |

### Include previous and new behavior

Even if the template doesn't have a dedicated section, state both in the overview:

```
Previously: expired tokens returned 200 with empty body
Now: expired tokens return 401 with {"error": "token_expired"}
```

### List changed files with rationale

Not just *what* changed but *why*:

```
- services/auth/handler.go — added token expiry check before DB lookup
- services/auth/handler_test.go — added test for expired token path
- schema/errors.go — added TokenExpired error constant
```

### Provide concrete verification commands

| Bad | Good |
|-----|------|
| "Run the tests" | `go test ./services/auth/...` |
| "Check the endpoint" | `curl -H "Authorization: Bearer expired" localhost:8080/api/me` |
| "Verify the build" | `npm run build && npm run typecheck` |

### Link to specs and issues

Fill any references section (参考, References, Related) with actual URLs or issue IDs. Never write "see Jira" without a link.

## Cleanup

- Replace HTML comment instructions (`<!-- describe changes -->`) with actual content — leftover comments confuse agent reviewers
- Remove placeholder text like "N/A" or "n/a" — leave the section empty or omit optional content

## What NOT to Do

- Do not add sections beyond what the template defines
- Do not embed workflow markers, raw command output, or checkpoint file references in the PR body — concise verification summaries (e.g., "Tests: 42 passed, Lint: clean") are fine within existing template sections
- Do not override team conventions (reviewer count, label policies, etc.)
- Do not repeat the full diff — summarize intent, not line-by-line changes
