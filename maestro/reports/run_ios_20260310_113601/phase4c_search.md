# Phase 4c: Search Spans

Validates `product.search` and `product.search.decode` spans.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4c.1 | `product.search` span created | PASS | [View trace](https://sentry.io/organizations/denrase/performance/trace/69e282ed260d4900bb3805238f06b6cc/) |
| 4c.2 | `product.search.decode` child of search | PASS | Same trace ID |
| 4c.3 | `query_type` attribute set | MANUAL | Click span, verify attribute |
| 4c.4 | HTTP span child of search | MANUAL | Check trace tree in Sentry |
