# Android Validation — Session Status

## ✅ Full Suite Run — All Flows Passed, All Spans Confirmed in Sentry

### Run Details
- **Device:** Pixel 4a, Android 13 (API 33), debug mode
- **Entrypoint:** `main_fdroid.dart` (ZXing scanner)
- **Run time:** 2026-03-09 18:50–19:01 CET
- **All 5 flows passed** (01–05)

### Sentry Verification (via API: `dataset=spans`)

| Trace ID | Spans | Key Span | Duration |
|----------|-------|----------|----------|
| [`ce4b02...`](https://sentry.io/organizations/denrase/performance/trace/ce4b02f5fc344d87a1279f3813f821bb/) | 18 | `product.search` | 27.6s |
| | | `product.search.decode` | 689ms |
| [`546906...`](https://sentry.io/organizations/denrase/performance/trace/546906a9e1ca41869e98e74a8e702943/) | 16 | `Cold Start` | 10.5s |
| | | `db` (Hive openBox/openLazyBox) × 9 | 4–31ms |
| [`2d3202...`](https://sentry.io/organizations/denrase/performance/trace/2d3202771fef4e4da35de98d6cc245da/) | 7 | `product.load` | 1.5s |
| | | `http.client` × 4 | 0.5–1.6s |
| [`e7a892...`](https://sentry.io/organizations/denrase/performance/trace/e7a8928ca9d14f659aa329800c323484/) | 3 | `product.load` | 2.4s |

### Span Types Verified
- ✅ **Streaming mode** — `traceLifecycle: streaming` active
- ✅ **App start** — Cold Start, Process Initialization, First frame render
- ✅ **Hive DB** — openBox, openLazyBox spans (9 total)
- ✅ **Search** — product.search (27.6s) + product.search.decode (689ms)
- ✅ **Product load** — product.load via deep link (2 separate traces)
- ✅ **HTTP** — http.client spans (auto-instrumented)
- ✅ **Navigation** — ui.load, ui.load.initial_display spans
- ✅ **beforeSendSpan** — all spans logged via `[SentrySpanFirst]` debugPrint

### Previous "Missing Search Spans" Issue — RESOLVED

**Root cause:** Pixel 4a in debug mode takes ~25-30s for the search HTTP call. Previous run's log capture ended before search completed.

**Additional finding:** Flutter's search results page renders all product text via Semantics `accessibilityText` (not `text`), which Maestro's `visible` check cannot match. This made it impossible to detect when results loaded. Flows were updated to fire-and-forget with long waits between flows.

---

## Files Modified (Not Committed)

| File | Change |
|------|--------|
| `maestro/run_validation_android.sh` | Android validation runner |
| `maestro/01_app_launch.yaml` | Flow 1 — unchanged |
| `maestro/02_search_product.yaml` | Updated — fire-and-forget, no result detection |
| `maestro/03_product_details.yaml` | Updated — fire-and-forget deep link |
| `maestro/04_preferences.yaml` | Updated — 45s init timeout |
| `maestro/05_product_edit.yaml` | Updated — fire-and-forget deep link |
| `REPORT.md` | Updated with link to Android report |
| `REPORT_ANDROID.md` | Android validation report |
| `maestro/KNOWN_ISSUES.md` | debugPrint section for both platforms |
| `search_products_manager.dart` | Clean — debug prints added and reverted |
