#!/bin/bash
#
# Read BIOS settings from OpenBMC via Redfish
#
# Queries the current BIOS attribute table and pending settings through
# bmcweb's Redfish /Systems/system/Bios endpoint.
#
# Usage:
#   ./read-bios-settings.sh <bmc-host> [username] [password]
#   ./read-bios-settings.sh <bmc-host> --attribute <name>
#
# Arguments:
#   bmc-host        BMC hostname or IP:port (e.g., localhost:2443)
#   username        BMC username (default: root)
#   password        BMC password (default: 0penBmc)
#   --attribute     Read a single attribute by name
#
# Examples:
#   ./read-bios-settings.sh localhost:2443
#   ./read-bios-settings.sh localhost:2443 --attribute BootMode
#   ./read-bios-settings.sh 192.168.1.100 admin password123
#
# Prerequisites:
#   - curl and jq installed on the client
#   - OpenBMC with bios-settings-manager enabled
#

set -euo pipefail

BMC_HOST=${1:?Usage: $0 <bmc-host> [username] [password] | <bmc-host> --attribute <name>}
shift

# Check for --attribute flag
ATTR_NAME=""
if [ "${1:-}" = "--attribute" ]; then
    ATTR_NAME=${2:?Usage: $0 <bmc-host> --attribute <name>}
    shift 2
fi

USERNAME=${1:-root}
PASSWORD=${2:-0penBmc}

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_HOST}/redfish/v1"
BIOS_URL="${BASE_URL}/Systems/system/Bios"

# Verify dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed" >&2
        exit 1
    fi
done

echo "========================================"
echo "BIOS Settings Reader"
echo "BMC: ${BMC_HOST}"
echo "========================================"
echo ""

# Read a single attribute
if [ -n "$ATTR_NAME" ]; then
    echo "Reading attribute: ${ATTR_NAME}"
    echo ""

    RESULT=$($CURL "${BIOS_URL}" 2>/dev/null)
    HTTP_CODE=$(echo "$RESULT" | jq -r '.error.code // empty' 2>/dev/null)

    if [ -n "$HTTP_CODE" ]; then
        echo "Error: Failed to read BIOS settings" >&2
        echo "$RESULT" | jq '.' 2>/dev/null
        exit 1
    fi

    VALUE=$(echo "$RESULT" | jq -r ".Attributes.${ATTR_NAME} // \"NOT_FOUND\"" 2>/dev/null)
    if [ "$VALUE" = "NOT_FOUND" ]; then
        echo "Attribute '${ATTR_NAME}' not found in current BIOS settings" >&2
        echo ""
        echo "Available attributes:"
        echo "$RESULT" | jq -r '.Attributes | keys[]' 2>/dev/null | sort | sed 's/^/  /'
        exit 1
    fi

    echo "  Current value: ${VALUE}"
    echo ""

    # Check if there is a pending value
    PENDING=$($CURL "${BIOS_URL}/Settings" 2>/dev/null)
    PENDING_VALUE=$(echo "$PENDING" | jq -r ".Attributes.${ATTR_NAME} // \"NONE\"" 2>/dev/null)
    if [ "$PENDING_VALUE" != "NONE" ] && [ "$PENDING_VALUE" != "$VALUE" ]; then
        echo "  Pending value: ${PENDING_VALUE} (applied on next boot)"
    else
        echo "  No pending change"
    fi

    exit 0
fi

# Read all current BIOS settings
echo "=== Current BIOS Attributes ==="
echo ""

RESULT=$($CURL "${BIOS_URL}" 2>/dev/null)
ERROR=$(echo "$RESULT" | jq -r '.error.code // empty' 2>/dev/null)

if [ -n "$ERROR" ]; then
    echo "Error: Failed to read BIOS settings" >&2
    echo "$RESULT" | jq '.' 2>/dev/null
    exit 1
fi

# Display metadata
REGISTRY=$(echo "$RESULT" | jq -r '.AttributeRegistry // "Unknown"' 2>/dev/null)
echo "Attribute Registry: ${REGISTRY}"
echo ""

# Display attributes in a sorted table
echo "Attributes:"
echo "$RESULT" | jq -r '.Attributes | to_entries | sort_by(.key) | .[] | "  \(.key) = \(.value)"' 2>/dev/null
echo ""

# Count attributes by inferred type
TOTAL=$(echo "$RESULT" | jq '.Attributes | length' 2>/dev/null)
STRINGS=$(echo "$RESULT" | jq '[.Attributes | to_entries[] | select(.value | type == "string")] | length' 2>/dev/null)
INTEGERS=$(echo "$RESULT" | jq '[.Attributes | to_entries[] | select(.value | type == "number")] | length' 2>/dev/null)
echo "Summary: ${TOTAL} attributes (${STRINGS} string/enum, ${INTEGERS} integer)"
echo ""

# Read pending settings
echo "=== Pending Settings (Applied on Next Boot) ==="
echo ""

PENDING=$($CURL "${BIOS_URL}/Settings" 2>/dev/null)
PENDING_ERROR=$(echo "$PENDING" | jq -r '.error.code // empty' 2>/dev/null)

if [ -n "$PENDING_ERROR" ]; then
    echo "  No pending settings endpoint available"
else
    PENDING_ATTRS=$(echo "$PENDING" | jq '.Attributes // {}' 2>/dev/null)
    PENDING_COUNT=$(echo "$PENDING_ATTRS" | jq 'length' 2>/dev/null)

    if [ "$PENDING_COUNT" -gt 0 ] 2>/dev/null; then
        echo "$PENDING_ATTRS" | jq -r 'to_entries | sort_by(.key) | .[] | "  \(.key) = \(.value)"' 2>/dev/null

        # Show settings apply time if available
        APPLY_TIME=$(echo "$PENDING" | jq -r '.["@Redfish.Settings"].Time // empty' 2>/dev/null)
        if [ -n "$APPLY_TIME" ]; then
            echo ""
            echo "  Last updated: ${APPLY_TIME}"
        fi
    else
        echo "  No pending changes"
    fi
fi

echo ""
echo "Read complete."
