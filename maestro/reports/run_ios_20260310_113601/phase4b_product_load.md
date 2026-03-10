# Phase 4b: Product Loader Span

Validates `product.load` span for deep link / product page loading.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4b.1 | `product.load` span created | PASS | [View trace](https://sentry.io/organizations/denrase/performance/trace/4f2255a34e3f410f8ad4cfcf968801f7/) |
| 4b.2 | `barcode` attribute set | MANUAL | Click span in Sentry |
| 4b.3 | Error status on not found | MANUAL | Load nonexistent barcode |
