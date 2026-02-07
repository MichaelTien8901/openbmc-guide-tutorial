#!/bin/bash
#
# List existing BMC dumps and their sizes via Redfish DumpService
#
# Usage:
#   ./list-dumps.sh <bmc-ip[:port]> [username] [password]
#
# Examples:
#   ./list-dumps.sh 192.168.1.100
#   ./list-dumps.sh localhost:2443 root 0penBmc
#
# Output includes dump ID, creation timestamp, size, and completion status
# for each dump entry on the BMC.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BMC_IP="${1:?Usage: $0 <bmc-ip[:port]> [username] [password]}"
USERNAME="${2:-root}"
PASSWORD="${3:-0penBmc}"

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_IP}"
DUMP_SERVICE="${BASE_URL}/redfish/v1/Managers/bmc/LogServices/Dump"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "${cmd}" > /dev/null 2>&1; then
            echo "Error: Required command not found: ${cmd}" >&2
            exit 1
        fi
    done
}

# Format byte sizes in human-readable form
format_size() {
    local bytes="$1"
    if [ "${bytes}" = "null" ] || [ -z "${bytes}" ]; then
        echo "N/A"
        return
    fi
    if [ "${bytes}" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.1f GB\", ${bytes}/1073741824}")"
    elif [ "${bytes}" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f MB\", ${bytes}/1048576}")"
    elif [ "${bytes}" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.1f KB\", ${bytes}/1024}")"
    else
        echo "${bytes} B"
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Verify DumpService is available
# ---------------------------------------------------------------------------

verify_dump_service() {
    RESPONSE=$($CURL "${DUMP_SERVICE}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "${RESPONSE}" ]; then
        echo "Error: Cannot reach BMC at ${BMC_IP}. Check network and credentials." >&2
        exit 1
    fi

    SERVICE_NAME=$(echo "${RESPONSE}" | jq -r '.Name // empty' 2>/dev/null)
    if [ -z "${SERVICE_NAME}" ]; then
        echo "Error: DumpService not available at ${DUMP_SERVICE}" >&2
        echo "${RESPONSE}" | jq '.' 2>/dev/null || echo "${RESPONSE}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Step 2: Fetch all dump entries
# ---------------------------------------------------------------------------

list_dumps() {
    ENTRIES_RESPONSE=$($CURL "${DUMP_SERVICE}/Entries" 2>/dev/null)

    TOTAL_COUNT=$(echo "${ENTRIES_RESPONSE}" | jq -r '."Members@odata.count" // 0' 2>/dev/null)

    echo "=== BMC Dump Entries on ${BMC_IP} ==="
    echo "Total dumps: ${TOTAL_COUNT}"
    echo ""

    if [ "${TOTAL_COUNT}" -eq 0 ]; then
        echo "No dump entries found."
        echo ""
        echo "To create a new dump:"
        echo "  ./collect-dump.sh ${BMC_IP} ${USERNAME}"
        echo ""
        echo "Or via curl:"
        echo "  curl -k -u ${USERNAME}:*** -X POST \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo "    -d '{\"DiagnosticDataType\": \"Manager\"}' \\"
        echo "    ${DUMP_SERVICE}/Actions/LogService.CollectDiagnosticData"
        return
    fi

    # Print table header
    printf "%-6s  %-26s  %-10s  %-12s  %s\n" \
        "ID" "Created" "Size" "Status" "URI"
    printf "%-6s  %-26s  %-10s  %-12s  %s\n" \
        "------" "--------------------------" "----------" "------------" "---"

    # Parse and display each entry
    # Sort by ID numerically for consistent display
    echo "${ENTRIES_RESPONSE}" | jq -r '
        .Members
        | sort_by(.Id | tonumber)
        | .[]
        | [.Id, .Created, (.AdditionalDataSizeBytes // 0 | tostring), .DiagnosticDataType, ."@odata.id"]
        | @tsv' 2>/dev/null | while IFS=$'\t' read -r ID CREATED SIZE_BYTES TYPE URI; do

        HUMAN_SIZE=$(format_size "${SIZE_BYTES}")

        printf "%-6s  %-26s  %-10s  %-12s  %s\n" \
            "${ID}" "${CREATED}" "${HUMAN_SIZE}" "${TYPE:-Manager}" "${URI}"
    done

    # Show total size
    echo ""
    TOTAL_BYTES=$(echo "${ENTRIES_RESPONSE}" | jq '[.Members[]?.AdditionalDataSizeBytes // 0] | add // 0' 2>/dev/null)
    TOTAL_HUMAN=$(format_size "${TOTAL_BYTES}")
    echo "Total size: ${TOTAL_HUMAN} (${TOTAL_BYTES} bytes)"
}

# ---------------------------------------------------------------------------
# Step 3: Show management commands
# ---------------------------------------------------------------------------

show_commands() {
    echo ""
    echo "=== Management Commands ==="
    echo ""
    echo "Download a specific dump:"
    echo "  curl -k -u ${USERNAME}:*** -o dump.tar.xz \\"
    echo "    -H 'Accept: application/octet-stream' \\"
    echo "    ${DUMP_SERVICE}/Entries/<ID>/attachment"
    echo ""
    echo "Delete a specific dump:"
    echo "  curl -k -u ${USERNAME}:*** -X DELETE \\"
    echo "    ${DUMP_SERVICE}/Entries/<ID>"
    echo ""
    echo "Delete all dumps:"
    echo "  curl -k -u ${USERNAME}:*** -X POST \\"
    echo "    ${DUMP_SERVICE}/Actions/LogService.ClearLog"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_dependencies
verify_dump_service
list_dumps
show_commands
