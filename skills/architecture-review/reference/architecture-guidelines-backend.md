# Architecture Guidelines — Backend (Go, Python, Node.js, etc.)

Backend-specific patterns, smells, and thresholds.

---

## Metrics

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| Function length | >50 lines | Long functions are hard to understand and test |
| Function parameters | >5 | Too many params suggests missing abstraction |
| Struct/class fields | >10 | Large types indicate mixed responsibilities |
| Import count | >15 | Many imports suggest file doing too much |
| Public functions/file | >10 | Large public API suggests splitting |

---

## Detection Patterns

**God function detection:**
```go
// Functions with many responsibilities
func ProcessOrder(ctx context.Context, db *sql.DB, order Order,
    user User, payment Payment, inventory Inventory,
    notifier Notifier, logger Logger) error {
    // Too many parameters = too many concerns
}
```

**Layer violation detection:**
```go
// Handler doing business logic (bad)
func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
    // Validation (OK in handler)
    // Business rules (should be in service)
    // Direct DB access (should be in repository)
    db.Query("INSERT INTO orders...")  // Layer violation
}
```

**Error swallowing detection:**
```go
// Error logged but not handled
if err != nil {
    log.Error(err)
    // Missing: return err
}

// Empty error handling
if err != nil {
    // Nothing here
}
```

**N+1 query detection:**
```go
// Loop with DB call inside
for _, user := range users {
    orders, _ := db.Query("SELECT * FROM orders WHERE user_id = ?", user.ID)
    // Should be: SELECT * FROM orders WHERE user_id IN (...)
}
```

---

## Backend Layer Model

```
┌─────────────────────────────────────┐
│     Handlers/Controllers (HTTP)     │  Request parsing, response formatting
├─────────────────────────────────────┤
│         Services (Business)         │  Business logic, orchestration
├─────────────────────────────────────┤
│       Repositories (Data)           │  Database access, caching
├─────────────────────────────────────┤
│         Domain (Models)             │  Entities, value objects
└─────────────────────────────────────┘
```

**Violations to detect:**
- Handlers doing business logic
- Services doing direct DB access
- Repositories containing business rules
- Domain models with infrastructure dependencies

---

## Backend Smells

### God Classes/Modules

**Symptoms:**
- Class/struct with >10 methods or fields
- Names like "Manager", "Handler", "Processor", "Helper"
- File handles multiple unrelated features
- Difficult to describe in one sentence

**Example (bad):**
```go
type OrderManager struct {
    db           *sql.DB
    cache        *redis.Client
    emailSender  EmailSender
    smsSender    SMSSender
    paymentGW    PaymentGateway
    inventory    InventoryService
    analytics    AnalyticsClient
    // ... doing everything
}

func (m *OrderManager) CreateOrder() {}
func (m *OrderManager) SendConfirmation() {}
func (m *OrderManager) ProcessPayment() {}
func (m *OrderManager) UpdateInventory() {}
func (m *OrderManager) TrackAnalytics() {}
```

**Recommendation:**
```go
// Split by responsibility
type OrderService struct { repo OrderRepository }
type OrderNotifier struct { email, sms Sender }
type PaymentProcessor struct { gateway PaymentGateway }
```

### Error Handling Anti-Patterns

**Swallowed errors:**
```go
// Bad: Error logged but execution continues
if err != nil {
    log.Error(err)
}
// Code continues as if nothing happened
```

**Generic errors:**
```go
// Bad: Loses context
if err != nil {
    return errors.New("operation failed")
}

// Good: Wraps with context
if err != nil {
    return fmt.Errorf("failed to create order %s: %w", orderID, err)
}
```

**Inconsistent patterns:**
```go
// Some functions return (result, error)
// Others panic
// Others return sentinel values
// Pick one pattern and stick to it
```

### Dependency Issues

**Circular dependencies:**
```
package A imports B
package B imports A  // Circular!
```

**Concrete dependencies:**
```go
// Bad: Depends on concrete type
type OrderService struct {
    db *sql.DB  // Hard to test, hard to swap
}

// Good: Depends on interface
type OrderService struct {
    repo OrderRepository  // Easy to mock
}
```

**Constructor with too many params:**
```go
// Bad: 8 parameters
func NewOrderService(db, cache, email, sms, payment, inventory, analytics, logger)

// Good: Options pattern or config struct
func NewOrderService(cfg OrderServiceConfig)
```

### Data Access Anti-Patterns

