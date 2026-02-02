---
paths: ["**/*.go"]
---

# Go Rules

## Linting (golangci-lint)

Required linters and thresholds:
- `gocyclo`: max complexity 15
- `funlen`: max 65 statements per function
- `dupl`: max 100 lines duplicate threshold
- `lll`: max 140 characters line length

Key linters to enable:
- `errorlint` - error wrapping validation
- `contextcheck` - context propagation
- `exhaustive` - exhaustive switch/map
- `gosec` - security checks
- `bodyclose` - HTTP response body closure

## Forbidden Dependencies

Via depguard:
- `log` - Use structured logger (zap) instead
- `github.com/stretchr/testify` - Use standard library testing
- Direct UUID packages - Centralise in `internal/uuid`

## Import Organization

Three-section grouping (enforced by gci):
1. Standard library
2. Third-party packages
3. Local packages (service-specific)

Use `gofmt` rewrite: `interface{}` → `any`

## Error Handling

- Always check errors: `if err != nil { return err }`
- Don't ignore errors with `_` unless explicitly justified with a comment
- Wrap errors with context: `fmt.Errorf("failed to process order: %w", err)`
- Message format: `"failed to <action>: %w"`
- Return early on error; avoid deep nesting
- nilnil acceptable for not-found: `return nil, nil //nolint:nilnil`
- Deferred cleanup ignoring error: `defer func() { _ = tx.Rollback(ctx) }()`

## Naming

- Use MixedCaps, not underscores: `orderID` not `order_id`
- Acronyms stay uppercase: `HTTPServer`, `userID`, `parseJSON`
- Interface names: single-method interfaces use `-er` suffix (`Reader`, `Writer`, `Notifier`)
- Avoid stuttering: `order.Order` is bad, `order.Details` is better

## Interfaces

- Accept interfaces, return structs
- Define interfaces where they're used, not where they're implemented
- Keep interfaces small (1-3 methods); compose larger ones
- Compile-time verification: `var _ Interface = (*impl)(nil)`
- Generate mocks with moq: `//go:generate moq -fmt goimports -out foo_mock.go . Foo`
- Optional tx params: `func Get(ctx context.Context, id string, tx ...pgx.Tx)`

## Testing

- Use standard library testing (no testify)
- Use `t.Context()` not `context.Background()`
- Always call `t.Parallel()` for test functions and subtests
- Map-based table tests: `cases := map[string]struct{...}`
- Use `t.Helper()` in test helper functions
- Mock generation: `//go:generate moq -fmt goimports -out foo_mock.go . Foo`
- Test file naming: `foo_test.go` for `foo.go`

## Concurrency

- Don't start goroutines in init functions
- Pass context as first parameter
- Use `sync.WaitGroup` or channels for coordination
- Avoid goroutine leaks: ensure goroutines can exit

## Common Pitfalls

- Don't defer in loops (resource leak)
- Don't use pointer receivers for small structs that don't need mutation
- Avoid `interface{}` / `any` when concrete types work
- Check `nil` maps before writing (reading is safe)

## Project Structure

```
cmd/
  ├── server/main.go      # HTTP/Connect entry
  ├── scheduler/main.go   # Job scheduler entry
  └── pubsub/main.go      # PubSub worker entry
internal/
  ├── config/             # Environment configuration
  ├── db/                 # Database layer (sqlc)
  ├── repository/         # Data access interfaces + impl
  ├── usecase/            # Business logic
  ├── http/               # HTTP/Connect handlers
  ├── gateway/            # External service clients
  ├── clock/              # Time utilities (mockable)
  └── domainmodel/        # Domain entities
db/
  ├── schema.sql
  └── query/              # SQL for sqlc
```

Main pattern:
- Separate `doMain()` for defer support
- Exit code constants: `exitOK = 0`, `exitError = 1`
- Signal handling with graceful shutdown

## Observability

- Named tracer per package: `var tracer = otel.Tracer("internal/usecase")`
- Manual spans: `ctx, span := tracer.Start(ctx, "method.Name")`
- Always `defer span.End()`
