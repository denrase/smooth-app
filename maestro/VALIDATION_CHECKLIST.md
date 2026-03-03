# Sentry Span-First Validation Checklist

## Setup

**Sentry Project:** `smooth-app-span-first`
**Sentry Dashboard:** https://sentry.io/organizations/sentry-sdks/performance/?project=4510980127784960
**Trace Explorer:** https://sentry.io/organizations/sentry-sdks/performance/trace/<TRACE_ID>/
**Span Details:** https://sentry.io/organizations/sentry-sdks/performance/trace/<TRACE_ID>/?node=span-<SPAN_ID>

> Replace `<TRACE_ID>` and `<SPAN_ID>` with values from the console output.
> Every span logs: `[SentrySpanFirst] Span: <name> (<status>) trace=<TRACE_ID> span=<SPAN_ID>`

### Automated Validation (Recommended)

```bash
# Run all flows with automatic log capture and report generation
./maestro/run_validation.sh

# Run specific flows only
./maestro/run_validation.sh 02           # just search
./maestro/run_validation.sh 02 03        # search + product details
```

The script will:
1. Start `flutter logs` in the background
2. Run each Maestro flow sequentially
3. Parse all `[SentrySpanFirst]` log lines
4. Auto-verify span existence and parent-child relationships (via shared trace IDs)
5. Generate a markdown report at `maestro/reports/report_<timestamp>.md` with clickable Sentry links

### Manual Flows (iOS Simulator)

```bash
# Run all flows
maestro test maestro/

# Run a single flow
maestro test maestro/02_search_product.yaml

# In a separate terminal, stream Flutter logs
flutter logs
```

Look for lines like:
```
[SentrySpanFirst] Span: product.scan (ok) trace=abc123 span=def456
```

Copy the `trace=` value and open:
`https://sentry.io/organizations/sentry-sdks/performance/trace/<paste-trace-id>/`

---

## Validation Checklist

### Phase 1: Streaming Mode & Options

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 1.1 | Sentry initializes with `traceLifecycle = streaming` | App launches without errors, spans appear in Sentry | [ ] |
| 1.2 | `beforeSendSpan` is called | Console shows `[SentrySpanFirst] Span:` log lines | [ ] |
| 1.3 | Tags `store` and `scanner` appear on events | Check any error event in Sentry for these tags | [ ] |
| 1.4 | `beforeSend` correctly gates on `_crashReports` | Toggle crash reporting preference, verify events are filtered | [ ] |

### Phase 2: Hive Instrumentation

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 2.1 | `SentryHive.init()` works | App boots, no Hive errors | [ ] |
| 2.2 | `openBox` / `openLazyBox` spans appear | Console shows spans like `openBox`, `openLazyBox` | [ ] |
| 2.3 | Box read/write operations create `db` spans | Search or scan a product, check for `db` spans with `db.system=flutter_hive` | [ ] |
| 2.4 | `registerAdapter` works via SentryHive | App boots, product data loads correctly | [ ] |

### Phase 3: HTTP Instrumentation

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 3.1 | `SentryHttpClient` creates HTTP spans | Search for a product, check for `http.client` spans in trace | [ ] |
| 3.2 | SVG downloads are traced | Navigate to a product with score badges, check for HTTP spans to `static.openfoodfacts.org` | [ ] |
| 3.3 | News feed fetch is traced | Launch app, check for HTTP span to `raw.githubusercontent.com` | [ ] |
| 3.4 | GitHub contributors fetch is traced | Open Settings > Contribute > Contributors, check for HTTP span to `api.github.com` | [ ] |

### Phase 4a: Product Scanning Spans

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4a.1 | `product.scan` span is created | Scan a barcode, check console for `product.scan` | [ ] |
| 4a.2 | `product.cache_lookup` is child of scan | Check trace view: `product.scan` → `product.cache_lookup` | [ ] |
| 4a.3 | `product.fetch` is child of scan | Scan unknown barcode, check: `product.scan` → `product.fetch` | [ ] |
| 4a.4 | `barcode` attribute is set | Click span in Sentry, verify `barcode` attribute | [ ] |
| 4a.5 | Error status on internet error | Disable network, scan barcode, check `product.fetch` has `error` status | [ ] |
| 4a.6 | `deadlineExceeded` on timeout | Slow network, check `product.cache_lookup` has `deadline_exceeded` | [ ] |

