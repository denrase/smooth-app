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
The validation scripts capture these logs via `xcrun simctl log stream`
(iOS) or `adb logcat` (Android). However, spans that complete during
active Maestro interaction (typing, tapping, scrolling) are consistently
**not** captured in local logs on either platform. Flutter throttles
`debugPrint` output (~1024 bytes/frame), and during busy UI frames the
log lines are dropped. Spans that fire during app startup or page
loading (lower UI activity) are reliably captured.

The spans are sent to Sentry regardless; this is a log-capture limitation,
not a span delivery issue. Always verify spans in the Sentry dashboard.

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
`run_validation_ios.sh` script already runs flows in order (01 → 02 → …), so this
is the default behavior. Do not run flow 02 in isolation without first clearing
app state.

### Root cause (suspected)

When search history is displayed, the Flutter `TextField` may lose keyboard
focus to the history list overlay, or the XCTest driver's `inputText` /
`pressKey` may not route to the correct first-responder. The iOS keyboard still
shows the search action button but Maestro's enter key event doesn't reach the
Flutter engine's `onSubmitted` callback.

---

## `evalScript: ${sleep()}` removed in Maestro 2.2.0 — RESOLVED

### Problem

Maestro 2.2.0 removed the `sleep()` JavaScript function from `evalScript`.
Flows using `evalScript: ${sleep(45000)}` fail with:
```
TypeError: undefined is not a function
```

### Fix

Replaced with `runScript` using a JS file containing a `Date.now()` busy-wait loop:
```yaml
- runScript:
    file: scripts/wait_45s.js
```

Wait scripts live in `maestro/scripts/`. While busy-waiting is not ideal, it
is the only reliable cross-platform delay mechanism in Maestro 2.2.0's GraalJS
engine (which lacks `setTimeout`, `Thread.sleep()`, and the old `sleep()` builtin).

---

## Android: Maestro driver APK installation over USB

### Problem

Maestro 2.2.0's `dadb` library fails to install driver APKs (`maestro-server.apk`,
`maestro-app.apk`) on USB-connected physical Android devices. The TCP/IP
workaround (`adb tcpip 5555`) requires Mac and device on the same reachable network.

### Workaround

Extract and manually install the driver APKs from the Maestro JAR:
```bash
cd /tmp && jar xf ~/.maestro/lib/maestro-client.jar maestro-server.apk maestro-app.apk
adb install maestro-server.apk
adb install maestro-app.apk
maestro test --no-reinstall-driver --device <USB_DEVICE_ID> flow.yaml
```
