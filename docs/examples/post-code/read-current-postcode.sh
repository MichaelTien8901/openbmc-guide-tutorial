#!/bin/bash
#
# Read Current POST Code
#
# Queries the current (most recent) POST code from the host via both D-Bus
# (busctl) and Redfish. Useful for quick checks during boot or when
# diagnosing a hung host.
#
# Usage:
#   ./read-current-postcode.sh [BMC_HOST]
#
# Arguments:
#   BMC_HOST  - BMC hostname or IP for Redfish queries (default: localhost)
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - phosphor-post-code-manager service running
#   - Host powered on or in boot process

set -euo pipefail

BMC_HOST="${1:-localhost}"
USERNAME="${USERNAME:-root}"
PASSWORD="${PASSWORD:-0penBmc}"

POSTCODE_SERVICE="xyz.openbmc_project.State.Boot.PostCode0"
POSTCODE_PATH="/xyz/openbmc_project/State/Boot/PostCode0"
POSTCODE_IFACE="xyz.openbmc_project.State.Boot.PostCode"

HOST_SERVICE="xyz.openbmc_project.State.Host"
HOST_PATH="/xyz/openbmc_project/state/host0"
PROGRESS_IFACE="xyz.openbmc_project.State.Boot.Progress"

echo "========================================"
echo "Current POST Code Reader"
echo "========================================"
echo ""

# --- 1. Host power state ---
echo "1. Host Power State"
HOST_STATE=$(busctl get-property "$HOST_SERVICE" "$HOST_PATH" \
    xyz.openbmc_project.State.Host CurrentHostState 2>/dev/null \
    | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}') || true

if [ -n "$HOST_STATE" ]; then
    echo "   State: $HOST_STATE"
else
    echo "   State: Unknown (host state service may not be running)"
fi
echo ""

# --- 2. Current POST code via D-Bus ---
echo "2. Current POST Code (D-Bus)"

# GetPostCodesWithTimeStamp returns the boot cycle's codes; read the last entry
# Method signature: GetPostCodesWithTimeStamp(q bootIndex) -> a(tay)
# Boot index 1 = most recent boot cycle
CURRENT_CODE=$(busctl call "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" GetPostCodesWithTimeStamp q 1 2>/dev/null) || true

if [ -n "$CURRENT_CODE" ]; then
    # Extract the last POST code value from the array
    # The response format is: a(tay) N timestamp [bytes] ...
    # Parse the last byte array entry for the most recent code
    LAST_CODE=$(echo "$CURRENT_CODE" | awk '{
        last = ""
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+$/ && $(i-1) ~ /^[0-9]+$/) {
                last = $i
            }
        }
        if (last != "") print last
    }')

    if [ -n "$LAST_CODE" ]; then
        printf "   POST Code: 0x%02X (%d)\n" "$LAST_CODE" "$LAST_CODE"
    else
        echo "   No POST codes recorded for current boot cycle"
    fi
else
    echo "   Could not read POST code (service may not be running)"
    echo "   Try: systemctl status $POSTCODE_SERVICE"
fi
echo ""

# --- 3. Boot progress via D-Bus ---
echo "3. Boot Progress (D-Bus)"
BOOT_PROGRESS=$(busctl get-property "$HOST_SERVICE" "$HOST_PATH" \
    "$PROGRESS_IFACE" BootProgress 2>/dev/null \
    | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}') || true

if [ -n "$BOOT_PROGRESS" ]; then
    echo "   Progress: $BOOT_PROGRESS"
else
    echo "   Progress: Unknown (boot progress property not available)"
fi
echo ""

# --- 4. Current POST code via Redfish ---
echo "4. System Boot Progress (Redfish)"

if command -v curl &>/dev/null; then
    REDFISH_RESP=$(curl -sk -u "${USERNAME}:${PASSWORD}" \
        "https://${BMC_HOST}/redfish/v1/Systems/system" 2>/dev/null) || true

    if [ -n "$REDFISH_RESP" ]; then
        if command -v jq &>/dev/null; then
            LAST_STATE=$(echo "$REDFISH_RESP" | jq -r '.BootProgress.LastState // "N/A"' 2>/dev/null)
            OEM_POST=$(echo "$REDFISH_RESP" | jq -r '.BootProgress.OemLastBootProgressCode // "N/A"' 2>/dev/null)
            POWER_STATE=$(echo "$REDFISH_RESP" | jq -r '.PowerState // "N/A"' 2>/dev/null)

            echo "   Power State:     $POWER_STATE"
            echo "   Last State:      $LAST_STATE"
            echo "   OEM POST Code:   $OEM_POST"
        else
            # Fallback without jq: grep for relevant fields
            echo "   (install jq for formatted output)"
            echo "$REDFISH_RESP" | grep -oP '"LastState"\s*:\s*"[^"]*"' || true
            echo "$REDFISH_RESP" | grep -oP '"PowerState"\s*:\s*"[^"]*"' || true
        fi
    else
        echo "   Could not reach Redfish at https://${BMC_HOST}"
    fi
else
    echo "   curl not available, skipping Redfish query"
fi
echo ""

# --- 5. POST code log entry count ---
echo "5. POST Code Log Entries"
BOOT_COUNT=$(busctl get-property "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" CurrentBootCycleCount 2>/dev/null \
    | awk '{print $2}') || true

if [ -n "$BOOT_COUNT" ]; then
    echo "   Stored boot cycles: $BOOT_COUNT"
else
    echo "   Could not read boot cycle count"
fi

MAX_CYCLES=$(busctl get-property "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
    "$POSTCODE_IFACE" MaxBootCycleNum 2>/dev/null \
    | awk '{print $2}') || true

if [ -n "$MAX_CYCLES" ]; then
    echo "   Max stored cycles:  $MAX_CYCLES"
fi
echo ""

echo "========================================"
echo "Done"
echo "========================================"