### Phase 4b: Product Loader Span

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4b.1 | `product.load` span is created | Open product via deep link or search, check for span | [ ] |
| 4b.2 | `barcode` attribute is set | Click span in Sentry, verify attribute | [ ] |
| 4b.3 | Error status on not found | Load nonexistent barcode, check `error` status | [ ] |

### Phase 4c: Search Spans

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4c.1 | `product.search` span is created | Run search flow, check console | [ ] |
| 4c.2 | `product.search.decode` is child | Check trace: `product.search` → `product.search.decode` | [ ] |
| 4c.3 | `query_type` attribute is set | Click span, verify `query_type` attribute (e.g. `live`) | [ ] |
| 4c.4 | HTTP span is child of search | Check trace: HTTP span nested under `product.search` | [ ] |

### Phase 4d: Background Task Spans

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4d.1 | `background_task.execute` span is created | Edit a product field, check console | [ ] |
| 4d.2 | `task_type` and `task_id` attributes set | Click span in Sentry, verify attributes | [ ] |
| 4d.3 | Error status on task failure | Disable network, trigger upload, check span status | [ ] |

### Phase 4e: `startInactiveSpan` Validation

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4e.1 | `background_task.lifecycle` span is created | Edit product, check console for lifecycle span | [ ] |
| 4e.2 | `background_task.execute` is child of lifecycle | Check trace view: `lifecycle` → `execute` | [ ] |
| 4e.3 | Lifecycle span duration > execute duration | In trace view, lifecycle should start earlier (at queue time) | [ ] |
| 4e.4 | Error propagates to lifecycle span | Fail a task, verify lifecycle span has `error` status | [ ] |

### Phase 4f: `configureScope` Validation

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 4f.1 | `flow=scanning` tag on `product.scan` children | Scan product, check `product.cache_lookup` / `product.fetch` tags | [ ] |
| 4f.2 | `flow=scanning` NOT on unrelated spans | Check `product.search` or `background_task.execute` — should not have tag | [ ] |

### Phase 5a: `ignoreSpans` Validation

| # | Check | How to verify | Status |
|---|-------|---------------|--------|
| 5a.1 | Ignored spans don't appear in Sentry | Add rule, trigger matching span, verify absence in UI | [ ] |
| 5a.2 | Non-ignored spans still appear | Other spans should be unaffected | [ ] |

### Phase 5c: Full Span Hierarchy

Open a trace in Sentry and verify the tree structure:

```
app.start
├── SentryHive openBox (×N)
├── SentryHive openLazyBox (×N)
└── ...

product.scan
├── product.cache_lookup
│   ├── db (Hive get)
│   └── http.client (fetch from server)
└── product.fetch
    └── http.client (API call)

product.search
├── http.client (search API)
└── product.search.decode

background_task.lifecycle
└── background_task.execute
    └── http.client (upload)
```

| # | Check | Status |
|---|-------|--------|
| 5c.1 | Scan hierarchy matches expected tree | [ ] |
| 5c.2 | Search hierarchy matches expected tree | [ ] |
| 5c.3 | Background task hierarchy matches expected tree | [ ] |
| 5c.4 | HTTP spans are children of the triggering operation | [ ] |
| 5c.5 | Hive `db` spans are children of the enclosing operation | [ ] |

---

## Trace Log

Record trace/span IDs from each test run for easy lookup.

| Timestamp | Flow | Trace ID | Sentry Link | Notes |
|-----------|------|----------|-------------|-------|
| | App Launch | | [link]() | |
| | Search | | [link]() | |
| | Product Details | | [link]() | |
| | Product Edit | | [link]() | |
| | Scan (if tested) | | [link]() | |

> Fill in trace IDs from `flutter logs` output and construct links:
> `https://sentry.io/organizations/sentry-sdks/performance/trace/<TRACE_ID>/`
