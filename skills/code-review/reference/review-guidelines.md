# Code Review Reference

Consolidated guidelines for code review.

---

## Code Review Principles

### Prerequisites
- Psychological safety must never be threatened during review
- Review the code, never the person
- Maximize team output through the review process
- Be mindful of human psychology - choose words carefully, praise good work

### Review Purpose
Focus on **code quality**:
- Readability meets team standards
- Architecture follows team conventions
- Language best practices are followed
- Style guide compliance
- Linter/formatter rules respected
- Tests included for changes
- Documentation supplements code where needed
- CI passes

### Reviewer Guidelines

1. **Don't hold back on quality issues** - Small compromises quickly erode standards
2. **Praise good code** - Balance criticism with recognition
3. **Minimize round-trips**:
   - Be explicit about expectations
   - Use labels: `[must]` (blocking), `[q]` (question), `[nit]` (suggestion)
   - Explain WHY when requesting changes
   - Complete all feedback in one pass
   - Consider synchronous communication for complex discussions
4. **Automate repeated feedback** - Use linters instead of manual comments
5. **Respond quickly** - Within one business day maximum
6. **Request PR splits** - Target 100-200 lines for effective review

---

## Coding Quality Standards

### Goals
Maintain code quality to deliver features:
- **Faster** - Quick idea-to-delivery
- **More frequently** - Rapid improvement cycles
- **Higher quality** - Natural customer problem solving
- **Longer-term** - Smooth extensibility
- **Safer** - Minimal bugs, no security concerns

### Quality Checklist

- [ ] **Consistency** - Naming, patterns, logic match surrounding code
- [ ] **High cohesion, low coupling** - Changes don't require modifications elsewhere
- [ ] **Clear naming** - Unique, concise, descriptive identifiers
- [ ] **Testable without excessive mocking**
- [ ] **Tests verify implementation** - Appropriate coverage without duplication
- [ ] **Appropriate comments** - Document non-obvious decisions, all public APIs
- [ ] **YAGNI** - No unnecessary features or complexity
- [ ] **Style guide compliance**

### AI-Generated Code
AI-generated code is treated as written by the supervisor (PR author). The supervisor takes full responsibility.

---

## PR Guidelines

### Size
- Target: Merge within one day of branch creation
- Lines: ~100-200 (excluding auto-generated code)
- Split by concern, not by test/implementation

### PR Creation
- **Title**: Clear, concise summary
- **Description**: Brief overview, link to Jira/docs/Figma
- **Reviewers**: Usually 1 person (more dilutes attention)
- **Labels**: As needed per team conventions

### During Review
- **Don't reorder commits** after review starts (breaks diff viewing)
- Commits will be squash-merged anyway

---

## Frontend-Specific Guidelines

### React/JSX Rules

1. **Extract complex inline conditionals**: When a JSX prop contains complex conditional logic (e.g., ternary with multiple checks), extract it to a named handler function for readability.
   ```tsx
   // Bad: Complex inline conditional
   <ErrorView onClickRetry={hasError && retryFn ? retryFn : handleDefault} />

   // Good: Extract to named handler
   const handleRetry = useCallback(() => {
     if (hasError && retryFn) {
       retryFn();
     } else {
       handleDefault();
     }
   }, [hasError, retryFn, handleDefault]);

   <ErrorView onClickRetry={handleRetry} />
   ```

### CSS Rules

1. **Use modern CSS**:
   - `gap` instead of margin-top/left for spacing
   - Logical properties (`margin-inline`, `margin-block`)
   - `flex` and `grid` for layout

2. **Class naming**:
   - camelCase (CSS Modules compatibility)
   - Root element always named `root`
   - Name by concern (e.g., `userProfile`, `FooContainer`, `FooWrapper`)

3. **Dynamic styles**:
   - Prefer: HTML attributes (`data-*`, `aria-*`) → CSS variables → `style` prop
   - Only use `style` prop for truly dynamic values

### Testing Rules (Frontend)

#### MUST Follow

1. **Clear test intent**:
   ```tsx
   // Good: Intent is documented
   it("returns false for integers that are not natural numbers", () => {});

   // Bad: Requires domain knowledge to understand
   it("0 returns false", () => {});

   // Very Bad: Just code translation
   it("0 === false", () => {});
   ```

2. **Test specification, not implementation** - If implementation changes require test changes, question if you're testing the right thing

3. **No test dependencies** - Tests must pass in any order

4. **Always release test doubles** - Use `onTestFinished()` or RAII patterns

#### Testing Approach

| Code Type | Test Type |
|-----------|-----------|
| Pure business logic | Unit tests (1:1 coverage) |
| External integrations | Integration tests (Repository layer) |
| User-facing components | Component tests (form level, not individual inputs) |
| Hooks from components | Component tests (not hook tests) |

#### What NOT to Test
- Don't re-test lower-level logic at higher levels
- Don't test external module behavior
- Don't exhaustively test input variations at page level

---

## Review Labels

| Label | Meaning | Use When |
|-------|---------|----------|
| `[must]` | Required | Bugs, security issues, violations - blocks approval |
| `[q]` | Question | Intent unclear, needs clarification |
| `[nit]` | Suggestion | Style preferences, optional improvements |
