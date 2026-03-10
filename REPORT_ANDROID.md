## Android — Trace Links & Observations

> Platform-specific evidence for the [Validation Report](REPORT.md).

**Tested on:** Google Pixel 4a, Android 13 (API 33), debug mode.
**Entrypoint:** [`main_fdroid.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/android/main_fdroid.dart) (ZXing scanner, `scanner_ml_kit` disabled due to Xcode 26 arm64 issue)
**Flows:** 5/5 passed · 111 spans · 7 traces

---

### Maestro Setup

Running Maestro on a physical Android device required a workaround for driver APK installation (automated in [`run_validation_android.sh`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/maestro/run_validation_android.sh)):

1. **Driver APK installation:** Maestro 2.2.0 uses `dadb` (Java ADB library) to install its driver APKs, which fails on USB-connected physical devices. The driver APKs (`maestro-server.apk`, `maestro-app.apk`) were extracted from the Maestro JAR and installed manually via `adb install`. Alternatively, switching the device to `adb tcpip 5555` and connecting via Wi-Fi resolves this, but requires the Mac and device to be on the same reachable network.
2. **App link approval:** `openLink` deep links open in Chrome by default on Android (debug builds can't verify domain ownership). Fixed by running `adb shell pm set-app-links --package org.openfoodfacts.scanner 2 all` after install to force the app as the default handler.
3. **Maestro sleep syntax:** Maestro 2.2.0 removed the `sleep()` function from `evalScript`. Replaced with `runScript` using a JS file with a `Date.now()` busy-wait loop.

---

### Trace Links

| Trace | Spans | Description |
|-------|-------|-------------|
| [`be27b023…`](https://sentry.io/organizations/denrase/performance/trace/be27b02320c84274924ce1398e55234a/) | 16 | Flow 01 — Cold Start, Hive openBox/openLazyBox × 9 |
| [`82862726…`](https://sentry.io/organizations/denrase/performance/trace/8286272670624e9dabb06cbf3025ff7b/) | 19 | Flow 02 — `product.search` + `product.search.decode`, Cold Start, Hive, POST search.pl |
| [`49d36d87…`](https://sentry.io/organizations/denrase/performance/trace/49d36d871bf341a2b90ddd4447dcf5e7/) | 12 | Flow 03 — `product.load`, HTTP × 6 (API, folksonomy, robotoff, prices), TTID/TTFD |
| [`2f9975e8…`](https://sentry.io/organizations/denrase/performance/trace/2f9975e8d9494329adc32943017e4f12/) | 16 | Flow 05 — `product.load`, HTTP × 10 (API, SVG, folksonomy, robotoff, prices), TTID/TTFD |
| [`641eea67…`](https://sentry.io/organizations/denrase/performance/trace/641eea67e5684fe5bf97bbb58ccb9412/) | 16 | Flow 04 — Cold Start, Hive |

---

### Android-Specific Observations

- **No behavioral differences from iOS.** All span types behave identically — same hierarchy, same attributes, same status codes.
- **App start sub-spans are different.** Android shows `Process Initialization` and `App start to plugin registration`; iOS shows `Pre Runtime Init`, `UIKit init`, and `Runtime init to Pre Main initializers`.
- **Maestro `launchApp` behaviour:** On Android, each `launchApp` is a Cold Start (app fully terminated and restarted). All 5 launches were Cold Starts, compared to iOS (1 Cold + 4 Warm).
- **Search results confirmed via screenshot:** 141 products found for "nutella" — identical results to iOS, with product cards, images, and score badges visible in `02_04_search_results.png`.
- **Product details confirmed via screenshot:** Nutella 400g product page loaded via deep link, matching iOS exactly.
