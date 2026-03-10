# Sentry Span-First Validation Report

**Run:** 20260310_113601
**Flows:** 01_app_launch 02_search_product 03_product_details 04_preferences 05_product_edit
**Spans:** 127 (125 ok, 2 error, 0 other)
**Traces:** 7

## Flow Results

| Flow | Status |
|------|--------|
| 01_app_launch | passed |
| 02_search_product | passed |
| 03_product_details | passed |
| 04_preferences | passed |
| 05_product_edit | passed |

## Trace Links

- [f7ba412a644a4ff88d7603ca3a3821e8](https://sentry.io/organizations/denrase/performance/trace/f7ba412a644a4ff88d7603ca3a3821e8/) — 20 spans
- [9d2325c5ea5041258fef9629fcb5f7fb](https://sentry.io/organizations/denrase/performance/trace/9d2325c5ea5041258fef9629fcb5f7fb/) — 20 spans
- [7f0125d5caa946e184db8020653f0ea7](https://sentry.io/organizations/denrase/performance/trace/7f0125d5caa946e184db8020653f0ea7/) — 18 spans
- [d2379c20fb0c4c9390ae1ef7405e9363](https://sentry.io/organizations/denrase/performance/trace/d2379c20fb0c4c9390ae1ef7405e9363/) — 20 spans
- [ba74d21de09641c2af3988c07df373b2](https://sentry.io/organizations/denrase/performance/trace/ba74d21de09641c2af3988c07df373b2/) — 12 spans
- [69e282ed260d4900bb3805238f06b6cc](https://sentry.io/organizations/denrase/performance/trace/69e282ed260d4900bb3805238f06b6cc/) — 21 spans
- [4f2255a34e3f410f8ad4cfcf968801f7](https://sentry.io/organizations/denrase/performance/trace/4f2255a34e3f410f8ad4cfcf968801f7/) — 16 spans

## Phase Reports

| Phase | File | Status |
|-------|------|--------|
| 1. Streaming Mode | [phase1_streaming.md](phase1_streaming.md) | 2/2 auto-passed, 2 manual |
| 2. Hive | [phase2_hive.md](phase2_hive.md) | 2/2 auto-passed, 2 manual |
| 3. HTTP | [phase3_http.md](phase3_http.md) | 3/3 auto-passed, manual remaining |
| 4a. Scanning | [phase4a_scanning.md](phase4a_scanning.md) | see file |
| 4b. Product Load | [phase4b_product_load.md](phase4b_product_load.md) | see file |
| 4c. Search | [phase4c_search.md](phase4c_search.md) | see file |
| 4d. Background | [phase4d_background.md](phase4d_background.md) | see file |
| 4e. Inactive Span | [phase4e_inactive_span.md](phase4e_inactive_span.md) | see file |
| 4f. configureScope | [phase4f_configure_scope.md](phase4f_configure_scope.md) | all manual |
| 5. Hierarchy | [phase5_hierarchy.md](phase5_hierarchy.md) | all manual |

## Files

| File | Description |
|------|-------------|
| [spans.md](spans.md) | All 127 captured spans (grouped + detailed) |
| [phase1_streaming.md](phase1_streaming.md) | Phase validation checks |
| [phase2_hive.md](phase2_hive.md) | Phase validation checks |
| [phase3_http.md](phase3_http.md) | Phase validation checks |
| [phase4a_scanning.md](phase4a_scanning.md) | Phase validation checks |
| [phase4b_product_load.md](phase4b_product_load.md) | Phase validation checks |
| [phase4c_search.md](phase4c_search.md) | Phase validation checks |
| [phase4d_background.md](phase4d_background.md) | Phase validation checks |
| [phase4e_inactive_span.md](phase4e_inactive_span.md) | Phase validation checks |
| [phase4f_configure_scope.md](phase4f_configure_scope.md) | Phase validation checks |
| [phase5_hierarchy.md](phase5_hierarchy.md) | Phase validation checks |
| [flutter_logs.txt](flutter_logs.txt) | Raw simulator logs |

---

[Sentry Dashboard](https://sentry.io/organizations/denrase/performance/?project=smooth-app-span-first)
