# Backend Testing Reference (Go)

A comprehensive guide to testing practices in the Go backend codebase.

## Testing Philosophy

The same core principles from frontend testing apply:

1. **Tests are mandatory** - Automated tests enable confident changes and guarantee specifications
2. **Test at appropriate levels** - Unit tests for pure logic, integration tests for external dependencies
3. **Write tests early** - Develop tests alongside implementation (TDD-style)
4. **Include tests in PRs** - Tests and implementation belong in the same PR

## Test Classifications

| Type | Description | Tools |
|------|-------------|-------|
| **Unit Tests** | Isolated logic, domain models | Go testing, go-cmp |
| **Integration Tests** | Database, external services | testcontainers-go |
| **API Tests** | gRPC/HTTP endpoint testing | Separate api-test modules |

## Technical Setup

### Frameworks & Libraries

| Package | Purpose |
|---------|---------|
| `testing` | Standard Go test runner |
| `github.com/matryer/moq` | Mock generation |
| `github.com/google/go-cmp` | Struct comparison/diff |
| `github.com/testcontainers/testcontainers-go` | Container-based integration tests |
| `github.com/morikuni/failure` | Error wrapping |

### File Organization

```
services/<service>/
├── internal/
│   ├── domainmodel/
│   │   ├── greeting.go
│   │   └── greeting_test.go      # Domain model tests
│   ├── repository/
│   │   ├── greeting.go           # Interface + implementation
│   │   ├── greeting_mock.go      # Generated mock
│   │   └── greeting_test.go      # Repository tests (with DB)
│   ├── usecase/
│   │   ├── greeting.go
│   │   └── greeting_test.go      # Use case tests (with mocks)
│   ├── gateway/
│   │   ├── gcs.go
│   │   └── gcs_mock.go           # External service mocks
│   └── pubsub/
│       ├── sample_event.go
│       └── sample_event_mock.go
├── db/
│   └── schema.sql                # Database schema for tests
└── Makefile
```

**Naming conventions:**
- Test files: `*_test.go`
- Mock files: `*_mock.go`
- Test package: `package <name>_test` (black-box testing)

---

## Mock Generation

### Using moq

Add a `go:generate` directive to the interface file:

```go
//go:generate moq -fmt goimports -out greeting_mock.go . Greeting

type Greeting interface {
    Get(ctx context.Context, greetingID string, tx ...pgx.Tx) (*domainmodel.Greeting, error)
    Store(ctx context.Context, greeting *domainmodel.Greeting, tx ...pgx.Tx) (*domainmodel.Greeting, error)
}
```

Run mock generation:
```bash
make mock-gen
# or
go generate ./...
```

### Using Generated Mocks

```go
mockedGreeting := &repository.GreetingMock{
    GetFunc: func(ctx context.Context, greetingID string, tx ...pgx.Tx) (*domainmodel.Greeting, error) {
        return &domainmodel.Greeting{GreetingID: greetingID}, nil
    },
    StoreFunc: func(ctx context.Context, greeting *domainmodel.Greeting, tx ...pgx.Tx) (*domainmodel.Greeting, error) {
        return greeting, nil
    },
}

// Verify calls
calls := mockedGreeting.GetCalls()
if len(calls) != 1 {
    t.Errorf("expected 1 call, got %d", len(calls))
}
```

---

## Test Patterns

### Table-Driven Tests

Standard pattern for multiple test cases:

```go
func TestNewGreeting(t *testing.T) {
    t.Parallel()

    now := time.Now()
    cases := map[string]struct {
        messageID, name string
        requestTime     time.Time
        wantErr         bool
    }{
        "valid name and ID": {
            messageID:   "1000",
            name:        "Bob",
            requestTime: now,
            wantErr:     false,
        },
        "empty name": {
            messageID:   "2000",
            name:        "",
            requestTime: now,
            wantErr:     true,
        },
    }

    for name, tc := range cases {
        t.Run(name, func(t *testing.T) {
            t.Parallel()

            m, err := domainmodel.NewGreeting(tc.messageID, tc.name, tc.requestTime)

            if tc.wantErr {
                if err == nil {
                    t.Fatal("expected error but got nil")
                }
                return
            }

            if err != nil {
                t.Fatalf("unexpected error: %v", err)
            }

            if m.MessageID != tc.messageID {
                t.Errorf("got %s, want %s", m.MessageID, tc.messageID)
            }
        })
    }
}
```

