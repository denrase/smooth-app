#!/usr/bin/env zsh
#
# Re-exec as login shell to pick up the full environment (.zprofile, .zshrc)
# so that tools like CocoaPods/rbenv are available to Flutter.
if [[ -z "${_RUN_VALIDATION_LOGIN:-}" ]]; then
  export _RUN_VALIDATION_LOGIN=1
  exec zsh --login "$0" "$@"
fi
#
# Sentry Span-First Validation Runner
#
# Runs Maestro flows against an iOS simulator while capturing Flutter logs,
# then generates a validation report with auto-checks and Sentry links.
#
# Usage:
#   ./maestro/run_validation_ios.sh                  # run all flows
#   ./maestro/run_validation_ios.sh 02               # run only flow 02
#   ./maestro/run_validation_ios.sh 02 03            # run flows 02 and 03
#
# Prerequisites:
#   - iOS simulator booted
#   - maestro CLI installed
#   - flutter CLI available
#
# The script will automatically build and install the app if needed.
#
# Output:
#   reports/run_ios_YYYYMMDD_HHMMSS/
#     summary.md              — concise overview with links to phase reports
#     spans.md                — full captured spans table
#     phase1_streaming.md     — Phase 1 checks
#     phase2_hive.md          — Phase 2 checks (if flow 01 ran)
#     phase3_http.md          — Phase 3 checks
#     phase4a_scanning.md     — Phase 4a checks (if flow 03 ran)
#     phase4b_product_load.md — Phase 4b checks (if flow 03 ran)
#     phase4c_search.md       — Phase 4c checks (if flow 02 ran)
#     phase4d_background.md   — Phase 4d checks (if flow 05 ran)
#     phase4e_inactive_span.md— Phase 4e checks (if flow 05 ran)
#     phase4f_configure_scope.md — Phase 4f checks (if flow 03 ran)
#     phase5_hierarchy.md     — Phase 5 checks
#     flutter_logs.txt        — raw simulator logs

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="$SCRIPT_DIR/reports"
REPORT_DIR="$OUTPUT_DIR/run_ios_${TIMESTAMP}"
LOG_FILE="$REPORT_DIR/flutter_logs.txt"

SENTRY_BASE_URL="https://sentry.io/organizations/denrase/performance/trace"

# All available flows in order
ALL_FLOWS=(
  "01_app_launch"
  "02_search_product"
  "03_product_details"
  "04_preferences"
  "05_product_edit"
)

# ─── Helpers ────────────────────────────────────────────────────────────────

info()  { echo "▸ $*"; }
ok()    { echo "  ✓ $*"; }
fail()  { echo "  ✗ $*"; }
warn()  { echo "  ? $*"; }

cleanup() {
  for pid_var in BUILD_PID FLUTTER_LOGS_PID; do
    local pid="${(P)pid_var:-}"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

# ─── Prerequisites ─────────────────────────────────────────────────────────

missing=()
if ! command -v flutter &>/dev/null; then missing+=("flutter"); fi
if ! command -v maestro &>/dev/null; then
  # Check common install locations
  if [[ -x "$HOME/.maestro/bin/maestro" ]]; then
    export PATH="$HOME/.maestro/bin:$PATH"
  else
    missing+=("maestro")
  fi
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing required tools: ${missing[*]}"
  echo ""
  echo "Install instructions:"
  for tool in "${missing[@]}"; do
    case "$tool" in
      maestro)
        echo "  maestro: curl -Ls 'https://get.maestro.mobile.dev' | bash"
        echo "           Then: export PATH=\$HOME/.maestro/bin:\$PATH"
        ;;
      flutter)
        echo "  flutter: https://docs.flutter.dev/get-started/install"
        ;;
    esac
  done
  exit 1
fi

# ─── App bundle ID ────────────────────────────────────────────────────────

APP_ID="org.openfoodfacts.scanner"
FLUTTER_PROJECT="$PROJECT_DIR/packages/smooth_app"
APP_BUNDLE="$FLUTTER_PROJECT/build/ios/iphonesimulator/Runner.app"

# ─── Detect simulator ────────────────────────────────────────────────────

SIMULATOR_UDID=$(xcrun simctl list devices booted -j 2>/dev/null \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('state') == 'Booted':
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null) || true

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "Error: No booted iOS simulator found."
  echo "  Boot one with: xcrun simctl boot <device-udid>"
  echo "  List available: xcrun simctl list devices available"
  exit 1
