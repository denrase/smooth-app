## iOS Validation Report

Instrumented [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) on branch [`denrase/smooth-app@sentry/smooth-app-span-first`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first) using SDK branch [`feat/span/native-app-start-v2`](https://github.com/getsentry/sentry-dart/pull/3534).

**Tested on:** iOS Simulator, iPhone 16 Pro, iOS 18.5, debug mode.
**Sentry Project:** [denrase / smooth-app-span-first](https://sentry.io/organizations/denrase/performance/?project=4510980127784960)

### Instrumentation

Auto-instrumented: TTID/TTFD, App Starts, Hive (`SentryHive`), HTTP (`SentryHttpClient`).
Manual spans: `product.scan`, `product.cache_lookup`, `product.fetch`, `product.load`, `product.search`, `product.search.decode`, `background_task.lifecycle`, `background_task.execute`.

5 [Maestro flows](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first/maestro) + a dedicated [validation entrypoint](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/ios/main_ios_scan_validation.dart) for scan/background task paths.

Key files:
- [`analytics_helper.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/helpers/analytics_helper.dart) — SDK init, `beforeSendSpan`, `ignoreSpans`
- [`continuous_scan_model.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/data_models/continuous_scan_model.dart) — `product.scan`, `product.cache_lookup`, `product.fetch`
- [`product_loader_page.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/pages/product/product_loader_page.dart) — `product.load`
- [`search_products_manager.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/query/search_products_manager.dart) — `product.search`, `product.search.decode`
- [`background_task_manager.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/background/background_task_manager.dart) — `background_task.lifecycle`, `background_task.execute`
- [`local_database.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/database/local_database.dart) — `SentryHive.init()`
- [`network_config.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/helpers/network_config.dart) — `SentryHttpClient`

---

### Assertions

| Assertion | Result |
|-----------|--------|
| `ignoreSpans` and `beforeSendSpan` behave correctly | ✅ `beforeSendSpan` fired for all 21 spans in validation run |
| No spans unexpectedly dropped by ingest | ✅ Sentry dashboard shows 21 spans — exact match ([trace](https://sentry.io/organizations/denrase/performance/trace/bd800c5ab6094685af3982d73e22510a/)) |
| Span hierarchies correct | ✅ Parent-child nesting verified in trace view. One exception: `product.fetch` orphaned due to fire-and-forget pattern (see below) |
| `configureScope` delegates attributes to children | ✅ `span.setAttribute()` works correctly (verified via API + UI). Note: `scope.setTag()` is not part of the span-first API — only `setAttribute` is supported. |
| `startInactiveSpan` documented | ✅ Two real-world use cases found (see below) |
| API is ergonomic | ✅ See details below |

All span types confirmed in Sentry — auto-instrumented (App Start, HTTP, Hive) and manual (`product.scan`, `product.load`, `product.search`, `product.search.decode`). `background_task.execute` was not observed — saving edits requires an OpenFoodFacts login which the Maestro flow doesn't have, so no background task is created. `background_task.lifecycle` (via `startInactiveSpan`) was observed.

---

### API Findings

**What worked well:**
- `startSpan` callback pattern — auto-ending and implicit nesting via zones
- `SentryHive` drop-in replacement
- `SentrySpanStatusV2` — `error`, `deadlineExceeded`, `cancelled` all worked

**What was awkward:**
- `startInactiveSpan` is internal — had to use `Sentry.currentHub.startInactiveSpan`. **Should be promoted to `Sentry.startInactiveSpan`.**
- `SentryAttribute.string(value)` is verbose for a common operation (used 10× across 4 files)

**⚠️ `startSpan` callback doesn't work with fire-and-forget patterns**

The app intentionally fire-and-forgets async work to keep the UI responsive ([`continuous_scan_model.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/data_models/continuous_scan_model.dart)):

```dart
Sentry.startSpan('product.scan', (span) async {
  _cacheOrLoadBarcode(barcode); // NOT awaited — intentional
  return true;
  // ← callback returns, span auto-ends before child work completes
});
// product.cache_lookup → sometimes nested (timing), product.fetch → orphaned
```

This is a common pattern in UI apps. `startSpan`'s auto-ending callback can't handle it — child spans get orphaned. This is a **second real-world case for `startInactiveSpan`** (alongside the [`BackgroundTaskManager`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/background/background_task_manager.dart) pattern where a span outlives its creation context).

---

### Open Questions

**1. `startSpan` — manual ending and naming:**

Two cases needed manual span lifetime control (fire-and-forget + spans outliving creation context). Both were solved with `startInactiveSpan`.

However, per the [Span API spec](https://develop.sentry.dev/sdk/telemetry/spans/span-api/), the **base** `startSpan` MUST return a span and MUST NOT auto-end — that's what the Dart SDK currently calls `startInactiveSpan`. The callback variant that auto-ends is an optional convenience API. The Dart SDK has these inverted: the convenience API got the `startSpan` name, and the spec-mandated base API is internal as `startInactiveSpan`.

The naming also conflates two concepts: the spec's `active` option controls **scope parenting** (whether new spans become children), not auto-ending. `startInactiveSpan` sounds like the span isn't started yet.

Recommendation: promote the base API to `Sentry.startSpan` (matching the spec) and give the callback variant a distinct name (e.g. `Sentry.startSpanWithCallback`), or align with the spec's single `startSpan` + `active` option.

**2. `startSpan` API split (`startSpan` / `startSpanSync`):** All instrumentation used async callbacks — `startSpan` felt natural everywhere. No synchronous spans were needed. Low priority.

---

### Remaining

- [ ] **Android** — physical device, release mode
