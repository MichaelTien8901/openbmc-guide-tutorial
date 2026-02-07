#!/bin/bash
#
# Redfish Server-Sent Events (SSE) Listener
#
# Connects to the BMC's SSE endpoint and displays streaming events in real
# time. The connection stays open until interrupted (Ctrl+C). No callback
# URL is needed -- events arrive on the same HTTP connection.
#
# Usage:
#   ./sse-listener.sh [filter]
#
# Arguments:
#   filter  - Optional jq filter applied to each event (default: '.')
#
# Environment variables:
#   BMC_HOST  - BMC hostname:port (default: localhost:2443)
#   BMC_USER  - Redfish username (default: root)
#   BMC_PASS  - Redfish password (default: 0penBmc)
#
# Prerequisites:
#   - Running OpenBMC with bmcweb SSE support enabled
#   - curl and jq installed on the client
#
# Examples:
#   ./sse-listener.sh                          # Show all events
#   ./sse-listener.sh '.Events[].MessageId'    # Show only MessageIds
#   ./sse-listener.sh '.Events[] | {MessageId, Message, Severity}'

set -euo pipefail

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"
JQ_FILTER="${1:-.}"

BASE_URL="https://${BMC_HOST}/redfish/v1"
CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"

echo "========================================"
echo "Redfish SSE Event Listener"
echo "BMC: ${BMC_HOST}"
echo "========================================"
echo ""

# Step 1: Discover SSE URI from EventService
echo "Step 1: Discovering SSE endpoint..."
ES_RESULT=$($CURL "${BASE_URL}/EventService" 2>/dev/null)
if ! echo "$ES_RESULT" | jq -e '.ServiceEnabled' > /dev/null 2>&1; then
    echo "  ERROR: EventService not available at ${BASE_URL}/EventService"
    exit 1
fi

SSE_URI=$(echo "$ES_RESULT" | jq -r '.ServerSentEventUri // empty')
if [ -z "$SSE_URI" ]; then
    echo "  ERROR: SSE not supported (ServerSentEventUri not present in EventService)"
    echo "  Ensure bmcweb is built with SSE support."
    exit 1
fi

echo "  SSE URI: ${SSE_URI}"
echo ""

# Step 2: Open SSE connection
echo "Step 2: Connecting to SSE stream..."
echo "  URL: https://${BMC_HOST}${SSE_URI}"
echo "  Filter: ${JQ_FILTER}"
echo ""
echo "  Waiting for events (press Ctrl+C to stop)..."
echo "  ----------------------------------------"
echo ""

# Track event count for display
EVENT_COUNT=0

# Connect to SSE endpoint and process events as they arrive.
#
# SSE format:
#   id: <event-id>
#   data: <JSON payload>
#
# We use --no-buffer to ensure curl outputs data immediately rather than
# buffering. The while loop reads each line and reassembles multi-line
# "data:" fields into complete JSON objects for jq processing.

DATA_BUFFER=""

$CURL --no-buffer \
    -H "Accept: text/event-stream" \
    "https://${BMC_HOST}${SSE_URI}" 2>/dev/null | \
while IFS= read -r LINE; do
    # Remove trailing carriage return if present
    LINE="${LINE%$'\r'}"

    # SSE "id:" field -- display the event ID
    if [[ "$LINE" == id:* ]]; then
        EVENT_ID="${LINE#id: }"
        continue
    fi

    # SSE "data:" field -- accumulate (data can span multiple lines)
    if [[ "$LINE" == data:* ]]; then
        DATA_BUFFER="${DATA_BUFFER}${LINE#data: }"
        continue
    fi

    # Empty line signals end of an SSE event -- process accumulated data
    if [ -z "$LINE" ] && [ -n "$DATA_BUFFER" ]; then
        EVENT_COUNT=$((EVENT_COUNT + 1))
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        echo "[${TIMESTAMP}] Event #${EVENT_COUNT} (id: ${EVENT_ID:-N/A})"

        # Try to parse as JSON and apply the filter
        if echo "$DATA_BUFFER" | jq -e '.' > /dev/null 2>&1; then
            echo "$DATA_BUFFER" | jq "$JQ_FILTER"
        else
            # Not valid JSON -- print raw data
            echo "  (raw) $DATA_BUFFER"
        fi
        echo ""

        # Reset for next event
        DATA_BUFFER=""
        EVENT_ID=""
    fi
done

echo ""
echo "SSE connection closed. Received ${EVENT_COUNT} event(s)."