fi

info "Using simulator: $SIMULATOR_UDID"

# ─── Clean install app ────────────────────────────────────────────────────

app_installed() {
  xcrun simctl listapps "$SIMULATOR_UDID" 2>/dev/null \
    | grep -q "$APP_ID"
}

install_app() {
  # Always start fresh: uninstall any existing version
  if app_installed; then
    info "Uninstalling previous app..."
    xcrun simctl uninstall "$SIMULATOR_UDID" "$APP_ID"
    ok "Previous app removed"
  fi

  if [[ ! -d "$FLUTTER_PROJECT" ]]; then
    echo "Error: Flutter project not found at $FLUTTER_PROJECT"
    exit 1
  fi

  # Use flutter run to build & install (handles CocoaPods correctly)
  info "Building and installing app via flutter run (this may take a few minutes)..."

  # Run flutter run in background; it builds, installs, and launches the app
  (cd "$FLUTTER_PROJECT" && flutter run -t lib/entrypoints/ios/main_ios.dart -d "$SIMULATOR_UDID" 2>&1 \
    | while IFS= read -r line; do echo "  │ $line"; done) < /dev/null &
  BUILD_PID=$!

  # Wait for the app to be installed (up to 5 minutes)
  waited=0
  while ! app_installed; do
    if [[ $waited -ge 300 ]]; then
      kill "$BUILD_PID" 2>/dev/null || true
      wait "$BUILD_PID" 2>/dev/null || true
      echo "Error: Timed out waiting for app to install (5 min)."
      echo "  Try running manually: cd packages/smooth_app && flutter run -t lib/entrypoints/ios/main_ios.dart"
      exit 1
    fi
    if ! kill -0 "$BUILD_PID" 2>/dev/null; then
      # Process exited — check one last time
      app_installed && break
      echo "Error: flutter run exited before app was installed."
      echo "  Try running manually: cd packages/smooth_app && flutter run -t lib/entrypoints/ios/main_ios.dart"
      exit 1
    fi
    sleep 5
    waited=$((waited + 5))
  done

  # App is installed — stop flutter run and terminate the app
  kill "$BUILD_PID" 2>/dev/null || true
  wait "$BUILD_PID" 2>/dev/null || true
  xcrun simctl terminate "$SIMULATOR_UDID" "$APP_ID" 2>/dev/null || true
  sleep 2

  ok "App built and installed"
}

install_app
echo ""

# ─── Determine which flows to run ──────────────────────────────────────────

