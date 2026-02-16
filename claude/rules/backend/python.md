---
paths: ["**/*.py"]
---

# Python Rules

## Tooling

ruff (not black/isort/flake8), pyright strict, uv (not pip/poetry), 120 chars, Python 3.13+.

## Type Hints

All function signatures typed. Prefer `list[str]` over `List[str]`. Use `TypedDict` for structured dicts.

## Error Handling

- Specific exceptions, never bare `except` or `except Exception: pass`
- Custom exceptions for domain errors
- Context managers for resources

## Naming (PEP 8)

`snake_case` functions/variables, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, `_private`.

## Classes

- `@dataclass` for data containers, `@property` for computed attributes
- Composition over inheritance. `ABC`/`@abstractmethod` for interfaces.

## gRPC

Inherit servicer, `# noqa: N802` for PascalCase methods, `context.abort()` for errors.

## Testing

pytest with fixtures and `@pytest.mark.parametrize`. Mock at boundaries only.

## Project Structure

`src/package_name/{controller/,usecase/,domain/{model/,repository/},infrastructure/repository/,common/,server.py}`
