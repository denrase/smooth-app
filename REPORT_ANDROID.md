## Android Validation Report

> See [general report](REPORT.md) for instrumentation details, API findings, and conclusions.

**Tested on:** Google Pixel 4a, Android 13 (API 33), debug mode.
**Entrypoint:** [`main_fdroid.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/android/main_fdroid.dart) (ZXing scanner, `scanner_ml_kit` disabled due to Xcode 26 arm64 issue)

---

### Maestro Setup

Running Maestro on a physical Android device required two workarounds (both automated in the script):

1. **TCP/IP mode:** Maestro 2.2.0 uses `dadb` (Java ADB library) to install its driver APKs, which fails on USB-connected physical devices. Switching the device to `adb tcpip 5555` and connecting via Wi-Fi (`adb connect <ip>:5555`) resolves this.
2. **App link approval:** `openLink` deep links open in Chrome by default on Android (debug builds can't verify domain ownership). Fixed by running `adb shell pm set-app-links --package org.openfoodfacts.scanner 2 all` after install to force the app as the default handler.

---

### Results

All 5 Maestro flows passed. 94 spans captured in logs across 8 traces.

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
| `ignoreSpans` and `beforeSendSpan` behave correctly | ✅ `beforeSendSpan` fired for all 94 spans |
| No spans unexpectedly dropped by ingest | ✅ All spans confirmed via Sentry API (`dataset=spans`) |
| Span hierarchies correct | ✅ Parent-child nesting verified. Same fire-and-forget orphaning as iOS (see [API Findings](REPORT.md#api-findings)) |
| `configureScope` delegates attributes to children | ✅ `span.setAttribute()` works correctly. Same note as iOS: `scope.setTag()` is not part of the span-first API. |
| App Start spans (Cold Start, sub-spans) | ✅ 5 Cold Starts (each Maestro `launchApp` = cold). Sub-spans: Process Initialization, Plugin registration |
| Hive `openBox`/`openLazyBox` spans | ✅ 9 per launch (3 openLazyBox + 6 openBox) |
| `product.search` / `product.search.decode` | ✅ Confirmed in Sentry — [trace `ce4b02…`](https://sentry.io/organizations/denrase/performance/trace/ce4b02f5fc344d87a1279f3813f821bb/) shows `product.search` (27.6s) + `product.search.decode` (689ms) |
| `product.load` span from deep link | ✅ 2 instances — flows 03 and 05 (1.5s, 2.4s) |
| HTTP spans | ✅ SVG downloads + API calls auto-instrumented |
| TTID/TTFD auto-instrumentation | ✅ `root /`, `root / initial display`, `_product_loader/:productId initial display` |
| `product.scan`, `product.cache_lookup`, `product.fetch` | N/A — camera-only, not testable via Maestro |
| `background_task.lifecycle`, `background_task.execute` | N/A — requires OpenFoodFacts login |

---

### Trace Links

| Trace | Spans | Description |
|-------|-------|-------------|
| [`ce4b02f5…`](https://sentry.io/organizations/denrase/performance/trace/ce4b02f5fc344d87a1279f3813f821bb/) | 18 | `product.search` (27.6s) + `product.search.decode` (689ms), Cold Start, Hive |
| [`546906a9…`](https://sentry.io/organizations/denrase/performance/trace/546906a9e1ca41869e98e74a8e702943/) | 16 | Flow 01 — Cold Start (10.5s), Hive openBox/openLazyBox × 9 |
| [`2d320277…`](https://sentry.io/organizations/denrase/performance/trace/2d3202771fef4e4da35de98d6cc245da/) | 7 | Flow 03 — `product.load` (1.5s), HTTP × 4, TTID/TTFD |
| [`e7a8928c…`](https://sentry.io/organizations/denrase/performance/trace/e7a8928ca9d14f659aa329800c323484/) | 3 | Flow 05 — `product.load` (2.4s), TTID/TTFD |

---

### Android-Specific Observations

- **No behavioral differences from iOS.** All span types behave identically — same hierarchy, same attributes, same status codes.
- **App start sub-spans are different.** Android shows `Process Initialization` and `App start to plugin registration`; iOS shows `Pre Runtime Init`, `UIKit init`, and `Runtime init to Pre Main initializers`.
- **Maestro `launchApp` behaviour:** On Android, each `launchApp` is a Cold Start (app fully terminated and restarted). On iOS it's a Warm Start.
- **Search HTTP latency:** ~25–28s on Pixel 4a in debug mode, comparable to iOS simulator (~20s). The OpenFoodFacts API is slow regardless of platform.