flows_to_run=()
if [[ $# -eq 0 ]]; then
  flows_to_run=("${ALL_FLOWS[@]}")
else
  for arg in "$@"; do
    matched=false
    for flow in "${ALL_FLOWS[@]}"; do
      if [[ "$flow" == "${arg}"* || "$flow" == *"${arg}"* ]]; then
        flows_to_run+=("$flow")
        matched=true
        break
      fi
    done
    if [[ "$matched" == false ]]; then
      echo "Error: No flow matching '$arg'. Available: ${ALL_FLOWS[*]}"
      exit 1
    fi
  done
fi

# ─── Setup ─────────────────────────────────────────────────────────────────

mkdir -p "$REPORT_DIR"

info "Validation run: $TIMESTAMP"
info "Flows: ${flows_to_run[*]}"
info "Output: $REPORT_DIR"
echo ""

# Start log capture in background
# Note: `flutter logs` cannot capture debugPrint output when the app is
# launched externally (by Maestro) rather than via `flutter run`.
# Instead, use the simulator's log stream filtered to the Runner process.
info "Starting log capture..."
xcrun simctl spawn "$SIMULATOR_UDID" log stream \
  --level debug \
  --style compact \
  --predicate 'processImagePath CONTAINS "Runner"' \
  > "$LOG_FILE" 2>&1 &
FLUTTER_LOGS_PID=$!
sleep 2

if ! kill -0 "$FLUTTER_LOGS_PID" 2>/dev/null; then
  echo "Error: log stream failed to start. Is a simulator booted?"
  exit 1
fi

info "Log capture running (PID: $FLUTTER_LOGS_PID)"
echo ""

# ─── Run flows ─────────────────────────────────────────────────────────────

typeset -A FLOW_STATUS

for flow in "${flows_to_run[@]}"; do
  flow_file="$SCRIPT_DIR/${flow}.yaml"
  if [[ ! -f "$flow_file" ]]; then
    warn "Flow file not found: $flow_file — skipping"
    FLOW_STATUS[$flow]="skipped"
    continue
  fi

  # Onboarding is skipped in-app (hardcoded in main.dart)

  info "Running flow: $flow"
  if maestro test --device "$SIMULATOR_UDID" --test-output-dir "$REPORT_DIR" "$flow_file" 2>&1 | while IFS= read -r line; do echo "  │ $line"; done; then
    FLOW_STATUS[$flow]="passed"
    ok "Flow $flow completed"
  else
    FLOW_STATUS[$flow]="failed"
    fail "Flow $flow failed"
  fi

  # Wait for Sentry transport to flush (log batcher timeout is 5s)
  sleep 10
  echo ""
done

# Stop flutter logs
info "Stopping flutter logs..."
cleanup
sleep 1

# ─── Parse logs ────────────────────────────────────────────────────────────

info "Parsing span logs..."
echo ""

# Extract all span lines: [SentrySpanFirst] Span: <name> (<status>) trace=<trace_id> span=<span_id>
SPAN_NAMES=()
SPAN_STATUSES=()
SPAN_TRACE_IDS=()
SPAN_SPAN_IDS=()

while IFS= read -r line; do
  if [[ "$line" =~ '\[SentrySpanFirst\] Span: (.+) \(([^)]*)\) trace=([^ ]+) span=([^ ]+)' ]]; then
    SPAN_NAMES+=("${match[1]}")
    SPAN_STATUSES+=("${match[2]}")
    SPAN_TRACE_IDS+=("${match[3]}")
    SPAN_SPAN_IDS+=("${match[4]}")
  fi
done < "$LOG_FILE"

TOTAL_SPANS=${#SPAN_NAMES[@]}
info "Found $TOTAL_SPANS spans total"

# Collect unique trace IDs
typeset -A UNIQUE_TRACES
for tid in "${SPAN_TRACE_IDS[@]}"; do
  [[ -n "$tid" ]] && UNIQUE_TRACES[$tid]=1
done
info "Found ${#UNIQUE_TRACES} unique traces"
echo ""

# ─── Span helpers ──────────────────────────────────────────────────────────

span_exists() {
  local name="$1"
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" == "$name" ]] && return 0
  done
  return 1
}

span_exists_pattern() {
  local pattern="$1"
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" =~ $pattern ]] && return 0
  done
  return 1
}

spans_share_trace() {
  local name1="$1" name2="$2"
  typeset -A traces_for_name1
  for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
    [[ "${SPAN_NAMES[$i]}" == "$name1" ]] && traces_for_name1[${SPAN_TRACE_IDS[$i]}]=1
  done
  for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
    [[ "${SPAN_NAMES[$i]}" == "$name2" ]] && [[ -n "${traces_for_name1[${SPAN_TRACE_IDS[$i]}]:-}" ]] && return 0
  done
  return 1
}

get_trace_id() {
  local name="$1"
  for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
    [[ "${SPAN_NAMES[$i]}" == "$name" ]] && echo "${SPAN_TRACE_IDS[$i]}" && return 0
  done
  echo ""
}

count_spans() {
  local name="$1" count=0
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" == "$name" ]] && count=$((count + 1))
  done
  echo "$count"
}

check() {
  local id="$1" description="$2" result="$3" detail="${4:-}"
  if [[ "$result" == "pass" ]]; then
    echo "| $id | $description | PASS | $detail |"
  elif [[ "$result" == "fail" ]]; then
    echo "| $id | $description | FAIL | $detail |"
  else
    echo "| $id | $description | MANUAL | $detail |"
  fi
}

# Check if a flow was included in this run
flow_ran() {
  local flow="$1"
  for f in "${flows_to_run[@]}"; do
    [[ "$f" == "$flow" ]] && return 0
  done
  return 1
}

# Count HTTP spans (GET/POST/PUT/DELETE/PATCH/HEAD URLs)
count_http_spans() {
  local count=0
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" =~ "^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS) " ]] && count=$((count + 1))
  done
  echo "$count"
}

# Count status categories
count_statuses() {
  OK_COUNT=0; ERROR_COUNT=0; OTHER_COUNT=0
  for st in "${SPAN_STATUSES[@]}"; do
    case "$st" in
      *ok*|*Ok*) OK_COUNT=$((OK_COUNT + 1)) ;;
      *error*|*Error*|*cancelled*|*Cancelled*|*deadline*|*Deadline*) ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
      *) OTHER_COUNT=$((OTHER_COUNT + 1)) ;;
    esac
  done
}

