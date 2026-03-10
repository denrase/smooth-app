## Android Validation Report

Instrumented [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) on branch [`denrase/smooth-app@sentry/smooth-app-span-first`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first) using SDK branch [`feat/span/native-app-start-v2`](https://github.com/getsentry/sentry-dart/pull/3534).

**Tested on:** Google Pixel 4a, Android 13 (API 33), debug mode.
**Sentry Project:** [denrase / smooth-app-span-first](https://sentry.io/organizations/denrase/performance/?project=4510980127784960)
**Entrypoint:** [`main_fdroid.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/android/main_fdroid.dart) (ZXing scanner, `scanner_ml_kit` disabled due to Xcode 26 arm64 issue)

### Instrumentation

Same as [iOS report](REPORT.md) — see that file for full instrumentation table and key files.

Auto-instrumented: TTID/TTFD, App Starts, Hive (`SentryHive`), HTTP (`SentryHttpClient`).
Manual spans: `product.scan`, `product.cache_lookup`, `product.fetch`, `product.load`, `product.search`, `product.search.decode`, `background_task.lifecycle`, `background_task.execute`.

5 [Maestro flows](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first/maestro) automated via [`run_validation_android.sh`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/maestro/run_validation_android.sh).

---

### Maestro Setup

Running Maestro on a physical Android device required two workarounds (both automated in the script):

1. **TCP/IP mode:** Maestro 2.2.0 uses `dadb` (Java ADB library) to install its driver APKs, which fails on USB-connected physical devices. Switching the device to `adb tcpip 5555` and connecting via Wi-Fi (`adb connect <ip>:5555`) resolves this.
2. **App link approval:** `openLink` deep links open in Chrome by default on Android (debug builds can't verify domain ownership). Fixed by running `adb shell pm set-app-links --package org.openfoodfacts.scanner 2 all` after install to force the app as the default handler.

---

### Results

All 5 Maestro flows passed. 90 spans captured in logs across 7 traces.

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
| `beforeSendSpan` fires on Android | ✅ 90 span log lines captured |
| App Start spans (Cold Start, Process Initialization, etc.) | ✅ 5 cold starts across 5 Maestro flows |
| Hive `openBox`/`openLazyBox` spans | ✅ 30 `openBox` + 15 `openLazyBox` (6 per launch × 5 launches) |
| `product.load` span from deep link | ✅ 2 instances — flows 03 and 05 ([trace](https://sentry.io/organizations/denrase/performance/trace/803e5c22b9264c73949df15cd2862f99/)) |
| HTTP spans for SVG downloads | ✅ 4 `GET static.openfoodfacts.org/...` spans |
| TTID/TTFD auto-instrumentation | ✅ `root /`, `root / initial display`, `_product_loader/:productId initial display` |
| `product.search` / `product.search.decode` | ✅ Confirmed in Sentry — [trace `ce4b02…`](https://sentry.io/organizations/denrase/performance/trace/ce4b02f5fc344d87a1279f3813f821bb/) shows `product.search` (27.6s) + `product.search.decode` (689ms). Originally missed due to Pixel 4a's slow debug-mode HTTP (~25s). |
| `product.scan`, `product.cache_lookup`, `product.fetch` | N/A — camera-only, not testable via Maestro |
| `background_task.lifecycle`, `background_task.execute` | N/A — requires OpenFoodFacts login |

All span types confirmed in Sentry via API (`dataset=spans`) — auto-instrumented (App Start, HTTP, Hive, TTID/TTFD) and manual (`product.load`, `product.search`, `product.search.decode`).

---

### Trace Links

| Trace | Spans | Flows |
|-------|-------|-------|
| [`ce4b02f5…`](https://sentry.io/organizations/denrase/performance/trace/ce4b02f5fc344d87a1279f3813f821bb/) | 18 | Flow 02 — `product.search` (27.6s), `product.search.decode` (689ms), Cold Start, Hive |
| [`546906a9…`](https://sentry.io/organizations/denrase/performance/trace/546906a9e1ca41869e98e74a8e702943/) | 16 | Flow 01 — Cold Start (10.5s), Hive openBox/openLazyBox × 9 |
| [`2d3202771…`](https://sentry.io/organizations/denrase/performance/trace/2d3202771fef4e4da35de98d6cc245da/) | 7 | Flow 03 — `product.load` (1.5s), HTTP × 4, TTID/TTFD |
| [`e7a8928c…`](https://sentry.io/organizations/denrase/performance/trace/e7a8928ca9d14f659aa329800c323484/) | 3 | Flow 05 — `product.load` (2.4s), TTID/TTFD |

---

### Android-Specific Observations

- **No behavioral differences from iOS.** All span types that could be triggered on both platforms behave identically — same hierarchy, same attributes, same status codes.
- **`SentrySpanStatusV2` renders as full enum name** in `debugPrint` (e.g. `SentrySpanStatusV2.ok` vs `ok` on iOS). No functional impact — just a `toString()` difference.
- **App Start spans are more verbose on Android.** `Process Initialization` and `App start to plugin registration` sub-spans provide finer-grained startup breakdown than iOS.

---

### Latest Run (2026-03-09 18:50–19:01)

Confirmed all spans via Sentry API (`dataset=spans` endpoint). Search spans verified end-to-end: code path → `RecordingSentrySpanV2` → `beforeSendSpan` log → Sentry ingestion.

Full reports: [`maestro/reports/run_android_20260309_165317/`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first/maestro/reports/run_android_20260309_165317)
