## iOS Validation Report

> See [general report](REPORT.md) for instrumentation details, API findings, and conclusions.

**Tested on:** iOS Simulator, iPhone 16 Pro, iOS 18.5, debug mode.
**Entrypoint:** [`main_ios.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/ios/main_ios.dart)

---

### Results

All 5 Maestro flows passed. 108 spans captured in logs across 7 traces.

| Flow | Status |
|------|--------|
| `01_app_launch` | ✅ passed |
| `02_search_product` | ✅ passed |
| `03_product_details` | ✅ passed |
| `04_preferences` | ✅ passed |
| `05_product_edit` | ✅ passed |

---

### Assertions

| Assertion | Result |
|-----------|--------|
| `ignoreSpans` and `beforeSendSpan` behave correctly | ✅ `beforeSendSpan` fired for all 108 spans |
| No spans unexpectedly dropped by ingest | ✅ Sentry dashboard confirms spans match local logs |
| Span hierarchies correct | ✅ Parent-child nesting verified in trace view. One exception: `product.fetch` orphaned due to fire-and-forget pattern (see [API Findings](REPORT.md#api-findings)) |
| `configureScope` delegates attributes to children | ✅ `span.setAttribute()` works correctly. Note: `scope.setTag()` is not part of the span-first API — only `setAttribute` is supported. |
| `startInactiveSpan` documented | ✅ Two real-world use cases found (see [API Findings](REPORT.md#api-findings)) |
| App Start spans (Cold/Warm Start, sub-spans) | ✅ 1 Cold + 4 Warm starts. iOS sub-spans: Pre Runtime Init, UIKit init, Runtime init |
| Hive `openBox`/`openLazyBox` spans | ✅ 9 per launch (3 openLazyBox + 6 openBox) |
| `product.search` / `product.search.decode` | ✅ Confirmed in Sentry — [trace `a184b72…`](https://sentry.io/organizations/denrase/performance/trace/a184b72268d846dfa30c2be2b5ef8226/) shows `product.search` (20.1s) + `product.search.decode` (84ms) |
| `product.load` span from deep link | ✅ 2 instances — flows 03 and 05 (649ms, 636ms) |
| HTTP spans | ✅ SVG downloads + API calls auto-instrumented |
| TTID/TTFD auto-instrumentation | ✅ `root /`, `root / initial display`, `_product_loader/:productId initial display` |
| `product.scan`, `product.cache_lookup`, `product.fetch` | N/A — camera-only, not testable via Maestro |
| `background_task.lifecycle`, `background_task.execute` | N/A — requires OpenFoodFacts login |

---

### Trace Links

| Trace | Spans | Description |
|-------|-------|-------------|
| [`a184b72…`](https://sentry.io/organizations/denrase/performance/trace/a184b72268d846dfa30c2be2b5ef8226/) | 20 | `product.search` (20.1s) + `product.search.decode` (84ms), Warm Start, Hive |
| [`6055867…`](https://sentry.io/organizations/denrase/performance/trace/6055867b5744464dbe733a62a2222eb0/) | 20 | Flow 01 — Cold Start, Hive openBox/openLazyBox, HTTP |
| [`58bed28…`](https://sentry.io/organizations/denrase/performance/trace/58bed28e28624468acadf5a69e0a8c1d/) | 7 | Flow 03 — `product.load` (649ms), HTTP × 4, TTID/TTFD |
| [`8ea4c93…`](https://sentry.io/organizations/denrase/performance/trace/8ea4c932f51145c6a93440a4b4810cba/) | 3 | Flow 05 — `product.load` (636ms), TTID/TTFD |

---

### iOS-Specific Observations

- **App start sub-spans** include iOS-specific phases: `Pre Runtime Init`, `Runtime init to Pre Main initializers`, `UIKit init`.
- **Maestro `launchApp` behaviour:** On iOS, `launchApp` terminates and re-creates the app (Warm Start). In-flight async operations (like search) can be killed if the next flow starts too soon. Requires 45s+ wait after search submission.
- **Search HTTP latency:** ~20s on iOS simulator in debug mode (OpenFoodFacts API), comparable to Android (~25s on Pixel 4a).
