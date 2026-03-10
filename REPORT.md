## Validation Report

Instrumented [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) on branch [`denrase/smooth-app@sentry/smooth-app-span-first`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first) using SDK branch [`feat/span/native-app-start-v2`](https://github.com/getsentry/sentry-dart/pull/3534).

**Sentry Project:** [denrase / smooth-app-span-first](https://sentry.io/organizations/denrase/performance/?project=4510980127784960)

Platform-specific details:
- [iOS Validation Report](REPORT_IOS.md) — iPhone 16 Pro Simulator, iOS 18.5
- [Android Validation Report](REPORT_ANDROID.md) — Pixel 4a, Android 13

---

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

### Cross-Platform Comparison

| Aspect | iOS (iPhone 16 Pro Sim) | Android (Pixel 4a physical) |
|--------|------------------------|---------------------------|
| **Flows** | 5/5 passed | 5/5 passed |
| **Total spans (logs)** | 108 | 94 |
| **Traces** | 7 | 8 |
| **App start type** | 1 Cold + 4 Warm | 5 Cold (each `launchApp` = cold) |
| **App start sub-spans** | Pre Runtime Init, UIKit init, Runtime init | Process Initialization, Plugin registration |
| **Hive DB spans** | ✅ openBox/openLazyBox | ✅ openBox/openLazyBox |
| **product.search** | ✅ 20.1s | ✅ 27.6s |
| **product.search.decode** | ✅ 84ms | ✅ 689ms |
| **product.load** | ✅ 649ms, 636ms | ✅ 1.5s, 2.4s |
| **HTTP spans** | ✅ auto-instrumented | ✅ auto-instrumented |
| **TTID/TTFD** | ✅ root /, _product_loader/ | ✅ root /, _product_loader/ |
| **beforeSendSpan** | ✅ fires for all spans | ✅ fires for all spans |
| **Sentry API confirmed** | ✅ | ✅ |

**Key difference:** Maestro's `launchApp` on iOS terminates and re-creates the app (Warm Start), while on Android each `launchApp` is a fresh Cold Start. This affects how much wait time is needed between flows for in-flight async operations (like search) to complete.

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

### Conclusions

**1. `startSpan` — manual ending and naming:**

Two cases needed manual span lifetime control (fire-and-forget + spans outliving creation context). Both were solved with `startInactiveSpan`.

However, per the [Span API spec](https://develop.sentry.dev/sdk/telemetry/spans/span-api/), the **base** `startSpan` MUST return a span and MUST NOT auto-end — that's what the Dart SDK currently calls `startInactiveSpan`. The callback variant that auto-ends is an optional convenience API. The Dart SDK has these inverted: the convenience API got the `startSpan` name, and the spec-mandated base API is internal as `startInactiveSpan`.

The naming also conflates two concepts: the spec's `active` option controls **scope parenting** (whether new spans become children), not auto-ending. `startInactiveSpan` sounds like the span isn't started yet.

Recommendation: promote the base API to `Sentry.startSpan` (matching the spec) and give the callback variant a distinct name (e.g. `Sentry.startSpanWithCallback`), or align with the spec's single `startSpan` + `active` option.

**2. `startSpan` API split (`startSpan` / `startSpanSync`):** Not needed. The current `startSpan` uses `FutureOr<T>` so it already handles both sync and async callbacks in one API — sync callbacks return directly, async callbacks return a Future.
