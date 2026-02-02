---
paths: ["**/*.py"]
---

# Python Rules

## Tooling

- **Linter/Formatter:** ruff (not black/isort/flake8)
- **Type Checker:** pyright strict mode (not mypy)
- **Package Manager:** uv (not pip/poetry)
- **Line length:** 120 characters
- **Python version:** 3.13+

Ruff rules: A (builtins), E (style), F (pyflakes), I (imports), N (naming), T100 (breakpoints)

## Type Hints

- Use type hints for function signatures
- All function signatures require types
- Target pyright strict mode compliance
- Prefer `list[str]` over `List[str]` (Python 3.9+)
- Use `TypedDict` for structured dicts, not `dict[str, Any]`

## Error Handling

- Be specific with exceptions: `except ValueError` not bare `except`
- Don't catch and ignore: `except Exception: pass` is almost always wrong
- Use custom exceptions for domain errors
- Context managers (`with`) for resource management

## Naming (PEP 8)

- Functions and variables: `snake_case`
- Classes: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Private: `_single_leading_underscore`
- Avoid single-letter names except for loops (`i`, `j`) or lambdas (`x`)

## Functions

- Keep functions small and focused
- Default arguments: never use mutable defaults (`def foo(items=[])` is a bug)
- Use `*args` and `**kwargs` sparingly
- Prefer keyword arguments for functions with 3+ parameters

## Classes

- Use `@dataclass` for data containers
- Use `@property` for computed attributes, not getters/setters
- Prefer composition over inheritance
- Use `ABC` and `@abstractmethod` for interfaces
- Interface naming: `*Interface` suffix for ABCs
- Docstrings required for abstract methods
- Simple classes for tiny models; @dataclass for multi-field data

## Dependency Injection

- Constructor injection with typed interfaces
- Composition root in server.py
- Example: `def __init__(self, repo: RepositoryInterface)`

## gRPC Patterns

- Inherit from generated servicer: `class FooController(grpc_v1.FooServiceServicer)`
- Use `# noqa: N802` for PascalCase method names (gRPC requirement)
- Error handling: `context.abort(code=StatusCode.X, details=str(e))`
- Type hints for request/response protos

## Logging

- Module-level logger: `_LOGGER = StructuredLogger.get_logger()`
- Structured logging with context fields
- Exception logging: `_LOGGER.error("message", exception=e)`

## Async

- Don't mix sync and async: use `asyncio.to_thread()` for blocking calls
- Use `async with` for async context managers
- Gather concurrent tasks: `await asyncio.gather(*tasks)`
- Handle cancellation: catch `asyncio.CancelledError` if cleanup needed

## Testing

- Use pytest, not unittest (unless project convention)
- Fixtures over setup/teardown
- Parametrize for multiple test cases: `@pytest.mark.parametrize`
- Mock at boundaries, not internal implementation

## Common Pitfalls

- Don't modify list while iterating: `for item in list[:]:` to iterate copy
- String concatenation in loops: use `"".join(items)` or f-strings
- Avoid `import *` (pollutes namespace)
- Use `is` for `None` comparison: `if x is None` not `if x == None`

## Project Structure (Clean Architecture)

```
src/package_name/
  ├── controller/           # gRPC/REST handlers
  │   └── interceptor/      # gRPC interceptors
  ├── usecase/              # Business logic
  ├── domain/
  │   ├── model/            # Business entities
  │   └── repository/       # Data access interfaces
  ├── infrastructure/
  │   └── repository/       # Repository implementations
  ├── common/               # Shared utilities (logger)
  └── server.py             # Entry point
tests/
```

Interfaces optional for small scope; add dto/, service/, gateway/ as needed.
