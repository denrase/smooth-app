# Phase 5: Hierarchy & Filtering

Validates span tree structure and `ignoreSpans` filtering.

## 5a. Filtering

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 5a.1 | Ignored spans filtered | MANUAL | Add ignoreSpan rule, verify absence |
| 5a.2 | Non-ignored spans unaffected | MANUAL | Other spans still appear |

## 5c. Span Hierarchy

Verify these hierarchies in the Sentry trace view:

- [Trace f7ba412a644a4ff88d7603ca3a3821e8](https://sentry.io/organizations/denrase/performance/trace/f7ba412a644a4ff88d7603ca3a3821e8/)
- [Trace 9d2325c5ea5041258fef9629fcb5f7fb](https://sentry.io/organizations/denrase/performance/trace/9d2325c5ea5041258fef9629fcb5f7fb/)
- [Trace 7f0125d5caa946e184db8020653f0ea7](https://sentry.io/organizations/denrase/performance/trace/7f0125d5caa946e184db8020653f0ea7/)
- [Trace d2379c20fb0c4c9390ae1ef7405e9363](https://sentry.io/organizations/denrase/performance/trace/d2379c20fb0c4c9390ae1ef7405e9363/)
- [Trace ba74d21de09641c2af3988c07df373b2](https://sentry.io/organizations/denrase/performance/trace/ba74d21de09641c2af3988c07df373b2/)
- [Trace 69e282ed260d4900bb3805238f06b6cc](https://sentry.io/organizations/denrase/performance/trace/69e282ed260d4900bb3805238f06b6cc/)
- [Trace 4f2255a34e3f410f8ad4cfcf968801f7](https://sentry.io/organizations/denrase/performance/trace/4f2255a34e3f410f8ad4cfcf968801f7/)

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 5c.1 | Scan hierarchy: scan -> cache_lookup / fetch | MANUAL | Open trace link |
| 5c.2 | Search hierarchy: search -> decode | MANUAL | Open trace link |
| 5c.3 | Background: lifecycle -> execute | MANUAL | Open trace link |
| 5c.4 | HTTP spans are children of operations | MANUAL | Open trace link |
| 5c.5 | Hive `db` spans are children of operations | MANUAL | Open trace link |
