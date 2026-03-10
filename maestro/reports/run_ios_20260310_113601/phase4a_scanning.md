# Phase 4a: Product Scanning Spans

Validates `product.scan`, `product.cache_lookup`, `product.fetch` spans and their hierarchy.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4a.1 | `product.scan` span created | FAIL | Not found |
| 4a.2 | `product.cache_lookup` child of scan | MANUAL | Span not found |
| 4a.3 | `product.fetch` child of scan | MANUAL | Span not found (may need unknown barcode) |
| 4a.4 | `barcode` attribute set | MANUAL | Click span in Sentry, verify `barcode` attribute |
| 4a.5 | Error status on internet error | MANUAL | Disable network, scan barcode |
| 4a.6 | `deadlineExceeded` on timeout | MANUAL | Slow network test |
