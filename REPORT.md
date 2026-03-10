## Validation Report

Instrumented [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) on branch [`denrase/smooth-app@sentry/smooth-app-span-first`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first) using SDK branch [`feat/span/native-app-start-v2`](https://github.com/getsentry/sentry-dart/pull/3534).

**Sentry Project:** [denrase / smooth-app-span-first](https://sentry.io/organizations/denrase/performance/?project=4510980127784960)

Platform-specific evidence (trace links, setup details):
- [iOS Report](REPORT_IOS.md) — iPhone 16 Pro Simulator, iOS 18.5, debug mode
- [Android Report](REPORT_ANDROID.md) — Pixel 4a, Android 13, debug mode

---

### Instrumentation

Auto-instrumented: TTID/TTFD, App Starts, Hive (`SentryHive`), HTTP (`SentryHttpClient`).
Manual spans: `product.scan`, `product.cache_lookup`, `product.fetch`, `product.load`, `product.search`, `product.search.decode`, `background_task.lifecycle`, `background_task.execute`.

Key files:
- [`analytics_helper.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/helpers/analytics_helper.dart) — SDK init, `beforeSendSpan`, `ignoreSpans`
- [`continuous_scan_model.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/data_models/continuous_scan_model.dart) — `product.scan`, `product.cache_lookup`, `product.fetch`
- [`product_loader_page.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/pages/product/product_loader_page.dart) — `product.load`
- [`search_products_manager.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/query/search_products_manager.dart) — `product.search`, `product.search.decode`
- [`background_task_manager.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/background/background_task_manager.dart) — `background_task.lifecycle`, `background_task.execute`
- [`local_database.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/database/local_database.dart) — `SentryHive.init()`
- [`network_config.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/helpers/network_config.dart) — `SentryHttpClient`

### Automation

5 [Maestro flows](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first/maestro) + a dedicated [validation entrypoint](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/ios/main_ios_scan_validation.dart) for scan/background task paths. All 5 flows passed on both platforms.

| Flow | What it exercises |
|------|-------------------|
| `01_app_launch` | App Start, Hive openBox/openLazyBox, HTTP |
| `02_search_product` | `product.search`, `product.search.decode`, HTTP |
| `03_product_details` | `product.load` (deep link), HTTP, TTID/TTFD |
| `04_preferences` | Navigation, UI interaction |
| `05_product_edit` | `product.load` (deep link), TTID/TTFD |

---

### Assertions

These map to the [assertions from the issue](https://github.com/getsentry/sentry-dart/issues/3543#assertions-to-validate--tasks).

| # | Assertion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | `ignoreSpans` and `beforeSendSpan` behave correctly | ✅ | `beforeSendSpan` fired for all spans — 108 on iOS, 94 on Android. Configured in [`analytics_helper.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/helpers/analytics_helper.dart). |
| 2 | No spans unexpectedly dropped by ingest | ✅ | All spans confirmed in Sentry — dashboard match on iOS, API query (`dataset=spans`) on Android. |
| 3 | Span hierarchies correct | ✅ | Parent-child nesting verified in trace view on both platforms. One expected exception: `product.fetch` orphaned due to fire-and-forget pattern — see [API findings](#startspan-callback-doesnt-work-with-fire-and-forget). |
| 4 | `configureScope` delegates attributes to children | ✅ | `span.setAttribute()` works correctly inside `startSpan` callbacks. Note: `scope.setTag()` is **not** part of the span-first API — only `setAttribute` is supported. |
| 5 | `startInactiveSpan` documented | ✅ | Two real-world use cases found — see [API findings](#startspan-callback-doesnt-work-with-fire-and-forget). |
| 6 | The API is ergonomic | ⚠️ | Mostly yes. Two issues: `startInactiveSpan` is internal (had to use `Sentry.currentHub.startInactiveSpan`), and `SentryAttribute.string()` is verbose. Details below. |

---

### Span Coverage

All auto-instrumented and manual span types verified on both platforms. Numbers differ due to Maestro behaviour (iOS: warm restarts reuse state; Android: cold starts from scratch).

| Span type | iOS | Android | Notes |
|-----------|-----|---------|-------|
| **App Start** | ✅ 1 Cold + 4 Warm | ✅ 5 Cold | Sub-spans differ per platform (see [iOS](REPORT_IOS.md#ios-specific-observations), [Android](REPORT_ANDROID.md#android-specific-observations)) |
| **Hive DB** (openBox/openLazyBox) | ✅ 9 per launch | ✅ 9 per launch | |
| **product.search** | ✅ 20.1s | ✅ 27.6s | |
| **product.search.decode** | ✅ 84ms | ✅ 689ms | |
| **product.load** | ✅ 649ms, 636ms | ✅ 1.5s, 2.4s | Via deep link (flows 03, 05) |
| **HTTP** | ✅ | ✅ | SVG downloads + API calls |
| **TTID/TTFD** | ✅ | ✅ | `root /`, `_product_loader/:productId` |
| **beforeSendSpan** | ✅ all 108 spans | ✅ all 94 spans | |
| **product.scan / .cache_lookup / .fetch** | N/A | N/A | Camera-only, not testable via Maestro |
| **background_task.lifecycle / .execute** | N/A | N/A | Requires OpenFoodFacts login |

---

### APIs Under Test

| API | Status | Notes |
|-----|--------|-------|
| `Sentry.startSpan` | ✅ works well | Callback pattern with auto-ending and implicit nesting via zones. Used for `product.search`, `product.load`, `product.scan`. One limitation: doesn't work with fire-and-forget — see below. |
| `Sentry.configureScope` | ✅ works | `span.setAttribute()` correctly delegates to children. `scope.setTag()` is not part of span-first API. |
| `Sentry.currentHub.startInactiveSpan` | ✅ works, needs promotion | Still internal. Two real-world use cases found. **Should be promoted to `Sentry.startInactiveSpan`.** |
| `options.ignoreSpans` | ✅ works | Configured in `analytics_helper.dart`. |
| `options.beforeSendSpan` | ✅ works | Fired for every span on both platforms. |

**Additional APIs exercised:**
- `SentryHive` — drop-in replacement, worked perfectly
- `SentryHttpClient` — auto-instrumented all HTTP calls
- `SentrySpanStatusV2` — `error`, `deadlineExceeded`, `cancelled` all worked

---

### API Findings

#### `startSpan` callback doesn't work with fire-and-forget

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

#### `SentryAttribute.string()` is verbose

Used 10× across 4 files. A common operation shouldn't require this much ceremony.

---

### Open Questions

#### 1. `startSpan` — manual ending

> Note any cases where automatic span ending is insufficient.

Two cases needed manual span lifetime control:
- **Fire-and-forget** (`product.scan`): callback returns before child async work completes → children orphaned.
- **Spans outliving creation context** (`background_task.lifecycle`): span starts in one method, ends in a later callback.

Both were solved with `startInactiveSpan`.

However, per the [Span API spec](https://develop.sentry.dev/sdk/telemetry/spans/span-api/), the **base** `startSpan` MUST return a span and MUST NOT auto-end — that's what the Dart SDK currently calls `startInactiveSpan`. The callback variant that auto-ends is an optional convenience API. The Dart SDK has these inverted: the convenience API got the `startSpan` name, and the spec-mandated base API is internal as `startInactiveSpan`.

The naming also conflates two concepts: the spec's `active` option controls **scope parenting** (whether new spans become children), not auto-ending. `startInactiveSpan` sounds like the span isn't started yet.

**Recommendation:** promote the base API to `Sentry.startSpan` (matching the spec) and give the callback variant a distinct name (e.g. `Sentry.startSpanWithCallback`), or align with the spec's single `startSpan` + `active` option.

#### 2. `startSpan` API split (`startSpan` / `startSpanSync`)

> Note whether the current single API feels natural, or if the split would improve clarity.

**Not needed.** The current `startSpan` uses `FutureOr<T>` so it already handles both sync and async callbacks in one API — sync callbacks return directly, async callbacks return a Future.
