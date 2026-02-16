---
paths: ["**/*.go"]
---

# Go Rules

## Linting (golangci-lint)

Thresholds: gocyclo max 15, funlen max 65, dupl 100, lll 140 chars.
Key linters: errorlint, contextcheck, exhaustive, gosec, bodyclose.

## Forbidden Dependencies

- `log` → use zap
- `github.com/stretchr/testify` → use stdlib
- Direct UUID packages → centralise in `internal/uuid`

## Imports

Three-section grouping (gci): stdlib, third-party, local. Rewrite `interface{}` → `any`.

## Error Handling

- Always check: `if err != nil { return err }`
- Wrap with context: `fmt.Errorf("failed to <action>: %w", err)`
- Return early, avoid nesting
- nilnil for not-found: `return nil, nil //nolint:nilnil`

## Naming

- MixedCaps not underscores. Acronyms uppercase: `HTTPServer`, `userID`
- `-er` suffix for single-method interfaces
- No stuttering: `order.Details` not `order.Order`

## Interfaces

- Accept interfaces, return structs. Define where used.
- Small (1-3 methods). Compile-time: `var _ Interface = (*impl)(nil)`
- Mocks: `//go:generate moq -fmt goimports -out foo_mock.go . Foo`

## Testing

- Stdlib only. `t.Context()` not `context.Background()`. Always `t.Parallel()`.
- Map-based table tests. `t.Helper()` in helpers.

## Concurrency

- No goroutines in init. Context as first param. Avoid goroutine leaks.

## Project Structure

`cmd/{server,scheduler,pubsub}/main.go` | `internal/{config,db,repository,usecase,http,gateway,clock,domainmodel}/` | `db/{schema.sql,query/}`
