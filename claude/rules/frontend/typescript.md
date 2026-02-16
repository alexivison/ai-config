---
paths: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.jsx"]
---

# TypeScript Rules

- Prefer `type` over `interface`
- Avoid `any`/`unknown` — comment if necessary
- Use `readonly` for props
- Prefer discriminated unions over optional properties
- Avoid `default` in switch for union types (hides exhaustiveness)
- Names reflect purpose, not implementation: `isFeatureEnabled` not `thresholdCheck`
