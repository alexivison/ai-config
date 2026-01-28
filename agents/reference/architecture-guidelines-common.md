# Architecture Guidelines — Common

Shared principles and metrics that apply to all code regardless of language or framework.

---

## Common Metrics

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| % file changed | >40% | Major changes warrant architectural review |
| TODO/FIXME count | >3 | Accumulating tech debt |
| Duplicate code blocks | >2 | DRY violation |
| File length | >400 lines | Long files are hard to navigate |
| Cyclomatic complexity | >10 | High branching makes testing difficult |
| Nesting depth | >4 levels | Deep nesting reduces readability |

---

## Universal Principles

### Single Responsibility Principle (SRP)

Every module, class, or function should have one reason to change.

**Signs of violation:**
- Name includes "And" or "Or"
- Difficult to describe purpose in one sentence
- Multiple unrelated dependencies
- Changes for different reasons

### Separation of Concerns

Different aspects of functionality should be in different modules.

**Common layers:**
```
┌─────────────────────────────┐
│    Presentation / API       │  User interface, HTTP handlers
├─────────────────────────────┤
│    Business Logic           │  Domain rules, orchestration
├─────────────────────────────┤
│    Data Access              │  Database, external services
├─────────────────────────────┤
│    Infrastructure           │  Logging, config, utilities
└─────────────────────────────┘
```

**Layer violations to detect:**
- Upper layers bypassing intermediate layers
- Lower layers depending on upper layers
- Cross-cutting concerns scattered everywhere

### Dependency Direction

Dependencies should point inward (toward the domain/business logic).

```
UI → Services → Domain ← Repository
                  ↑
              Infrastructure
```

**Bad:** Domain depends on database implementation
**Good:** Domain defines interfaces, infrastructure implements them

---

## Complexity Indicators

### Cyclomatic Complexity

Count of independent paths through code.

| Value | Assessment |
|-------|------------|
| 1-5 | Simple, low risk |
| 6-10 | Moderate, some risk |
| 11-20 | Complex, high risk |
| 21+ | Untestable, refactor |

**How to count:** Start at 1, add 1 for each:
- `if`, `else if`, `case`
- `for`, `while`, `do-while`
- `&&`, `||` in conditions
- `catch`, `except`
- Ternary operators

### Cognitive Complexity

How hard code is to understand (considers nesting).

| Value | Assessment |
|-------|------------|
| 0-10 | Easy to understand |
| 11-25 | Requires concentration |
| 26+ | Very difficult, split it |

---

## Code Smells (Universal)

### Long Function

**Symptoms:**
- >50 lines of code
- Multiple levels of abstraction
- Many local variables
- Hard to name accurately

**Fix:** Extract smaller functions with clear names

### Long Parameter List

**Symptoms:**
- >5 parameters
- Related parameters always passed together
- Boolean flags controlling behavior

**Fix:**
- Group related params into object
- Use builder/options pattern
- Split into multiple functions

### Feature Envy

**Symptoms:**
- Function uses more data from another class than its own
- Frequent accessor calls on other objects

**Fix:** Move function to the class whose data it uses

### Shotgun Surgery

**Symptoms:**
- One change requires many small changes across files
- Related code scattered in multiple places

**Fix:** Consolidate related code into one module

### Primitive Obsession

**Symptoms:**
- Using primitives instead of small objects (email as string, money as float)
- Groups of primitives that belong together

**Fix:** Create value objects/types

---

## Sources

- [Code Quality Metrics - Qodo](https://www.qodo.ai/blog/code-quality/)
- [Code Complexity Explained - Qodo](https://www.qodo.ai/blog/code-complexity/)
- [Clean Architecture - Uncle Bob](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