# ─── Generate reports ─────────────────────────────────────────────────────

info "Generating reports..."

# Track which phase files we generate (for the summary)
PHASE_FILES=()
PHASE_SUMMARIES=()

# ── spans.md ──────────────────────────────────────────────────────────────

{
echo "# Captured Spans"
echo ""
echo "**Run:** $TIMESTAMP | **Total:** $TOTAL_SPANS | **Traces:** ${#UNIQUE_TRACES}"
echo ""

# Group spans by name with counts
typeset -A SPAN_GROUP_COUNT
typeset -A SPAN_GROUP_FIRST_IDX
for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
  name="${SPAN_NAMES[$i]}"
  SPAN_GROUP_COUNT[$name]=$(( ${SPAN_GROUP_COUNT[$name]:-0} + 1 ))
  [[ -z "${SPAN_GROUP_FIRST_IDX[$name]:-}" ]] && SPAN_GROUP_FIRST_IDX[$name]=$i
done

echo "## Span Summary"
echo ""
echo "| Span Name | Count | Status | Trace |"
echo "|-----------|-------|--------|-------|"
for name in "${(k)SPAN_GROUP_FIRST_IDX[@]}"; do
  idx="${SPAN_GROUP_FIRST_IDX[$name]}"
  tid="${SPAN_TRACE_IDS[$idx]}"
  span_status="${SPAN_STATUSES[$idx]}"
  count="${SPAN_GROUP_COUNT[$name]}"
  echo "| \`$name\` | $count | $span_status | [view]($SENTRY_BASE_URL/$tid/) |"
done
echo ""

echo "## All Spans (detailed)"
echo ""
echo "| # | Span Name | Status | Trace ID | Span ID |"
echo "|---|-----------|--------|----------|---------|"
for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
  tid="${SPAN_TRACE_IDS[$i]}"
  sid="${SPAN_SPAN_IDS[$i]}"
  echo "| $i | \`${SPAN_NAMES[$i]}\` | ${SPAN_STATUSES[$i]} | \`${tid[1,12]}…\` | \`${sid[1,12]}…\` |"
done
echo ""

echo "## Trace Links"
echo ""
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  trace_count=0
  for (( i = 1; i <= ${#SPAN_TRACE_IDS[@]}; i++ )); do
    [[ "${SPAN_TRACE_IDS[$i]}" == "$tid" ]] && trace_count=$((trace_count + 1))
  done
  echo "- [$tid]($SENTRY_BASE_URL/$tid/) — $trace_count spans"
done
} > "$REPORT_DIR/spans.md"

# ── Phase 1: Streaming Mode ──────────────────────────────────────────────

{
echo "# Phase 1: Streaming Mode & Options"
echo ""
echo "Validates that Sentry initializes with \`SentryTraceLifecycle.streaming\` and the new callbacks work."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

p1_pass=0; p1_total=0

p1_total=$((p1_total + 1))
if [[ $TOTAL_SPANS -gt 0 ]]; then
  check "1.1" "Sentry initializes, spans appear" "pass" "Found $TOTAL_SPANS spans"
  p1_pass=$((p1_pass + 1))
else
  check "1.1" "Sentry initializes, spans appear" "fail" "No spans captured"
fi

p1_total=$((p1_total + 1))
if [[ $TOTAL_SPANS -gt 0 ]]; then
  check "1.2" "\`beforeSendSpan\` is called" "pass" "Log lines present"
  p1_pass=$((p1_pass + 1))
else
  check "1.2" "\`beforeSendSpan\` is called" "fail" "No log lines"
fi

check "1.3" "Tags \`store\` and \`scanner\` on events" "manual" "Check any event in Sentry"
check "1.4" "\`beforeSend\` gates on \`_crashReports\`" "manual" "Toggle preference, verify filtering"
} > "$REPORT_DIR/phase1_streaming.md"
PHASE_FILES+=("phase1_streaming.md")
PHASE_SUMMARIES+=("1. Streaming Mode|phase1_streaming.md|$p1_pass/$p1_total auto-passed, 2 manual")

# ── Phase 2: Hive Instrumentation ────────────────────────────────────────

{
echo "# Phase 2: Hive Instrumentation"
echo ""
echo "Validates \`SentryHive\` replacement produces \`openBox\`/\`openLazyBox\` and \`db\` spans."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

p2_pass=0; p2_total=0

p2_total=$((p2_total + 1))
if span_exists_pattern "openBox|SentryHive"; then
  hive_count=0
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" =~ "openBox|openLazyBox|SentryHive" ]] && hive_count=$((hive_count + 1))
  done
  check "2.1" "\`SentryHive.init()\` works" "pass" "App booted, Hive spans present"
  p2_pass=$((p2_pass + 1))
  p2_total=$((p2_total + 1))
  check "2.2" "\`openBox\`/\`openLazyBox\` spans appear" "pass" "Found $hive_count Hive-related spans"
  p2_pass=$((p2_pass + 1))
else
  check "2.1" "\`SentryHive.init()\` works" "manual" "No Hive spans detected — check if app booted"
  p2_total=$((p2_total + 1))
  check "2.2" "\`openBox\`/\`openLazyBox\` spans appear" "fail" "No openBox/openLazyBox spans found"
fi

if span_exists_pattern "^db$|^db\."; then
  check "2.3" "Box read/write create \`db\` spans" "pass" "Found db spans"
else
  check "2.3" "Box read/write create \`db\` spans" "manual" "No \`db\` spans found — check trace in Sentry"
fi

check "2.4" "\`registerAdapter\` works via SentryHive" "manual" "Verify product data loads correctly"
} > "$REPORT_DIR/phase2_hive.md"
PHASE_FILES+=("phase2_hive.md")
PHASE_SUMMARIES+=("2. Hive|phase2_hive.md|$p2_pass/$p2_total auto-passed, 2 manual")

# ── Phase 3: HTTP Instrumentation ────────────────────────────────────────

HTTP_COUNT=$(count_http_spans)

{
echo "# Phase 3: HTTP Instrumentation"
echo ""
echo "Validates that HTTP requests produce spans (via \`SentryHttpClient\` or auto-instrumentation)."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

p3_pass=0; p3_total=0

p3_total=$((p3_total + 1))
if [[ "$HTTP_COUNT" -gt 0 ]]; then
  check "3.1" "HTTP spans appear" "pass" "Found $HTTP_COUNT HTTP spans"
  p3_pass=$((p3_pass + 1))
else
  check "3.1" "HTTP spans appear" "fail" "No HTTP spans found (looked for GET/POST/... patterns)"
fi

# Check for specific URLs
github_count=0; off_count=0
for sn in "${SPAN_NAMES[@]}"; do
  [[ "$sn" == *"raw.githubusercontent.com"* ]] && github_count=$((github_count + 1))
  [[ "$sn" == *"static.openfoodfacts.org"* ]] && off_count=$((off_count + 1))
done

if [[ "$github_count" -gt 0 ]]; then
  check "3.2" "GitHub/news feed fetches traced" "pass" "Found $github_count spans to raw.githubusercontent.com"
  p3_total=$((p3_total + 1)); p3_pass=$((p3_pass + 1))
else
  check "3.2" "GitHub/news feed fetches traced" "manual" "Check for HTTP spans to \`raw.githubusercontent.com\`"
fi

if [[ "$off_count" -gt 0 ]]; then
  check "3.3" "SVG downloads traced" "pass" "Found $off_count spans to static.openfoodfacts.org"
  p3_total=$((p3_total + 1)); p3_pass=$((p3_pass + 1))
else
  check "3.3" "SVG downloads traced" "manual" "Check for HTTP spans to \`static.openfoodfacts.org\` in Sentry"
fi

check "3.4" "GitHub contributors fetch traced" "manual" "Check for HTTP span to \`api.github.com\`"
} > "$REPORT_DIR/phase3_http.md"
PHASE_FILES+=("phase3_http.md")
PHASE_SUMMARIES+=("3. HTTP|phase3_http.md|$p3_pass/$p3_total auto-passed, manual remaining")

# ── Phase 4a: Product Scanning ────────────────────────────────────────────

if flow_ran "03_product_details"; then
{
echo "# Phase 4a: Product Scanning Spans"
echo ""
echo "Validates \`product.scan\`, \`product.cache_lookup\`, \`product.fetch\` spans and their hierarchy."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "product.scan"; then
  tid=$(get_trace_id "product.scan")
  check "4a.1" "\`product.scan\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4a.1" "\`product.scan\` span created" "fail" "Not found"
fi

if span_exists "product.cache_lookup"; then
  if spans_share_trace "product.scan" "product.cache_lookup"; then
    check "4a.2" "\`product.cache_lookup\` child of scan" "pass" "Same trace ID"
  else
    check "4a.2" "\`product.cache_lookup\` child of scan" "manual" "Different trace IDs — check hierarchy"
  fi
else
  check "4a.2" "\`product.cache_lookup\` child of scan" "manual" "Span not found"
fi

if span_exists "product.fetch"; then
  if spans_share_trace "product.scan" "product.fetch"; then
    check "4a.3" "\`product.fetch\` child of scan" "pass" "Same trace ID"
  else
    check "4a.3" "\`product.fetch\` child of scan" "manual" "Different trace IDs — check hierarchy"
  fi
else
  check "4a.3" "\`product.fetch\` child of scan" "manual" "Span not found (may need unknown barcode)"
fi

check "4a.4" "\`barcode\` attribute set" "manual" "Click span in Sentry, verify \`barcode\` attribute"
check "4a.5" "Error status on internet error" "manual" "Disable network, scan barcode"
check "4a.6" "\`deadlineExceeded\` on timeout" "manual" "Slow network test"
} > "$REPORT_DIR/phase4a_scanning.md"
PHASE_FILES+=("phase4a_scanning.md")
PHASE_SUMMARIES+=("4a. Scanning|phase4a_scanning.md|see file")
fi

# ── Phase 4b: Product Loader ─────────────────────────────────────────────

if flow_ran "03_product_details"; then
{
echo "# Phase 4b: Product Loader Span"
echo ""
echo "Validates \`product.load\` span for deep link / product page loading."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "product.load"; then
  tid=$(get_trace_id "product.load")
  check "4b.1" "\`product.load\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4b.1" "\`product.load\` span created" "fail" "Not found"
fi

check "4b.2" "\`barcode\` attribute set" "manual" "Click span in Sentry"
check "4b.3" "Error status on not found" "manual" "Load nonexistent barcode"
} > "$REPORT_DIR/phase4b_product_load.md"
PHASE_FILES+=("phase4b_product_load.md")
PHASE_SUMMARIES+=("4b. Product Load|phase4b_product_load.md|see file")
fi

# ── Phase 4c: Search ─────────────────────────────────────────────────────

if flow_ran "02_search_product"; then
{
echo "# Phase 4c: Search Spans"
echo ""
echo "Validates \`product.search\` and \`product.search.decode\` spans."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "product.search"; then
  tid=$(get_trace_id "product.search")
  check "4c.1" "\`product.search\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4c.1" "\`product.search\` span created" "fail" "Not found"
fi

if span_exists "product.search.decode"; then
  if spans_share_trace "product.search" "product.search.decode"; then
    check "4c.2" "\`product.search.decode\` child of search" "pass" "Same trace ID"
  else
    check "4c.2" "\`product.search.decode\` child of search" "manual" "Check hierarchy"
  fi
else
  check "4c.2" "\`product.search.decode\` child of search" "fail" "Span not found"
fi

check "4c.3" "\`query_type\` attribute set" "manual" "Click span, verify attribute"
check "4c.4" "HTTP span child of search" "manual" "Check trace tree in Sentry"
} > "$REPORT_DIR/phase4c_search.md"
PHASE_FILES+=("phase4c_search.md")
PHASE_SUMMARIES+=("4c. Search|phase4c_search.md|see file")
fi

# ── Phase 4d: Background Tasks ───────────────────────────────────────────

if flow_ran "05_product_edit"; then
{
echo "# Phase 4d: Background Task Spans"
echo ""
echo "Validates \`background_task.execute\` span with \`task_type\` and \`task_id\` attributes."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "background_task.execute"; then
  tid=$(get_trace_id "background_task.execute")
  check "4d.1" "\`background_task.execute\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4d.1" "\`background_task.execute\` span created" "fail" "Not found — edit flow may not trigger actual save"
fi

check "4d.2" "\`task_type\` and \`task_id\` attributes" "manual" "Click span in Sentry"
check "4d.3" "Error status on task failure" "manual" "Disable network, trigger upload"
} > "$REPORT_DIR/phase4d_background.md"
PHASE_FILES+=("phase4d_background.md")
PHASE_SUMMARIES+=("4d. Background|phase4d_background.md|see file")
fi

# ── Phase 4e: startInactiveSpan ──────────────────────────────────────────

if flow_ran "05_product_edit"; then
{
echo "# Phase 4e: \`startInactiveSpan\` Validation"
echo ""
echo "Validates \`background_task.lifecycle\` as parent of \`background_task.execute\`."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "background_task.lifecycle"; then
  tid=$(get_trace_id "background_task.lifecycle")
  check "4e.1" "\`background_task.lifecycle\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
  if spans_share_trace "background_task.lifecycle" "background_task.execute"; then
    check "4e.2" "\`execute\` child of \`lifecycle\`" "pass" "Same trace ID"
  else
    check "4e.2" "\`execute\` child of \`lifecycle\`" "manual" "Check trace"
  fi
else
  check "4e.1" "\`background_task.lifecycle\` span created" "fail" "Not found"
  check "4e.2" "\`execute\` child of \`lifecycle\`" "manual" "Depends on 4e.1"
fi

check "4e.3" "Lifecycle duration > execute duration" "manual" "Compare spans in trace view"
check "4e.4" "Error propagates to lifecycle span" "manual" "Fail a task, check status"
} > "$REPORT_DIR/phase4e_inactive_span.md"
PHASE_FILES+=("phase4e_inactive_span.md")
PHASE_SUMMARIES+=("4e. Inactive Span|phase4e_inactive_span.md|see file")
fi

# ── Phase 4f: configureScope ─────────────────────────────────────────────

if flow_ran "03_product_details"; then
{
echo "# Phase 4f: \`configureScope\` Validation"
echo ""
echo "Validates that \`flow=scanning\` tag is scoped to scan children only."
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"
check "4f.1" "\`flow=scanning\` tag on scan children" "manual" "Check tags in Sentry span detail"
check "4f.2" "\`flow=scanning\` NOT on unrelated spans" "manual" "Verify search/background spans lack tag"
} > "$REPORT_DIR/phase4f_configure_scope.md"
PHASE_FILES+=("phase4f_configure_scope.md")
PHASE_SUMMARIES+=("4f. configureScope|phase4f_configure_scope.md|all manual")
fi

# ── Phase 5: Hierarchy & Filtering ───────────────────────────────────────

{
echo "# Phase 5: Hierarchy & Filtering"
echo ""
echo "Validates span tree structure and \`ignoreSpans\` filtering."
echo ""
echo "## 5a. Filtering"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"
check "5a.1" "Ignored spans filtered" "manual" "Add ignoreSpan rule, verify absence"
check "5a.2" "Non-ignored spans unaffected" "manual" "Other spans still appear"
echo ""

echo "## 5c. Span Hierarchy"
echo ""
echo "Verify these hierarchies in the Sentry trace view:"
echo ""
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  echo "- [Trace $tid]($SENTRY_BASE_URL/$tid/)"
done
echo ""

echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if flow_ran "03_product_details"; then
  check "5c.1" "Scan hierarchy: scan -> cache_lookup / fetch" "manual" "Open trace link"
else
  check "5c.1" "Scan hierarchy" "manual" "N/A — flow 03 not run"
fi

if flow_ran "02_search_product"; then
  check "5c.2" "Search hierarchy: search -> decode" "manual" "Open trace link"
else
  check "5c.2" "Search hierarchy" "manual" "N/A — flow 02 not run"
fi

if flow_ran "05_product_edit"; then
  check "5c.3" "Background: lifecycle -> execute" "manual" "Open trace link"
else
  check "5c.3" "Background task hierarchy" "manual" "N/A — flow 05 not run"
fi

check "5c.4" "HTTP spans are children of operations" "manual" "Open trace link"
check "5c.5" "Hive \`db\` spans are children of operations" "manual" "Open trace link"
} > "$REPORT_DIR/phase5_hierarchy.md"
PHASE_FILES+=("phase5_hierarchy.md")
PHASE_SUMMARIES+=("5. Hierarchy|phase5_hierarchy.md|all manual")

# ── summary.md ────────────────────────────────────────────────────────────

count_statuses

{
echo "# Sentry Span-First Validation Report"
echo ""
echo "**Run:** $TIMESTAMP"
echo "**Flows:** ${flows_to_run[*]}"
echo "**Spans:** $TOTAL_SPANS ($OK_COUNT ok, $ERROR_COUNT error, $OTHER_COUNT other)"
echo "**Traces:** ${#UNIQUE_TRACES}"
echo ""

echo "## Flow Results"
echo ""
echo "| Flow | Status |"
echo "|------|--------|"
for flow in "${flows_to_run[@]}"; do
  echo "| $flow | ${FLOW_STATUS[$flow]:-unknown} |"
done
echo ""

echo "## Trace Links"
echo ""
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  trace_count=0
  for (( i = 1; i <= ${#SPAN_TRACE_IDS[@]}; i++ )); do
    [[ "${SPAN_TRACE_IDS[$i]}" == "$tid" ]] && trace_count=$((trace_count + 1))
  done
  echo "- [$tid]($SENTRY_BASE_URL/$tid/) — $trace_count spans"
done
echo ""

echo "## Phase Reports"
echo ""
echo "| Phase | File | Status |"
echo "|-------|------|--------|"

for summary in "${PHASE_SUMMARIES[@]}"; do
  IFS='|' read -r label file phase_result <<< "$summary"
  echo "| $label | [$file]($file) | $phase_result |"
done

# Show skipped phases
if ! flow_ran "03_product_details"; then
  echo "| 4a. Scanning | — | *skipped (flow 03 not run)* |"
  echo "| 4b. Product Load | — | *skipped (flow 03 not run)* |"
  echo "| 4f. configureScope | — | *skipped (flow 03 not run)* |"
fi
if ! flow_ran "02_search_product"; then
  echo "| 4c. Search | — | *skipped (flow 02 not run)* |"
fi
if ! flow_ran "05_product_edit"; then
  echo "| 4d. Background | — | *skipped (flow 05 not run)* |"
  echo "| 4e. Inactive Span | — | *skipped (flow 05 not run)* |"
fi
echo ""

echo "## Files"
echo ""
echo "| File | Description |"
echo "|------|-------------|"
echo "| [spans.md](spans.md) | All $TOTAL_SPANS captured spans (grouped + detailed) |"
for pf in "${PHASE_FILES[@]}"; do
  echo "| [$pf]($pf) | Phase validation checks |"
done
echo "| [flutter_logs.txt](flutter_logs.txt) | Raw simulator logs |"
echo ""

echo "---"
echo ""
echo "[Sentry Dashboard](https://sentry.io/organizations/denrase/performance/?project=smooth-app-span-first)"
} > "$REPORT_DIR/summary.md"

# ─── Terminal summary ─────────────────────────────────────────────────────

echo ""
info "Reports generated: $REPORT_DIR"
echo ""

echo "═══════════════════════════════════════════════════"
echo " Spans: $TOTAL_SPANS ($OK_COUNT ok, $ERROR_COUNT err, $OTHER_COUNT other)"
echo " Traces: ${#UNIQUE_TRACES}"
echo ""
echo " Phase reports:"
for summary in "${PHASE_SUMMARIES[@]}"; do
  IFS='|' read -r label file phase_result <<< "$summary"
  echo "   $label — $phase_result"
done
echo ""

# Quick span check for custom instrumentation
typeset -A SPAN_FLOW_MAP
SPAN_FLOW_MAP=(
  [product.search]="02_search_product"
  [product.search.decode]="02_search_product"
  [product.load]="03_product_details"
  [product.scan]="03_product_details"
  [product.cache_lookup]="03_product_details"
  [product.fetch]="03_product_details"
  [background_task.execute]="05_product_edit"
  [background_task.lifecycle]="05_product_edit"
)

echo " Custom spans:"
for expected in "product.scan" "product.cache_lookup" "product.fetch" "product.search" "product.search.decode" "product.load" "background_task.execute" "background_task.lifecycle"; do
  required_flow="${SPAN_FLOW_MAP[$expected]}"
  if span_exists "$expected"; then
    ok "$expected"
  elif ! flow_ran "$required_flow"; then
    warn "$expected (flow $required_flow not run)"
  else
    fail "$expected"
  fi
done

echo ""
echo " Trace links:"
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  echo "   $SENTRY_BASE_URL/$tid/"
done
echo "═══════════════════════════════════════════════════"
echo ""
echo "Summary: $REPORT_DIR/summary.md"
