#!/bin/bash
#
# Dump Boot POST Code Sequence
#
# Retrieves and displays the complete POST code sequence from one or more
# boot cycles. Shows each code with its timestamp, making it easy to
# identify where a boot stalled or how long each phase took.
#
# Usage:
#   ./dump-boot-sequence.sh [BOOT_INDEX] [BMC_HOST]
#
# Arguments:
#   BOOT_INDEX - Boot cycle to dump: 1 = most recent (default), 2 = previous, etc.
#   BMC_HOST   - BMC hostname or IP for Redfish queries (default: localhost)
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - phosphor-post-code-manager service running
#   - At least one host boot cycle completed

set -euo pipefail

BOOT_INDEX="${1:-1}"
BMC_HOST="${2:-localhost}"
USERNAME="${USERNAME:-root}"
PASSWORD="${PASSWORD:-0penBmc}"

POSTCODE_SERVICE="xyz.openbmc_project.State.Boot.PostCode0"
POSTCODE_PATH="/xyz/openbmc_project/State/Boot/PostCode0"
POSTCODE_IFACE="xyz.openbmc_project.State.Boot.PostCode"

echo "========================================"
echo "POST Code Boot Sequence Dump"
echo "Boot cycle: $BOOT_INDEX (1 = most recent)"
echo "========================================"
echo ""

# --- 1. Check available boot cycles ---
echo "1. Available Boot Cycles"
BOOT_COUNT=$(busctl get-property "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" CurrentBootCycleCount 2>/dev/null \
    | awk '{print $2}') || true

if [ -z "$BOOT_COUNT" ] || [ "$BOOT_COUNT" = "0" ]; then
    echo "   No boot cycles recorded."
    echo "   The host may not have booted yet, or the post-code-manager"
    echo "   service may not be running."
    echo ""
    echo "   Check service: systemctl status $POSTCODE_SERVICE"
    exit 1
fi

echo "   Stored boot cycles: $BOOT_COUNT"

if [ "$BOOT_INDEX" -gt "$BOOT_COUNT" ]; then
    echo "   ERROR: Requested boot cycle $BOOT_INDEX but only $BOOT_COUNT available"
    exit 1
fi
echo ""

# --- 2. Dump POST codes via D-Bus ---
echo "2. POST Code Sequence (D-Bus)"
echo ""
echo "   Index  Timestamp (us)         Code (hex)  Code (dec)"
echo "   -----  ---------------------  ----------  ----------"

# GetPostCodesWithTimeStamp(q bootIndex) -> a(tay)
# Returns array of (timestamp, byte-array) tuples
RAW_OUTPUT=$(busctl call "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" GetPostCodesWithTimeStamp q "$BOOT_INDEX" 2>/dev/null) || true

if [ -z "$RAW_OUTPUT" ]; then
    echo "   Could not retrieve POST codes for boot cycle $BOOT_INDEX"
    echo "   Try: busctl introspect $POSTCODE_SERVICE $POSTCODE_PATH"
    exit 1
fi

# Parse the D-Bus response
# Format: a(tay) N <timestamp> <array_len> <byte1> [byte2...] ...
# Each entry is a timestamp (uint64) followed by a byte array (the POST code)
CODE_COUNT=0
FIRST_TS=""
LAST_TS=""

# Use busctl --json=short for structured parsing if available, otherwise
# fall back to the text output
if busctl --json=short call "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" GetPostCodesWithTimeStamp q "$BOOT_INDEX" &>/dev/null; then

    JSON_OUTPUT=$(busctl --json=short call "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
        "$POSTCODE_IFACE" GetPostCodesWithTimeStamp q "$BOOT_INDEX" 2>/dev/null)

    if command -v jq &>/dev/null && [ -n "$JSON_OUTPUT" ]; then
        echo "$JSON_OUTPUT" | jq -r '
            .data[0] // [] | to_entries[] |
            "   \(.key + 1 | tostring | if length < 5 then " " * (5 - length) + . else . end)  \(.value[0])  \(.value[1] | map(tostring) | join(",") | if length > 0 then . else "0" end)"
        ' 2>/dev/null | while IFS= read -r line; do
            # Re-format with hex conversion
            IDX=$(echo "$line" | awk '{print $1}')
            TS=$(echo "$line" | awk '{print $2}')
            CODE_STR=$(echo "$line" | awk '{print $3}')
            # Take first byte as the POST code
            CODE=$(echo "$CODE_STR" | cut -d',' -f1)
            if [ -n "$CODE" ] && [ "$CODE" != "null" ]; then
                printf "   %5s  %-21s  0x%02X        %d\n" "$IDX" "$TS" "$CODE" "$CODE"
                CODE_COUNT=$((CODE_COUNT + 1))
            fi
        done
    fi
fi

# If JSON parsing did not produce output, fall back to text parsing
if [ "$CODE_COUNT" -eq 0 ] 2>/dev/null; then
    # Parse text format: a(tay) N timestamp arraylen byte ...
    echo "$RAW_OUTPUT" | tr ' ' '\n' | awk '
    BEGIN { idx = 0; state = "skip"; ts = "" }
    /^a\(tay\)$/ { state = "count"; next }
    state == "count" { total = $1; state = "ts"; next }
    state == "ts" { ts = $1; state = "len"; next }
    state == "len" { arrlen = $1; state = "byte"; byteidx = 0; next }
    state == "byte" {
        if (byteidx == 0) {
            idx++
            printf "   %5d  %-21s  0x%02X        %d\n", idx, ts, $1, $1
        }
        byteidx++
        if (byteidx >= arrlen) { state = "ts" }
        next
    }
    '
fi

echo ""

# --- 3. Dump POST codes via Redfish ---
echo "3. POST Code Log (Redfish)"

if command -v curl &>/dev/null; then
    ENTRIES_URL="https://${BMC_HOST}/redfish/v1/Systems/system/LogServices/PostCodes/Entries"
    REDFISH_RESP=$(curl -sk -u "${USERNAME}:${PASSWORD}" "$ENTRIES_URL" 2>/dev/null) || true

    if [ -n "$REDFISH_RESP" ] && command -v jq &>/dev/null; then
        MEMBER_COUNT=$(echo "$REDFISH_RESP" | jq -r '.Members@odata.count // 0' 2>/dev/null)
        echo "   Total Redfish log entries: $MEMBER_COUNT"
        echo ""

        if [ "$MEMBER_COUNT" -gt 0 ]; then
            echo "   Last 10 entries:"
            echo "   ID         Created                    PostCode"
            echo "   ---------  -------------------------  --------"

            echo "$REDFISH_RESP" | jq -r '
                .Members[-10:][] |
                "   \(.Id | if length < 9 then . + " " * (9 - length) else . end)  \(.Created // "N/A" | if length < 25 then . + " " * (25 - length) else . end)  \(.MessageArgs[0] // "N/A")"
            ' 2>/dev/null || echo "   (could not parse entries)"
        fi
    elif [ -n "$REDFISH_RESP" ]; then
        echo "   (install jq for formatted output)"
    else
        echo "   Could not reach Redfish at https://${BMC_HOST}"
    fi
else
    echo "   curl not available, skipping Redfish query"
fi
echo ""

echo "========================================"
echo "Done"
echo "========================================"
