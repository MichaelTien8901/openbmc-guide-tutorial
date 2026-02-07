#!/bin/bash
#
# List and Manage Redfish Event Subscriptions
#
# Displays existing EventService subscriptions and provides commands for
# inspecting individual subscriptions and cleaning up stale ones.
#
# Usage:
#   ./list-subscriptions.sh [list|show ID|delete ID|delete-all]
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

BASE_URL="https://${BMC_HOST}/redfish/v1"
CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"

ACTION="${1:-list}"
SUB_ID="${2:-}"

list_subscriptions() {
    echo "========================================"
    echo "Redfish Event Subscriptions"
    echo "BMC: ${BMC_HOST}"
    echo "========================================"
    echo ""

    # Get EventService overview
    ES_RESULT=$($CURL "${BASE_URL}/EventService" 2>/dev/null)
    if echo "$ES_RESULT" | jq -e '.ServiceEnabled' > /dev/null 2>&1; then
        SERVICE_ENABLED=$(echo "$ES_RESULT" | jq -r '.ServiceEnabled')
        SSE_URI=$(echo "$ES_RESULT" | jq -r '.ServerSentEventUri // "N/A"')
        echo "  EventService Enabled: ${SERVICE_ENABLED}"
        echo "  SSE URI: ${SSE_URI}"
        echo ""
    else
        echo "  ERROR: EventService not available at ${BASE_URL}/EventService"
        exit 1
    fi

    # List subscriptions
    SUBS_RESULT=$($CURL "${BASE_URL}/EventService/Subscriptions" 2>/dev/null)
    COUNT=$(echo "$SUBS_RESULT" | jq '.Members | length' 2>/dev/null || echo "0")

    echo "  Total subscriptions: ${COUNT}"
    echo ""

    if [ "$COUNT" = "0" ]; then
        echo "  No active subscriptions."
        echo ""
        echo "  Create one with:"
        echo "    ./create-subscription.sh https://your-listener:8443/events"
        return
    fi

    # Fetch details for each subscription
    echo "$SUBS_RESULT" | jq -r '.Members[]."@odata.id"' 2>/dev/null | while read -r URI; do
        DETAIL=$($CURL "https://${BMC_HOST}${URI}" 2>/dev/null)
        if [ -n "$DETAIL" ]; then
            ID=$(echo "$DETAIL" | jq -r '.Id // "?"')
            DEST=$(echo "$DETAIL" | jq -r '.Destination // "?"')
            PROTOCOL=$(echo "$DETAIL" | jq -r '.Protocol // "?"')
            CONTEXT=$(echo "$DETAIL" | jq -r '.Context // ""')
            EVENT_FORMAT=$(echo "$DETAIL" | jq -r '.EventFormatType // "Event"')
            REGISTRIES=$(echo "$DETAIL" | jq -r '(.RegistryPrefixes // []) | join(", ")')
            RESOURCE_TYPES=$(echo "$DETAIL" | jq -r '(.ResourceTypes // []) | join(", ")')

            echo "  --- Subscription: ${ID} ---"
            echo "    Destination:      ${DEST}"
            echo "    Protocol:         ${PROTOCOL}"
            echo "    Context:          ${CONTEXT}"
            echo "    EventFormatType:  ${EVENT_FORMAT}"
            if [ -n "$REGISTRIES" ]; then
                echo "    RegistryPrefixes: ${REGISTRIES}"
            fi
            if [ -n "$RESOURCE_TYPES" ]; then
                echo "    ResourceTypes:    ${RESOURCE_TYPES}"
            fi
            echo ""
        fi
    done
}

show_subscription() {
    if [ -z "$SUB_ID" ]; then
        echo "Usage: $0 show SUBSCRIPTION_ID"
        echo "  Use '$0 list' to see available IDs."
        exit 1
    fi

    echo "========================================"
    echo "Subscription Details: ${SUB_ID}"
    echo "========================================"
    echo ""

    RESULT=$($CURL "${BASE_URL}/EventService/Subscriptions/${SUB_ID}" 2>/dev/null)

    if echo "$RESULT" | jq -e '.Id' > /dev/null 2>&1; then
        echo "$RESULT" | jq '.'
    else
        echo "  Subscription '${SUB_ID}' not found."
        echo ""
        echo "  Available subscriptions:"
        $CURL "${BASE_URL}/EventService/Subscriptions" 2>/dev/null \
            | jq -r '.Members[]."@odata.id"' 2>/dev/null || echo "    (none)"
    fi
}

delete_subscription() {
    if [ -z "$SUB_ID" ]; then
        echo "Usage: $0 delete SUBSCRIPTION_ID"
        echo "  Use '$0 list' to see available IDs."
        exit 1
    fi

    echo "Deleting subscription: ${SUB_ID}..."

    RESULT=$($CURL -X DELETE \
        -w "\n%{http_code}" \
        "${BASE_URL}/EventService/Subscriptions/${SUB_ID}" 2>/dev/null)

    HTTP_CODE=$(echo "$RESULT" | tail -1)

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo "  Subscription '${SUB_ID}' deleted successfully."
    elif [ "$HTTP_CODE" = "404" ]; then
        echo "  Subscription '${SUB_ID}' not found."
    else
        echo "  Failed to delete subscription (HTTP ${HTTP_CODE})."
        RESPONSE_BODY=$(echo "$RESULT" | head -n -1)
        echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
    fi
}

delete_all_subscriptions() {
    echo "========================================"
    echo "Delete All Subscriptions"
    echo "BMC: ${BMC_HOST}"
    echo "========================================"
    echo ""

    SUBS_RESULT=$($CURL "${BASE_URL}/EventService/Subscriptions" 2>/dev/null)
    COUNT=$(echo "$SUBS_RESULT" | jq '.Members | length' 2>/dev/null || echo "0")

    if [ "$COUNT" = "0" ]; then
        echo "  No subscriptions to delete."
        return
    fi

    echo "  Found ${COUNT} subscription(s). Deleting..."
    echo ""

    echo "$SUBS_RESULT" | jq -r '.Members[]."@odata.id"' 2>/dev/null | while read -r URI; do
        ID=$(basename "$URI")
        RESULT=$($CURL -X DELETE \
            -w "\n%{http_code}" \
            "https://${BMC_HOST}${URI}" 2>/dev/null)
        HTTP_CODE=$(echo "$RESULT" | tail -1)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
            echo "  Deleted: ${ID}"
        else
            echo "  Failed to delete: ${ID} (HTTP ${HTTP_CODE})"
        fi
    done
    echo ""
    echo "  Done."
}

case "$ACTION" in
    list)
        list_subscriptions
        ;;
    show)
        show_subscription
        ;;
    delete)
        delete_subscription
        ;;
    delete-all)
        delete_all_subscriptions
        ;;
    *)
        echo "Usage: $0 [list|show ID|delete ID|delete-all]"
        echo ""
        echo "Commands:"
        echo "  list              - List all event subscriptions"
        echo "  show ID           - Show full details of a subscription"
        echo "  delete ID         - Delete a specific subscription"
        echo "  delete-all        - Delete all subscriptions"
        echo ""
        echo "Environment variables:"
        echo "  BMC_HOST=${BMC_HOST}"
        echo "  BMC_USER=${BMC_USER}"
        echo "  BMC_PASS=***"
        exit 1
        ;;
esac
