#!/bin/bash
#
# Create a Redfish Push Event Subscription
#
# Registers a callback URL with the BMC's EventService. When events occur,
# the BMC will POST event payloads to the specified Destination URL.
#
# Usage:
#   ./create-subscription.sh [destination-url]
#
# Environment variables:
#   BMC_HOST  - BMC hostname:port (default: localhost:2443)
#   BMC_USER  - Redfish username (default: root)
#   BMC_PASS  - Redfish password (default: 0penBmc)
#
# Prerequisites:
#   - Running OpenBMC with bmcweb EventService enabled
#   - curl and jq installed on the client

set -euo pipefail

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"
DESTINATION="${1:-https://listener.example.com:8443/redfish-events}"

BASE_URL="https://${BMC_HOST}/redfish/v1"
CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"

echo "========================================"
echo "Create Redfish Event Subscription"
echo "BMC: ${BMC_HOST}"
echo "========================================"
echo ""

# Step 1: Check EventService status
echo "Step 1: Checking EventService status..."
ES_RESULT=$($CURL "${BASE_URL}/EventService" 2>/dev/null)
if ! echo "$ES_RESULT" | jq -e '.ServiceEnabled' > /dev/null 2>&1; then
    echo "  ERROR: EventService not available at ${BASE_URL}/EventService"
    echo "  Ensure bmcweb is running and EventService is enabled."
    exit 1
fi

SERVICE_ENABLED=$(echo "$ES_RESULT" | jq -r '.ServiceEnabled')
SSE_URI=$(echo "$ES_RESULT" | jq -r '.ServerSentEventUri // "N/A"')
RETRY_ATTEMPTS=$(echo "$ES_RESULT" | jq -r '.DeliveryRetryAttempts // "N/A"')
RETRY_INTERVAL=$(echo "$ES_RESULT" | jq -r '.DeliveryRetryIntervalSeconds // "N/A"')

echo "  ServiceEnabled: ${SERVICE_ENABLED}"
echo "  SSE URI: ${SSE_URI}"
echo "  DeliveryRetryAttempts: ${RETRY_ATTEMPTS}"
echo "  DeliveryRetryIntervalSeconds: ${RETRY_INTERVAL}"
echo ""

if [ "$SERVICE_ENABLED" != "true" ]; then
    echo "  WARNING: EventService is not enabled."
fi

# Step 2: Create subscription for all event types
echo "Step 2: Creating push event subscription..."
echo "  Destination: ${DESTINATION}"
echo ""

SUBSCRIPTION_BODY=$(cat <<'ENDJSON'
{
    "Destination": "DESTINATION_PLACEHOLDER",
    "Protocol": "Redfish",
    "Context": "OpenBMC-Tutorial-Events",
    "EventFormatType": "Event",
    "RegistryPrefixes": [
        "OpenBMC",
        "ResourceEvent",
        "TaskEvent"
    ],
    "ResourceTypes": [
        "Chassis",
        "Systems",
        "Managers",
        "LogEntry"
    ],
    "HttpHeaders": {
        "Content-Type": "application/json"
    }
}
ENDJSON
)

# Replace placeholder with actual destination
SUBSCRIPTION_BODY=$(echo "$SUBSCRIPTION_BODY" | jq --arg dest "$DESTINATION" '.Destination = $dest')

echo "  Request body:"
echo "$SUBSCRIPTION_BODY" | jq '.'
echo ""

RESULT=$($CURL -X POST \
    -H "Content-Type: application/json" \
    -d "$SUBSCRIPTION_BODY" \
    -w "\n%{http_code}" \
    "${BASE_URL}/EventService/Subscriptions" 2>/dev/null)

HTTP_CODE=$(echo "$RESULT" | tail -1)
RESPONSE_BODY=$(echo "$RESULT" | head -n -1)

echo "  HTTP Status: ${HTTP_CODE}"
echo ""

if [ "$HTTP_CODE" = "201" ]; then
    echo "  Subscription created successfully!"
    echo ""
    echo "  Subscription details:"
    echo "$RESPONSE_BODY" | jq '{
        Id: .Id,
        Destination: .Destination,
        Protocol: .Protocol,
        Context: .Context,
        RegistryPrefixes: .RegistryPrefixes,
        ResourceTypes: .ResourceTypes
    }' 2>/dev/null || echo "$RESPONSE_BODY"

    SUB_ID=$(echo "$RESPONSE_BODY" | jq -r '.Id // "unknown"')
    echo ""
    echo "  To view:   curl -k -s -u ${BMC_USER}:${BMC_PASS} ${BASE_URL}/EventService/Subscriptions/${SUB_ID} | jq ."
    echo "  To delete: curl -k -s -u ${BMC_USER}:${BMC_PASS} -X DELETE ${BASE_URL}/EventService/Subscriptions/${SUB_ID}"
else
    echo "  Failed to create subscription."
    echo ""
    echo "  Response:"
    echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
fi
echo ""

# Step 3: Show alternative minimal subscription
echo "========================================"
echo "Alternative: Minimal Subscription"
echo "========================================"
echo ""
echo "For a simpler subscription that receives all events:"
echo ""
echo "  curl -k -u ${BMC_USER}:${BMC_PASS} -X POST \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"Destination\": \"${DESTINATION}\", \"Protocol\": \"Redfish\"}' \\"
echo "    ${BASE_URL}/EventService/Subscriptions"
echo ""
echo "For metric report events only (telemetry):"
echo ""
echo "  curl -k -u ${BMC_USER}:${BMC_PASS} -X POST \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"Destination\": \"${DESTINATION}\", \"Protocol\": \"Redfish\", \"RegistryPrefixes\": [\"TelemetryService\"]}' \\"
echo "    ${BASE_URL}/EventService/Subscriptions"
