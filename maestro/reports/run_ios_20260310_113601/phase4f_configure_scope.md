# Phase 4f: `configureScope` Validation

Validates that `flow=scanning` tag is scoped to scan children only.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4f.1 | `flow=scanning` tag on scan children | MANUAL | Check tags in Sentry span detail |
| 4f.2 | `flow=scanning` NOT on unrelated spans | MANUAL | Verify search/background spans lack tag |
