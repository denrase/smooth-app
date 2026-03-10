## Android — Trace Links & Observations

> Platform-specific evidence for the [Validation Report](REPORT.md).

**Tested on:** Google Pixel 4a, Android 13 (API 33), debug mode.
**Entrypoint:** [`main_fdroid.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/android/main_fdroid.dart) (ZXing scanner, `scanner_ml_kit` disabled due to Xcode 26 arm64 issue)
**Flows:** 5/5 passed · 94 spans · 8 traces

---

### Maestro Setup

Running Maestro on a physical Android device required two workarounds (both automated in [`run_validation_android.sh`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/maestro/run_validation_android.sh)):

1. **TCP/IP mode:** Maestro 2.2.0 uses `dadb` (Java ADB library) to install its driver APKs, which fails on USB-connected physical devices. Switching the device to `adb tcpip 5555` and connecting via Wi-Fi (`adb connect <ip>:5555`) resolves this.
2. **App link approval:** `openLink` deep links open in Chrome by default on Android (debug builds can't verify domain ownership). Fixed by running `adb shell pm set-app-links --package org.openfoodfacts.scanner 2 all` after install to force the app as the default handler.

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