### Use Case Tests with Mocks

```go
func TestGreetingImpl_SayHello(t *testing.T) {
    t.Parallel()

    ctx := t.Context()

    cases := map[string]struct {
        id, name, wantMessage string
        storeFunc             func(ctx context.Context, greeting *domainmodel.Greeting, tx ...pgx.Tx) (*domainmodel.Greeting, error)
        publisherFunc         func(ctx context.Context, msg proto.Message) error
        wantErr               error
    }{
        "successful greeting": {
            id:          "1000",
            name:        "Bob",
            wantMessage: "Hello, Bob!",
            storeFunc: func(_ context.Context, _ *domainmodel.Greeting, _ ...pgx.Tx) (*domainmodel.Greeting, error) {
                return nil, nil
            },
            publisherFunc: func(_ context.Context, _ proto.Message) error {
                return nil
            },
            wantErr: nil,
        },
        "store failure": {
            id:          "3000",
            name:        "Tom",
            wantMessage: "",
            storeFunc: func(_ context.Context, _ *domainmodel.Greeting, _ ...pgx.Tx) (*domainmodel.Greeting, error) {
                return nil, pgx.ErrTxClosed
            },
            publisherFunc: func(_ context.Context, _ proto.Message) error {
                return nil
            },
            wantErr: pgx.ErrTxClosed,
        },
    }

    pool := postgres.PreparePostgresResources(t, ctx, []string{"../../db/schema.sql"})

    for name, tc := range cases {
        t.Run(name, func(t *testing.T) {
            t.Parallel()

            u := usecase.NewGreeting(
                &repository.GreetingMock{StoreFunc: tc.storeFunc},
                pool,
                &gateway.GoogleCloudStorageClientMock{},
                clock.NewFixedClocker(),
                &pubsub.SampleEventPublisherMock{PublishFunc: tc.publisherFunc},
            )

            gotID, gotMessage, _, err := u.SayHello(t.Context(), tc.id, tc.name)

            if tc.wantErr != nil {
                if err == nil {
                    t.Fatal("expected error but got nil")
                }
                return
            }

            if err != nil {
                t.Fatalf("unexpected error: %v", err)
            }

            if gotID != tc.id {
                t.Errorf("got %s, want %s", gotID, tc.id)
            }

            if gotMessage != tc.wantMessage {
                t.Errorf("got %s, want %s", gotMessage, tc.wantMessage)
            }
        })
    }
}
```

### Repository Tests with Test Containers

```go
func TestGreetingRepository(t *testing.T) {
    t.Parallel()

    ctx := t.Context()

    // Start PostgreSQL container with schema
    pool := postgres.PreparePostgresResources(t, ctx, []string{"../../db/schema.sql"})

    r := repository.NewGreetingRepository(clock.NewFixedClocker(), pool)

    // Test Store
    wantModel := &domainmodel.Greeting{
        MessageID:   "test-id",
        Name:        "Bob",
        RequestTime: time.Now(),
    }

    m, err := domainmodel.NewGreeting(wantModel.MessageID, wantModel.Name, wantModel.RequestTime)
    if err != nil {
        t.Fatalf("failed to create greeting model: %v", err)
    }

    got, err := r.Store(t.Context(), m)
    if err != nil {
        t.Fatalf("failed to store greeting: %v", err)
    }

    // Use go-cmp for comparison (ignoring generated fields)
    opt := cmpopts.IgnoreFields(domainmodel.Greeting{}, "GreetingID")
    if diff := cmp.Diff(wantModel, got, opt); diff != "" {
        t.Errorf("Greeting mismatch (-want +got):\n%s", diff)
    }

    // Test Get
    retrieved, err := r.Get(ctx, got.GreetingID)
    if err != nil {
        t.Fatalf("failed to get greeting: %v", err)
    }

    if diff := cmp.Diff(got, retrieved); diff != "" {
        t.Errorf("Retrieved greeting mismatch (-want +got):\n%s", diff)
    }
}
```

