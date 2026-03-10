# Phase 1: Streaming Mode & Options

Validates that Sentry initializes with `SentryTraceLifecycle.streaming` and the new callbacks work.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 1.1 | Sentry initializes, spans appear | PASS | Found 127 spans |
| 1.2 | `beforeSendSpan` is called | PASS | Log lines present |
| 1.3 | Tags `store` and `scanner` on events | MANUAL | Check any event in Sentry |
| 1.4 | `beforeSend` gates on `_crashReports` | MANUAL | Toggle preference, verify filtering |
