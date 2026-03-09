# smooth-app (Sentry Span-First Validation Fork)

This is a fork of [openfoodfacts/smooth-app](https://github.com/openfoodfacts/smooth-app) instrumented with the Sentry Flutter SDK's **span-first** APIs for end-to-end validation.

**Tracking issue:** https://github.com/getsentry/sentry-dart/issues/3543

## Purpose

Validate the new Sentry Dart span APIs (`Sentry.startSpan`, `Sentry.configureScope`, `startInactiveSpan`, `ignoreSpans`, `beforeSendSpan`) against a realistic Flutter codebase. This fork exercises auto-instrumentation (Hive, HTTP, App Starts, TTID/TTFD) and manual span APIs to surface gaps or ergonomic issues before the APIs ship.

## Sentry Branch

All Sentry packages (`sentry`, `sentry_flutter`, `sentry_hive`) point to the `feat/span/native-app-start-v2` branch of `getsentry/sentry-dart` (see `pubspec.yaml`).

## Instrumentation

| Area | File(s) | What it tests |
|------|---------|---------------|
| Sentry init (streaming mode, callbacks) | `lib/helpers/analytics_helper.dart` | `traceLifecycle: streaming`, `beforeSendSpan`, `beforeSend`, `ignoreSpans`, `configureScope` |
| Hive DB | `lib/database/local_database.dart`, `lib/database/dao_*.dart` | `SentryHive.init()`, `openBox`/`openLazyBox` spans, `db` read/write spans |
| HTTP | `lib/helpers/network_config.dart`, `lib/cards/category_cards/svg_safe_network.dart`, `lib/data_models/newsfeed_provider.dart` | `SentryHttpClient` wrapping, HTTP spans as children of enclosing operations |
| Product scanning | `lib/data_models/continuous_scan_model.dart` | `product.scan` → `product.cache_lookup` / `product.fetch`, `configureScope` scoping |
| Product loading | `lib/pages/product/product_loader_page.dart` | `product.load` with barcode attribute, error status on not-found |
| Search | `lib/query/search_products_manager.dart` | `product.search` → `product.search.decode`, HTTP child spans |
| Background tasks | `lib/background/background_task_manager.dart` | `startInactiveSpan` for `background_task.lifecycle` → `background_task.execute` |

## Maestro Automation

Automated UI flows live in `maestro/`. They run against an iOS simulator and capture Sentry span logs for validation.

```bash
# Run all flows (builds app, clears state, runs 01-05, generates report)
./maestro/run_validation.sh

# Run specific flows
./maestro/run_validation.sh 02 03
```

**Important:** Flow 01 (`clearState: true`) must run before flows 02/03/05 — see `maestro/KNOWN_ISSUES.md`.

| Flow | What it triggers |
|------|-----------------|
| `01_app_launch` | App start spans, Hive init, cold start |
| `02_search_product` | `product.search`, `product.search.decode`, HTTP spans |
| `03_product_details` | `product.load`, `product.scan`, `configureScope` |
| `04_preferences` | Navigation spans, Hive read/write |
| `05_product_edit` | `background_task.lifecycle`, `background_task.execute` |

Reports are generated in `maestro/reports/`. See `maestro/VALIDATION_CHECKLIST.md` for the full checklist.

## Key Files

- `maestro/VALIDATION_CHECKLIST.md` — full validation checklist with Sentry links
- `maestro/KNOWN_ISSUES.md` — Maestro quirks and workarounds
- `maestro/run_validation.sh` — automated runner with log parsing and report generation
