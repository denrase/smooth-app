# Phase 4e: `startInactiveSpan` Validation

Validates `background_task.lifecycle` as parent of `background_task.execute`.

| # | Check | Result | Detail |
|---|-------|--------|--------|
| 4e.1 | `background_task.lifecycle` span created | FAIL | Not found |
| 4e.2 | `execute` child of `lifecycle` | MANUAL | Depends on 4e.1 |
| 4e.3 | Lifecycle duration > execute duration | MANUAL | Compare spans in trace view |
| 4e.4 | Error propagates to lifecycle span | MANUAL | Fail a task, check status |
