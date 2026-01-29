---
paths: ["**/*.go"]
---

# Go Rules

## Error Handling

- Always check errors: `if err != nil { return err }`
- Don't ignore errors with `_` unless explicitly justified with a comment
- Wrap errors with context: `fmt.Errorf("failed to process order: %w", err)`
- Return early on error; avoid deep nesting

## Naming

- Use MixedCaps, not underscores: `orderID` not `order_id`
- Acronyms stay uppercase: `HTTPServer`, `userID`, `parseJSON`
- Interface names: single-method interfaces use `-er` suffix (`Reader`, `Writer`, `Notifier`)
- Avoid stuttering: `order.Order` is bad, `order.Details` is better

## Interfaces

- Accept interfaces, return structs
- Define interfaces where they're used, not where they're implemented
- Keep interfaces small (1-3 methods); compose larger ones

## Testing

- Table-driven tests for multiple cases
- Use `t.Helper()` in test helper functions
- Test file naming: `foo_test.go` for `foo.go`
- Use testify/assert or standard library, be consistent

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

- Keep `main.go` minimal; logic in packages
- Internal packages for non-exported code
- Avoid circular imports; use interfaces to break cycles
