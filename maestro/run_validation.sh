#!/usr/bin/env zsh
#
# Sentry Span-First Validation Runner
#
# Runs Maestro flows against an iOS simulator while capturing Flutter logs,
# then generates a validation report with auto-checks and Sentry links.
#
# Usage:
#   ./maestro/run_validation.sh                  # run all flows
#   ./maestro/run_validation.sh 02               # run only flow 02
#   ./maestro/run_validation.sh 02 03            # run flows 02 and 03
#
# Prerequisites:
#   - iOS simulator booted with the app installed
#   - maestro CLI installed
#   - flutter CLI available

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="$SCRIPT_DIR/reports"
LOG_FILE="$OUTPUT_DIR/flutter_logs_${TIMESTAMP}.txt"
REPORT_FILE="$OUTPUT_DIR/report_${TIMESTAMP}.md"

SENTRY_BASE_URL="https://sentry.io/organizations/sentry-sdks/performance/trace"

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
  if [[ -n "${FLUTTER_LOGS_PID:-}" ]] && kill -0 "$FLUTTER_LOGS_PID" 2>/dev/null; then
    kill "$FLUTTER_LOGS_PID" 2>/dev/null || true
    wait "$FLUTTER_LOGS_PID" 2>/dev/null || true
  fi
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

mkdir -p "$OUTPUT_DIR"

info "Validation run: $TIMESTAMP"
info "Flows: ${flows_to_run[*]}"
info "Log file: $LOG_FILE"
info "Report: $REPORT_FILE"
echo ""

# Start flutter logs in background
info "Starting flutter logs..."
flutter logs --no-color > "$LOG_FILE" 2>&1 &
FLUTTER_LOGS_PID=$!
sleep 2

if ! kill -0 "$FLUTTER_LOGS_PID" 2>/dev/null; then
  echo "Error: flutter logs failed to start. Is a simulator booted?"
  exit 1
fi

info "Flutter logs running (PID: $FLUTTER_LOGS_PID)"
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

  info "Running flow: $flow"
  if maestro test "$flow_file" 2>&1 | while IFS= read -r line; do echo "  │ $line"; done; then
    FLOW_STATUS[$flow]="passed"
    ok "Flow $flow completed"
  else
    FLOW_STATUS[$flow]="failed"
    fail "Flow $flow failed"
  fi

  # Brief pause to let any trailing spans flush
  sleep 3
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
  if [[ "$line" =~ '\[SentrySpanFirst\] Span: ([^ ]+) \(([^)]*)\) trace=([^ ]+) span=([^ ]+)' ]]; then
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

# ─── Helper: check if span name exists ─────────────────────────────────────

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

# Check if two span names share a trace ID (indicates parent-child relationship)
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

# Get trace ID for a span name (first match)
get_trace_id() {
  local name="$1"
  for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
    [[ "${SPAN_NAMES[$i]}" == "$name" ]] && echo "${SPAN_TRACE_IDS[$i]}" && return 0
  done
  echo ""
}

# Count occurrences of a span name
count_spans() {
  local name="$1" count=0
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" == "$name" ]] && count=$((count + 1))
  done
  echo "$count"
}

# Format check result
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

# ─── Generate report ───────────────────────────────────────────────────────

info "Generating report..."

