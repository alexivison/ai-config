# Architecture Review Reference — Backend

Backend-specific patterns, smells, and thresholds (Go, Python, Node.js).

---

## Metrics

| Metric | Warn `[q]` | Block `[must]` |
|--------|------------|----------------|
| Function length | >50 lines | >100 lines |
| Function parameters | >5 | >8 |
| Struct/class fields | >10 | >15 |
| Import count | >15 | >25 |
| Public functions/file | >10 | >20 |
| File length | >400 lines | >600 lines |

---

## Layer Violations `[must]`

| Detection | Issue |
|-----------|-------|
| Handler contains SQL/DB calls | Handlers should call services |
| Service contains raw SQL | Services should call repositories |
| Repository contains business logic | Repositories are data access only |
| Domain imports infrastructure | Domain should be pure |

**Expected layer flow:**
```
Handler → Service → Repository → Database
```

---

## Backend Smells

### Blocking `[must]`

| Smell | Detection |
|-------|-----------|
| God Class | >10 methods, name contains "Manager"/"Handler"/"Processor" |
| Error Swallowing | `if err != nil { log.Error(err) }` without return |
| N+1 Query | DB call inside loop |
| Missing Transaction | Multiple related writes without tx |
| Unbounded Query | `SELECT *` without LIMIT |

### Warning `[q]`

| Smell | Detection |
|-------|-----------|
| Concrete Dependencies | Struct field is concrete type, not interface |
| Constructor Bloat | Constructor with >5 parameters |
| Generic Errors | `errors.New("failed")` without context |
| Circular Imports | Package A imports B, B imports A |

---

## Error Handling `[must]`

| Pattern | Detection |
|---------|-----------|
| Swallowed error | Error logged but function continues |
| Empty catch | `if err != nil { }` with no body |
| Lost context | `return errors.New("failed")` instead of wrapping |
| Inconsistent style | Mix of `(result, error)`, panic, sentinel values |

---

## Concurrency (Go) `[must]`

| Pattern | Detection |
|---------|-----------|
| Goroutine leak | `go func()` without context or exit condition |
| Race condition | Shared variable modified in multiple goroutines |
| Missing sync | Counter/map accessed from goroutines without mutex/atomic |

---

## Data Access `[must]`

| Pattern | Detection |
|---------|-----------|
| N+1 queries | `for user := range users { db.Query(...user.ID) }` |
| Missing transaction | Multiple `db.Exec` for related operations |
| Unbounded result | `SELECT * FROM table` without LIMIT |
| SQL in handler | Raw SQL outside repository layer |

---

## Detection Patterns

**God function detection:**
```go
func ProcessOrder(ctx, db, order, user, payment, inventory, notifier, logger)
// >5 params = too many concerns
```

**Error swallowing:**
```go
if err != nil {
    log.Error(err)
    // Missing: return err
}
```

**N+1 query:**
```go
for _, user := range users {
    orders, _ := db.Query("...WHERE user_id = ?", user.ID)
}
```

---

## Verdicts

| Verdict | Condition |
|---------|-----------|
| **SKIP** | All metrics below warn thresholds |
| **APPROVE** | Deep review passed, no `[must]` |
| **REQUEST_CHANGES** | Has `[must]` or unresolved `[q]` |
| **NEEDS_DISCUSSION** | Major refactoring needed |
