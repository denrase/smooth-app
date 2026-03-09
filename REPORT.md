## iOS Validation Report

Instrumented [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) on branch [`denrase/smooth-app@sentry/smooth-app-span-first`](https://github.com/denrase/smooth-app/tree/sentry/smooth-app-span-first) using SDK branch [`feat/span/native-app-start-v2`](https://github.com/getsentry/sentry-dart/pull/3534).

**Tested on:** iOS Simulator, iPhone 16 Pro, iOS 18.5, debug mode.
**Sentry Project:** [denrase / smooth-app-span-first](https://sentry.io/organizations/denrase/performance/?project=4510980127784960)

### Instrumentation

Auto-instrumented: TTID/TTFD, App Starts, Hive (`SentryHive`), HTTP (`SentryHttpClient`).
Manual spans: `product.scan`, `product.cache_lookup`, `product.fetch`, `product.load`, `product.search`, `product.search.decode`, `background_task.lifecycle`, `background_task.execute`.

5 Maestro flows + a dedicated validation entrypoint for scan/background task paths. See branch for details.

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

All span types confirmed in Sentry — auto-instrumented (App Start, HTTP, Hive) and manual (`product.scan`, `product.load`, `product.search`, `product.search.decode`). Only `background_task.execute` was never triggered (Maestro edit flow didn't produce an actual background save).

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

The app intentionally fire-and-forgets async work to keep the UI responsive:

```dart
Sentry.startSpan('product.scan', (span) async {
  _cacheOrLoadBarcode(barcode); // NOT awaited — intentional
  return true;
  // ← callback returns, span auto-ends before child work completes
});
// product.cache_lookup → sometimes nested (timing), product.fetch → orphaned
```

This is a common pattern in UI apps. `startSpan`'s auto-ending callback can't handle it — child spans get orphaned. This is a **second real-world case for `startInactiveSpan`** (alongside the `BackgroundTaskManager` pattern where a span outlives its creation context).

---

### Open Questions

**1. `startSpan` — manual ending:** `startInactiveSpan` covers both cases found (fire-and-forget + spans outliving creation context). Promote to `Sentry.startInactiveSpan`. A separate `startSpanManually` is nice-to-have but not blocking.

**2. `startSpan` API split (`startSpan` / `startSpanSync`):** All instrumentation used async callbacks — `startSpan` felt natural everywhere. No synchronous spans were needed. Low priority.

---

### Remaining

- [ ] **Android** — physical device, release mode

---

### Run Logs

Detailed Maestro run reports and flutter logs are in `maestro/reports/` (gitignored, local only):

- `run_20260309_102328/` — latest full run (all 5 flows)
  - `flutter_logs.txt` — raw `beforeSendSpan` output
  - `phase4a_scanning.md` through `phase4f_configure_scope.md` — per-phase validation
  - `summary.md` — run summary
- `run_20260309_101851/`, `run_20260309_100821/` — earlier runs
