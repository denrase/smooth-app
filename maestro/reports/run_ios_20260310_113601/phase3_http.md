# Phase 3: HTTP Instrumentation

Validates that HTTP requests produce spans (via `SentryHttpClient` or auto-instrumentation).

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 3.1 | HTTP spans appear | PASS | Found 29 HTTP spans |
| 3.2 | GitHub/news feed fetches traced | PASS | Found 2 spans to raw.githubusercontent.com |
| 3.3 | SVG downloads traced | PASS | Found 8 spans to static.openfoodfacts.org |
| 3.4 | GitHub contributors fetch traced | MANUAL | Check for HTTP span to `api.github.com` |