---

## Test Utilities

### PostgreSQL with Testcontainers

Use `testcontainers-go` for realistic database integration tests:

```go
import (
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/testcontainers/testcontainers-go"
    "github.com/testcontainers/testcontainers-go/modules/postgres"
    "github.com/testcontainers/testcontainers-go/wait"
)

func setupPostgres(t *testing.T, ctx context.Context) *pgxpool.Pool {
    t.Helper()

    container, err := postgres.Run(ctx, "postgres:16",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"),
        postgres.WithPassword("test"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready to accept connections").
                WithOccurrence(2)),
    )
    if err != nil {
        t.Fatalf("failed to start postgres: %v", err)
    }

    t.Cleanup(func() { container.Terminate(ctx) })

    connStr, err := container.ConnectionString(ctx, "sslmode=disable")
    if err != nil {
        t.Fatalf("failed to get connection string: %v", err)
    }

    pool, err := pgxpool.New(ctx, connStr)
    if err != nil {
        t.Fatalf("failed to create pool: %v", err)
    }

    t.Cleanup(func() { pool.Close() })

    return pool
}
```

### Fixed Clock for Deterministic Tests

Define a clock interface for time-dependent code:

```go
// clock.go
type Clock interface {
    Now() time.Time
}

type realClock struct{}
func (realClock) Now() time.Time { return time.Now() }
func NewClock() Clock { return realClock{} }

// For tests
type fixedClock struct{ t time.Time }
func (c fixedClock) Now() time.Time { return c.t }
func NewFixedClock(t time.Time) Clock { return fixedClock{t: t} }
```

### Common Test Utilities

| Tool | Purpose |
|------|---------|
| `testcontainers-go` | Container-based integration tests (Postgres, Redis, etc.) |
| `testcontainers-go/modules/*` | Pre-configured modules for common services |
| `github.com/orlangure/gnomock` | Alternative to testcontainers |
| `net/http/httptest` | HTTP server/client mocking |

---

## Interface-Based Design for Testability

Define interfaces for external dependencies:

```go
// In repository/greeting.go
//go:generate moq -fmt goimports -out greeting_mock.go . Greeting

type Greeting interface {
    Get(ctx context.Context, greetingID string, tx ...pgx.Tx) (*domainmodel.Greeting, error)
    Store(ctx context.Context, greeting *domainmodel.Greeting, tx ...pgx.Tx) (*domainmodel.Greeting, error)
}

// Compile-time check that implementation satisfies interface
var _ Greeting = (*greetingImpl)(nil)
```

Use dependency injection in constructors:

```go
func NewGreeting(
    repo repository.Greeting,      // Interface
    pool *pgxpool.Pool,
    gcs gateway.GoogleCloudStorageClient,  // Interface
    clock clock.Clocker,           // Interface
    publisher pubsub.SampleEventPublisher, // Interface
) *greetingImpl {
    return &greetingImpl{
        repo:      repo,
        pool:      pool,
        gcs:       gcs,
        clock:     clock,
        publisher: publisher,
    }
}
```

---

## Scripts

```bash
# Run all tests
make test

# Run tests with verbose output
make test-v

# Run tests with coverage report
make test-cov

# Generate mocks
make mock-gen

# Run linter
make lint
```

---

## Best Practices Summary

1. **Use `t.Parallel()`** - Enable parallel test execution for speed
2. **Use `t.Context()`** - Get context that's canceled when test ends
3. **Use table-driven tests** - Organized, readable, easy to extend
4. **Use `t.Helper()`** - In helper functions for better error reporting
5. **Use `t.Cleanup()`** - For automatic resource cleanup
6. **Mock at interface boundaries** - Use generated mocks for dependencies
7. **Use `go-cmp` for comparisons** - Better diff output than manual checks
8. **Use testcontainers** - For realistic database integration tests
9. **Use fixed clocks** - For deterministic time-dependent tests
10. **Black-box testing** - Use `package name_test` for testing public API
