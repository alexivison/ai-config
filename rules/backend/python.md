---
paths: ["**/*.py"]
---

# Python Rules

## Type Hints

- Use type hints for function signatures
- Use `from __future__ import annotations` for forward references
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

## Project Structure

- `__init__.py` should be minimal (re-exports only)
- Keep imports at top of file, grouped: stdlib, third-party, local
- Use absolute imports over relative
