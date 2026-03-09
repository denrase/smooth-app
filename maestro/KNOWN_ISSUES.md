# Maestro Known Issues

## Simulator Limitations

### Barcode scanning cannot be automated

`product.scan`, `product.cache_lookup`, and `product.fetch` spans are only
triggered by `ContinuousScanModel.onScan()` which is called from the camera
barcode scanner. The iOS simulator does not have a camera, so these spans
cannot be tested via Maestro. Test manually on a physical device.

### Background tasks require login

Saving product edits creates `BackgroundTaskDetails` which triggers
`background_task.lifecycle` and `background_task.execute` spans. However,
`BackgroundTaskDetails.addTask()` is guarded by `checkIfLoggedIn()` which
requires OpenFoodFacts credentials. The Maestro flow navigates to the edit
page but cannot complete the save without credentials. Test manually with a
logged-in session.

### `debugPrint` log capture is intermittent

The `beforeSendSpan` callback uses `debugPrint` to log span information.
The `run_validation.sh` script captures these logs via `xcrun simctl log
stream`. However, `debugPrint` output is intermittently captured by the
system log — some runs capture `product.search` spans, others don't. The
spans are sent to Sentry regardless; this is a log-capture limitation, not
a span delivery issue. Always verify spans in the Sentry dashboard.

---

## Flow 02: `tapOn: "maestro_search_bar"` — RESOLVED

### Problem (was)

`tapOn: "maestro_search_bar"` consistently tapped the **news card below** the
search bar instead of the search bar itself, due to the `CarouselSlider`
causing the accessibility bounds to be offset from the actual visual position.

### Fix

Wrapped the entire `_ScanSearchBar` `InkWell` in
`Semantics(label: 'maestro_search_bar', excludeSemantics: true)` instead of
relying on the child `Text('maestro_search_bar')`. This makes Maestro tap the
center of the full 48px search bar (the Semantics node) rather than the small
Text bounds. The `Text` was restored to the localized
`localizations.homepage_main_card_search_field_hint`.

**File:** `packages/smooth_app/lib/pages/scan/carousel/main_card/top_card/scan_search_card.dart`

---

## Flow 02: `pressKey: enter` unreliable with search history

### Problem

`pressKey: enter` does not trigger `TextInputAction.search` on the Flutter
`TextField` when search history is visible. The keyboard's blue search button
is shown but `pressKey: enter` has no effect — the search never executes and
the flow times out waiting for results.

This only happens when the app has prior search history (from previous Maestro
runs). On a clean app state (no history), `pressKey: enter` works correctly.

### Workaround

**Always run flow 01 (`clearState: true`) before flow 02.** The
`run_validation.sh` script already runs flows in order (01 → 02 → …), so this
is the default behavior. Do not run flow 02 in isolation without first clearing
app state.

### Root cause (suspected)

When search history is displayed, the Flutter `TextField` may lose keyboard
focus to the history list overlay, or the XCTest driver's `inputText` /
`pressKey` may not route to the correct first-responder. The iOS keyboard still
shows the search action button but Maestro's enter key event doesn't reach the
Flutter engine's `onSubmitted` callback.
