## iOS — Trace Links & Observations

> Platform-specific evidence for the [Validation Report](REPORT.md).

**Tested on:** iOS Simulator, iPhone 16 Pro, iOS 18.5, debug mode.
**Entrypoint:** [`main_ios.dart`](https://github.com/denrase/smooth-app/blob/sentry/smooth-app-span-first/packages/smooth_app/lib/entrypoints/ios/main_ios.dart)
**Flows:** 5/5 passed · 127 spans · 7 traces

---

### Trace Links

| Trace | Spans | Description |
|-------|-------|-------------|
| [`d2379c20…`](https://sentry.io/organizations/denrase/performance/trace/d2379c20fb0c4c9390ae1ef7405e9363/) | 20 | Flow 01 — Cold Start, Hive openBox/openLazyBox × 9, HTTP (GitHub assets) |
| [`69e282ed…`](https://sentry.io/organizations/denrase/performance/trace/69e282ed260d4900bb3805238f06b6cc/) | 21 | Flow 02 — `product.search` + `product.search.decode`, Warm Start, Hive, POST search.pl |
| [`4f2255a3…`](https://sentry.io/organizations/denrase/performance/trace/4f2255a34e3f410f8ad4cfcf968801f7/) | 16 | Flow 03 — `product.load`, HTTP × 10 (API, SVG, robotoff, folksonomy, prices), TTID/TTFD |
| [`ba74d21d…`](https://sentry.io/organizations/denrase/performance/trace/ba74d21de09641c2af3988c07df373b2/) | 12 | Flow 05 — `product.load`, HTTP × 8, TTID/TTFD |
| [`9d2325c5…`](https://sentry.io/organizations/denrase/performance/trace/9d2325c5ea5041258fef9629fcb5f7fb/) | 20 | Flow 04 — Warm Start, Hive, SVG downloads |

---

### iOS-Specific Observations

- **App start sub-spans** include iOS-specific phases: `Pre Runtime Init`, `Runtime init to Pre Main initializers`, `UIKit init`, `App start to plugin registration`, `Before Sentry Init Setup`, `First frame render`.
- **Maestro `launchApp` behaviour:** On iOS, `launchApp` terminates and re-creates the app (Warm Start). 1 Cold Start (flow 01 with `clearState`) + 4 Warm Starts.
- **Search results confirmed via screenshot:** 141 products found for "nutella" — product cards with images, Nutri-Score badges, and green scores visible in `02_04_search_results.png`.
- **Product details confirmed via screenshot:** Nutella 400g product page loaded via deep link with Nutri-Score E, compatibility score, and edit button visible.
