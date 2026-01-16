---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# React Rules

- Avoid `React.FC` - use explicit return types (e.g., `const Foo = ({ bar }: Props): JSX.Element => ...`)
- Avoid hardcoding texts - use i18n libraries or other localization methods
