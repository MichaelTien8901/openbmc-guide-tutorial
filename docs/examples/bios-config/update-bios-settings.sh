#!/bin/bash
#
# Update BIOS settings on OpenBMC via Redfish
#
# Applies BIOS attribute changes through bmcweb's Redfish
# /Systems/system/Bios/Settings endpoint. Changes are staged as
# pending and applied on the next host boot.
#
# Usage:
#   ./update-bios-settings.sh <bmc-host> <attribute> <value> [username] [password]
#   ./update-bios-settings.sh <bmc-host> --file <json-file> [username] [password]
#   ./update-bios-settings.sh <bmc-host> --reset [username] [password]
#
# Arguments:
#   bmc-host        BMC hostname or IP:port (e.g., localhost:2443)
#   attribute       BIOS attribute name (e.g., BootMode)
#   value           New value for the attribute (e.g., UEFI)
#   --file          Apply multiple settings from a JSON file
#   --reset         Reset all BIOS settings to factory defaults
#   username        BMC username (default: root)
#   password        BMC password (default: 0penBmc)
#
# Examples:
#   # Set a single attribute
#   ./update-bios-settings.sh localhost:2443 BootMode UEFI
#
#   # Set an integer attribute
#   ./update-bios-settings.sh localhost:2443 NumCoresPerSocket 8
#
#   # Apply batch changes from a JSON file
#   ./update-bios-settings.sh localhost:2443 --file my-settings.json
#
#   # Reset BIOS to defaults
#   ./update-bios-settings.sh localhost:2443 --reset
#
# JSON file format for --file:
#   {
#       "BootMode": "UEFI",
#       "HyperThreading": "Enabled",
#       "NumCoresPerSocket": 16
#   }
#
# Prerequisites:
#   - curl and jq installed on the client
#   - OpenBMC with bios-settings-manager enabled
#   - ConfigureComponents or Administrator privilege
#

set -euo pipefail

BMC_HOST=${1:?Usage: $0 <bmc-host> <attribute> <value> | --file <json> | --reset}
shift

# Determine operation mode
MODE="single"
ATTR_NAME=""
ATTR_VALUE=""
JSON_FILE=""

case "${1:-}" in
    --file)
        MODE="file"
        JSON_FILE=${2:?Usage: $0 <bmc-host> --file <json-file> [username] [password]}
        shift 2
        ;;
    --reset)
        MODE="reset"
        shift
        ;;
    *)
        ATTR_NAME=${1:?Usage: $0 <bmc-host> <attribute> <value> [username] [password]}
        ATTR_VALUE=${2:?Usage: $0 <bmc-host> <attribute> <value> [username] [password]}
        shift 2
        ;;
esac

USERNAME=${1:-root}
PASSWORD=${2:-0penBmc}

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_HOST}/redfish/v1"
BIOS_URL="${BASE_URL}/Systems/system/Bios"
SETTINGS_URL="${BIOS_URL}/Settings"

# Verify dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed" >&2
        exit 1
    fi
done

echo "========================================"
echo "BIOS Settings Updater"
echo "BMC: ${BMC_HOST}"
echo "========================================"
echo ""

# Reset BIOS to defaults
if [ "$MODE" = "reset" ]; then
    echo "Resetting BIOS settings to factory defaults..."
    echo "POST ${BIOS_URL}/Actions/Bios.ResetBios"
    echo ""

    RESULT=$($CURL -X POST \
        -H "Content-Type: application/json" \
        -d '{}' \
        "${BIOS_URL}/Actions/Bios.ResetBios" \
        -w "\n%{http_code}" 2>/dev/null)

    HTTP_CODE=$(echo "$RESULT" | tail -1)
    BODY=$(echo "$RESULT" | sed '$d')

    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
        echo "BIOS reset requested successfully (HTTP ${HTTP_CODE})"
        echo "Settings will be restored to defaults on next host boot."
    else
        echo "Error: BIOS reset failed (HTTP ${HTTP_CODE})" >&2
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        exit 1
    fi

    exit 0
fi

# Build the PATCH payload
if [ "$MODE" = "file" ]; then
    # Batch update from JSON file
    if [ ! -f "$JSON_FILE" ]; then
        echo "Error: File not found: ${JSON_FILE}" >&2
        exit 1
    fi

    # Validate JSON
    if ! jq empty "$JSON_FILE" 2>/dev/null; then
        echo "Error: Invalid JSON in ${JSON_FILE}" >&2
        exit 1
    fi

    PAYLOAD=$(jq -c '{ "Attributes": . }' "$JSON_FILE")
    ATTR_COUNT=$(jq 'length' "$JSON_FILE")
    echo "Applying ${ATTR_COUNT} attributes from: ${JSON_FILE}"
    echo ""
    echo "Settings to apply:"
    jq -r 'to_entries[] | "  \(.key) = \(.value)"' "$JSON_FILE"
else
    # Single attribute update
    # Detect if the value is an integer
    if [[ "$ATTR_VALUE" =~ ^[0-9]+$ ]]; then
        PAYLOAD=$(jq -n --arg name "$ATTR_NAME" --argjson val "$ATTR_VALUE" \
            '{ "Attributes": { ($name): $val } }')
    else
        PAYLOAD=$(jq -n --arg name "$ATTR_NAME" --arg val "$ATTR_VALUE" \
            '{ "Attributes": { ($name): $val } }')
    fi

    echo "Setting: ${ATTR_NAME} = ${ATTR_VALUE}"
fi

echo ""
echo "PATCH ${SETTINGS_URL}"
echo "Payload: ${PAYLOAD}"
echo ""

# Apply the settings
RESULT=$($CURL -X PATCH \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$SETTINGS_URL" \
    -w "\n%{http_code}" 2>/dev/null)

HTTP_CODE=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ] 2>/dev/null; then
    echo "Settings applied successfully (HTTP ${HTTP_CODE})"
    echo ""

    # Show the pending settings to confirm
    echo "=== Pending Settings ==="
    PENDING=$($CURL "${SETTINGS_URL}" 2>/dev/null)
    echo "$PENDING" | jq '.Attributes // empty' 2>/dev/null
    echo ""
    echo "Changes will take effect on the next host boot."
else
    echo "Error: Failed to apply settings (HTTP ${HTTP_CODE})" >&2
    echo ""

    # Parse error details
    ERROR_MSG=$(echo "$BODY" | jq -r '.error["@Message.ExtendedInfo"][]?.Message // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        echo "Details:"
        echo "$ERROR_MSG" | sed 's/^/  /'
    else
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    fi

    exit 1
fi
