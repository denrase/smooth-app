# Phase 4d: Background Task Spans

Validates `background_task.execute` span with `task_type` and `task_id` attributes.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4d.1 | `background_task.execute` span created | FAIL | Not found — edit flow may not trigger actual save |
| 4d.2 | `task_type` and `task_id` attributes | MANUAL | Click span in Sentry |
| 4d.3 | Error status on task failure | MANUAL | Disable network, trigger upload |