**N+1 queries:**
```go
// Bad: 1 query + N queries
users := db.Query("SELECT * FROM users")
for _, u := range users {
    orders := db.Query("SELECT * FROM orders WHERE user_id = ?", u.ID)
}

// Good: 2 queries total
users := db.Query("SELECT * FROM users")
orders := db.Query("SELECT * FROM orders WHERE user_id IN (?)", userIDs)
```

**Missing transactions:**
```go
// Bad: Partial failure possible
db.Exec("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
// If this fails, money disappeared:
db.Exec("UPDATE accounts SET balance = balance + 100 WHERE id = 2")

// Good: Atomic operation
tx.Exec("UPDATE accounts SET balance = balance - 100 WHERE id = 1")
tx.Exec("UPDATE accounts SET balance = balance + 100 WHERE id = 2")
tx.Commit()
```

**Unbounded queries:**
```go
// Bad: Could return millions of rows
db.Query("SELECT * FROM logs")

// Good: Always paginate
db.Query("SELECT * FROM logs LIMIT ? OFFSET ?", limit, offset)
```

### Concurrency Issues (Go-specific)

**Goroutine leaks:**
```go
// Bad: Goroutine never exits
go func() {
    for {
        // No exit condition, no context
    }
}()

// Good: Controlled lifecycle
go func(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        default:
            // work
        }
    }
}(ctx)
```

**Missing synchronization:**
```go
// Bad: Race condition
var counter int
go func() { counter++ }()
go func() { counter++ }()

// Good: Synchronized access
var counter atomic.Int64
go func() { counter.Add(1) }()
go func() { counter.Add(1) }()
```

---

## Recommended Patterns

### Dependency Injection

```go
// Define interface for dependencies
type OrderRepository interface {
    Create(ctx context.Context, order Order) error
    GetByID(ctx context.Context, id string) (Order, error)
}

// Inject via constructor
type OrderService struct {
    repo   OrderRepository
    logger Logger
}

func NewOrderService(repo OrderRepository, logger Logger) *OrderService {
    return &OrderService{repo: repo, logger: logger}
}
```

### Repository Pattern

```go
// Abstract data access behind interface
type UserRepository interface {
    FindByID(ctx context.Context, id string) (*User, error)
    FindByEmail(ctx context.Context, email string) (*User, error)
    Save(ctx context.Context, user *User) error
}

// Implementation details hidden
type PostgresUserRepository struct {
    db *sql.DB
}

func (r *PostgresUserRepository) FindByID(ctx context.Context, id string) (*User, error) {
    // SQL implementation
}
```

### Options Pattern (Go)

```go
// For functions with many optional parameters
type ServerOption func(*Server)

func WithPort(port int) ServerOption {
    return func(s *Server) { s.port = port }
}

func WithTimeout(d time.Duration) ServerOption {
    return func(s *Server) { s.timeout = d }
}

func NewServer(opts ...ServerOption) *Server {
    s := &Server{port: 8080, timeout: 30 * time.Second}  // defaults
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage
server := NewServer(WithPort(9000), WithTimeout(time.Minute))
```

### Error Wrapping

```go
// Add context to errors as they bubble up
func (s *OrderService) CreateOrder(ctx context.Context, req CreateOrderRequest) error {
    user, err := s.userRepo.GetByID(ctx, req.UserID)
    if err != nil {
        return fmt.Errorf("get user for order: %w", err)
    }

    order, err := s.orderRepo.Create(ctx, newOrder)
    if err != nil {
        return fmt.Errorf("create order for user %s: %w", req.UserID, err)
    }

    return nil
}

// Caller can unwrap to check specific errors
if errors.Is(err, ErrNotFound) {
    // Handle not found case
}
```

### Graceful Shutdown

```go
func main() {
    ctx, cancel := context.WithCancel(context.Background())

    // Handle shutdown signals
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

    go func() {
        <-sigCh
        cancel()  // Signal all goroutines to stop
    }()

    // Start server with context
    if err := server.Run(ctx); err != nil {
        log.Fatal(err)
    }
}
```

---

## Sources

- [Effective Go - golang.org](https://go.dev/doc/effective_go)
- [Go Code Review Comments - golang/go wiki](https://github.com/golang/go/wiki/CodeReviewComments)
- [Clean Architecture - Uncle Bob](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Code Quality Metrics - Qodo](https://www.qodo.ai/blog/code-quality/)
