## iOS — Trace Links & Observations

> Platform-specific evidence for the [Validation Report](REPORT.md).

**Tested on:** iOS Simulator, iPhone 16 Pro, iOS 18.5, debug mode.
**Entrypoint:** [`main_ios.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/ios/main_ios.dart)
**Flows:** 5/5 passed · 108 spans · 7 traces

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