{
cat <<'HEADER'
# Sentry Span-First Validation Report

HEADER

echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
echo "**Total spans captured:** $TOTAL_SPANS"
echo "**Unique traces:** ${#UNIQUE_TRACES}"
echo ""

# ── Flow results ──

echo "## Flow Results"
echo ""
echo "| Flow | Maestro Status |"
echo "|------|---------------|"
for flow in "${flows_to_run[@]}"; do
  flow_status="${FLOW_STATUS[$flow]:-unknown}"
  echo "| $flow | $flow_status |"
done
echo ""

# ── All captured spans ──

echo "## Captured Spans"
echo ""
echo "| # | Span Name | Status | Trace ID | Span ID | Sentry Link |"
echo "|---|-----------|--------|----------|---------|-------------|"
for (( i = 1; i <= ${#SPAN_NAMES[@]}; i++ )); do
  tid="${SPAN_TRACE_IDS[$i]}"
  sid="${SPAN_SPAN_IDS[$i]}"
  link="[trace]($SENTRY_BASE_URL/$tid/)"
  echo "| $i | \`${SPAN_NAMES[$i]}\` | ${SPAN_STATUSES[$i]} | \`${tid[1,12]}…\` | \`${sid[1,12]}…\` | $link |"
done
echo ""

# ── Unique traces ──

echo "## Traces"
echo ""
echo "Open these links in Sentry to inspect the full span tree:"
echo ""
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  # List span names in this trace
  spans_in_trace=""
  for (( i = 1; i <= ${#SPAN_TRACE_IDS[@]}; i++ )); do
    [[ "${SPAN_TRACE_IDS[$i]}" == "$tid" ]] && spans_in_trace="$spans_in_trace \`${SPAN_NAMES[$i]}\`"
  done
  echo "- **[$tid]($SENTRY_BASE_URL/$tid/)** —$spans_in_trace"
done
echo ""

# ── Auto-verified checks ──

echo "## Validation Checks"
echo ""
echo "Legend: **PASS** = verified from logs, **FAIL** = expected but not found, **MANUAL** = requires Sentry UI"
echo ""

# Phase 1
echo "### Phase 1: Streaming Mode & Options"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if [[ $TOTAL_SPANS -gt 0 ]]; then
  check "1.1" "Sentry initializes, spans appear" "pass" "Found $TOTAL_SPANS spans"
else
  check "1.1" "Sentry initializes, spans appear" "fail" "No spans captured"
fi

if [[ $TOTAL_SPANS -gt 0 ]]; then
  check "1.2" "\`beforeSendSpan\` is called" "pass" "Log lines present"
else
  check "1.2" "\`beforeSendSpan\` is called" "fail" "No log lines"
fi

check "1.3" "Tags \`store\` and \`scanner\` on events" "manual" "Check any event in Sentry"
check "1.4" "\`beforeSend\` gates on \`_crashReports\`" "manual" "Toggle preference, verify filtering"
echo ""

# Phase 2
echo "### Phase 2: Hive Instrumentation"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists_pattern "openBox|SentryHive"; then
  hive_count=0
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" =~ "openBox|openLazyBox|SentryHive" ]] && hive_count=$((hive_count + 1))
  done
  check "2.1" "\`SentryHive.init()\` works" "pass" "App booted, Hive spans present"
  check "2.2" "\`openBox\`/\`openLazyBox\` spans appear" "pass" "Found $hive_count Hive-related spans"
else
  check "2.1" "\`SentryHive.init()\` works" "manual" "No Hive spans detected — check if app booted"
  check "2.2" "\`openBox\`/\`openLazyBox\` spans appear" "fail" "No openBox/openLazyBox spans found"
fi

if span_exists_pattern "^db$|^db\."; then
  check "2.3" "Box read/write create \`db\` spans" "pass" "Found db spans"
else
  check "2.3" "Box read/write create \`db\` spans" "manual" "No \`db\` spans found — check trace in Sentry"
fi

check "2.4" "\`registerAdapter\` works via SentryHive" "manual" "Verify product data loads correctly"
echo ""

# Phase 3
echo "### Phase 3: HTTP Instrumentation"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

http_count=$(count_spans "http.client")
# Also count any span starting with http
if [[ "$http_count" -eq 0 ]]; then
  for sn in "${SPAN_NAMES[@]}"; do
    [[ "$sn" =~ "^http" ]] && http_count=$((http_count + 1))
  done
fi

if [[ "$http_count" -gt 0 ]]; then
  check "3.1" "\`SentryHttpClient\` creates HTTP spans" "pass" "Found $http_count HTTP spans"
else
  check "3.1" "\`SentryHttpClient\` creates HTTP spans" "fail" "No HTTP spans found"
fi

check "3.2" "SVG downloads traced" "manual" "Check for HTTP spans to \`static.openfoodfacts.org\` in trace"
check "3.3" "News feed fetch traced" "manual" "Check for HTTP span to \`raw.githubusercontent.com\`"
check "3.4" "GitHub contributors fetch traced" "manual" "Check for HTTP span to \`api.github.com\`"
echo ""

# Phase 4a
echo "### Phase 4a: Product Scanning Spans"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "product.scan"; then
  tid=$(get_trace_id "product.scan")
  check "4a.1" "\`product.scan\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4a.1" "\`product.scan\` span created" "fail" "Not found — scanning flow may not have run"
fi

if span_exists "product.cache_lookup"; then
  if spans_share_trace "product.scan" "product.cache_lookup"; then
    check "4a.2" "\`product.cache_lookup\` child of scan" "pass" "Same trace ID"
  else
    check "4a.2" "\`product.cache_lookup\` child of scan" "manual" "Different trace IDs — check hierarchy in Sentry"
  fi
else
  check "4a.2" "\`product.cache_lookup\` child of scan" "manual" "Span not found"
fi

if span_exists "product.fetch"; then
  if spans_share_trace "product.scan" "product.fetch"; then
    check "4a.3" "\`product.fetch\` child of scan" "pass" "Same trace ID"
  else
    check "4a.3" "\`product.fetch\` child of scan" "manual" "Different trace IDs — check hierarchy in Sentry"
  fi
else
  check "4a.3" "\`product.fetch\` child of scan" "manual" "Span not found (may need unknown barcode)"
fi

check "4a.4" "\`barcode\` attribute set" "manual" "Click span in Sentry, verify \`barcode\` attribute"
check "4a.5" "Error status on internet error" "manual" "Disable network, scan barcode"
check "4a.6" "\`deadlineExceeded\` on timeout" "manual" "Slow network test"
echo ""

# Phase 4b
echo "### Phase 4b: Product Loader Span"
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
echo ""

# Phase 4c
echo "### Phase 4c: Search Spans"
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

if span_exists "product.search" && [[ "$http_count" -gt 0 ]]; then
  check "4c.4" "HTTP span child of search" "manual" "Check trace tree in Sentry"
else
  check "4c.4" "HTTP span child of search" "manual" "Verify in Sentry"
fi
echo ""

# Phase 4d
echo "### Phase 4d: Background Task Spans"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"

if span_exists "background_task.execute"; then
  tid=$(get_trace_id "background_task.execute")
  check "4d.1" "\`background_task.execute\` span created" "pass" "[View trace]($SENTRY_BASE_URL/$tid/)"
else
  check "4d.1" "\`background_task.execute\` span created" "manual" "Edit flow may not trigger actual save"
fi

check "4d.2" "\`task_type\` and \`task_id\` attributes" "manual" "Click span in Sentry"
check "4d.3" "Error status on task failure" "manual" "Disable network, trigger upload"
echo ""

# Phase 4e
echo "### Phase 4e: \`startInactiveSpan\` Validation"
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
  check "4e.1" "\`background_task.lifecycle\` span created" "manual" "May require actual product edit"
  check "4e.2" "\`execute\` child of \`lifecycle\`" "manual" "Depends on 4e.1"
fi

check "4e.3" "Lifecycle duration > execute duration" "manual" "Compare spans in trace view"
check "4e.4" "Error propagates to lifecycle span" "manual" "Fail a task, check status"
echo ""

# Phase 4f
echo "### Phase 4f: \`configureScope\` Validation"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"
check "4f.1" "\`flow=scanning\` tag on scan children" "manual" "Check tags in Sentry span detail"
check "4f.2" "\`flow=scanning\` NOT on unrelated spans" "manual" "Verify search/background spans lack tag"
echo ""

# Phase 5
echo "### Phase 5: Hierarchy & Filtering"
echo ""
echo "| # | Check | Result | Detail |"
echo "|---|-------|--------|--------|"
check "5a.1" "Ignored spans filtered" "manual" "Add ignoreSpan rule, verify absence"
check "5a.2" "Non-ignored spans unaffected" "manual" "Other spans still appear"

# For hierarchy checks, provide links
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  echo ""
  echo "**Verify hierarchy in trace:** [$tid]($SENTRY_BASE_URL/$tid/)"
  break  # just show first one as example
done
echo ""
check "5c.1" "Scan hierarchy matches tree" "manual" "Open trace link above"
check "5c.2" "Search hierarchy matches tree" "manual" "Open trace link above"
check "5c.3" "Background task hierarchy matches tree" "manual" "Open trace link above"
check "5c.4" "HTTP spans are children of operations" "manual" "Open trace link above"
check "5c.5" "Hive \`db\` spans are children of operations" "manual" "Open trace link above"
echo ""

# ── Summary ──

echo "---"
echo ""
echo "## Summary"
echo ""
echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Total spans | $TOTAL_SPANS |"
echo "| Unique traces | ${#UNIQUE_TRACES} |"
echo "| Flows run | ${#flows_to_run[@]} |"

# Count statuses
ok_count=0
error_count=0
other_count=0
for st in "${SPAN_STATUSES[@]}"; do
  case "$st" in
    ok) ok_count=$((ok_count + 1)) ;;
    error|cancelled|deadlineExceeded|deadline_exceeded) error_count=$((error_count + 1)) ;;
    *) other_count=$((other_count + 1)) ;;
  esac
done
echo "| Spans with \`ok\` status | $ok_count |"
echo "| Spans with error/cancelled status | $error_count |"
echo "| Spans with other status | $other_count |"
echo ""

echo "## Quick Links"
echo ""
echo "- [Sentry Dashboard](https://sentry.io/organizations/sentry-sdks/performance/?project=4510980127784960)"
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  echo "- [Trace $tid]($SENTRY_BASE_URL/$tid/)"
done
echo ""
echo "---"
echo "*Log file: \`$LOG_FILE\`*"

} > "$REPORT_FILE"

echo ""
info "Report generated: $REPORT_FILE"
info "Log file: $LOG_FILE"
echo ""

# Print a quick summary to terminal too
echo "═══════════════════════════════════════════════════"
echo " Spans captured: $TOTAL_SPANS"
echo " Unique traces:  ${#UNIQUE_TRACES}"
echo ""
echo " Quick span check:"

for expected in "product.search" "product.search.decode" "product.load" "product.scan" "product.cache_lookup" "product.fetch" "background_task.execute" "background_task.lifecycle"; do
  if span_exists "$expected"; then
    ok "$expected"
  else
    fail "$expected (not found)"
  fi
done

echo ""
echo " Trace links:"
for tid in "${(k)UNIQUE_TRACES[@]}"; do
  echo "   $SENTRY_BASE_URL/$tid/"
done
echo "═══════════════════════════════════════════════════"
echo ""
echo "Full report: $REPORT_FILE"
