#!/bin/bash
#
# Monitor Boot Progress
#
# Polls the BootProgress D-Bus property in real-time during host boot,
# displaying state transitions as they happen. Optionally monitors POST
# codes alongside boot progress for a complete view of the boot sequence.
#
# Usage:
#   ./monitor-boot-progress.sh [POLL_INTERVAL] [--with-postcode]
#
# Arguments:
#   POLL_INTERVAL   - Seconds between polls (default: 1)
#   --with-postcode - Also poll and display current POST code each interval
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - phosphor-host-state-manager service running
#   - Host powered on or about to be powered on
#
# Exit:
#   Press Ctrl+C to stop monitoring.
#   The script also exits automatically when BootProgress reaches
#   "OSRunning" or the host powers off.

set -euo pipefail

# --- Parse arguments ---
POLL_INTERVAL=1
WITH_POSTCODE=false

for arg in "$@"; do
    case "$arg" in
        --with-postcode)
            WITH_POSTCODE=true
            ;;
        [0-9]*)
            POLL_INTERVAL="$arg"
            ;;
    esac
done

# --- D-Bus constants ---
HOST_SERVICE="xyz.openbmc_project.State.Host"
HOST_PATH="/xyz/openbmc_project/state/host0"
PROGRESS_IFACE="xyz.openbmc_project.State.Boot.Progress"
HOST_IFACE="xyz.openbmc_project.State.Host"

POSTCODE_SERVICE="xyz.openbmc_project.State.Boot.PostCode0"
POSTCODE_PATH="/xyz/openbmc_project/State/Boot/PostCode0"
POSTCODE_IFACE="xyz.openbmc_project.State.Boot.PostCode"

# --- State tracking ---
PREV_PROGRESS=""
PREV_HOST_STATE=""
PREV_POSTCODE=""
TRANSITION_COUNT=0
START_TIME=$(date +%s)

# --- Cleanup on exit ---
cleanup() {
    echo ""
    echo "========================================"
    ELAPSED=$(( $(date +%s) - START_TIME ))
    echo "Monitoring stopped after ${ELAPSED}s"
    echo "State transitions observed: $TRANSITION_COUNT"
    echo "========================================"
}
trap cleanup EXIT

# --- Helper: get short enum value ---
# Extracts the last segment from D-Bus enum strings like
# "xyz.openbmc_project.State.Boot.Progress.ProgressStages.MemoryInit"
# -> "MemoryInit"
short_enum() {
    echo "$1" | awk -F'.' '{print $NF}'
}

echo "========================================"
echo "Boot Progress Monitor"
echo "Poll interval: ${POLL_INTERVAL}s"
echo "POST code tracking: $WITH_POSTCODE"
echo "========================================"
echo ""
echo "Waiting for boot activity... (Ctrl+C to stop)"
echo ""

if [ "$WITH_POSTCODE" = true ]; then
    printf "%-12s  %-20s  %-18s  %-10s\n" "Timestamp" "Boot Progress" "Host State" "POST Code"
    printf "%-12s  %-20s  %-18s  %-10s\n" "------------" "--------------------" "------------------" "----------"
else
    printf "%-12s  %-20s  %-18s\n" "Timestamp" "Boot Progress" "Host State"
    printf "%-12s  %-20s  %-18s\n" "------------" "--------------------" "------------------"
fi

while true; do
    TIMESTAMP=$(date '+%H:%M:%S')

    # Read BootProgress
    RAW_PROGRESS=$(busctl get-property "$HOST_SERVICE" "$HOST_PATH" \
        "$PROGRESS_IFACE" BootProgress 2>/dev/null \
        | awk -F'"' '{print $2}') || true
    BOOT_PROGRESS=$(short_enum "${RAW_PROGRESS:-Unknown}")

    # Read host state
    RAW_STATE=$(busctl get-property "$HOST_SERVICE" "$HOST_PATH" \
        "$HOST_IFACE" CurrentHostState 2>/dev/null \
        | awk -F'"' '{print $2}') || true
    HOST_STATE=$(short_enum "${RAW_STATE:-Unknown}")

    # Read POST code if requested
    POSTCODE_STR=""
    if [ "$WITH_POSTCODE" = true ]; then
        # Get the most recent POST code from the current boot cycle
        RAW_CODE=$(busctl call "$POSTCODE_SERVICE" "$POSTCODE_PATH" \
            "$POSTCODE_IFACE" GetPostCodesWithTimeStamp q 1 2>/dev/null) || true

        if [ -n "$RAW_CODE" ]; then
            # Extract last byte value from the response
            LAST_BYTE=$(echo "$RAW_CODE" | awk '{
                last = ""
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[0-9]+$/ && $(i-1) ~ /^[0-9]+$/) {
                        last = $i
                    }
                }
                if (last != "") print last
            }')

            if [ -n "$LAST_BYTE" ]; then
                POSTCODE_STR=$(printf "0x%02X" "$LAST_BYTE" 2>/dev/null) || true
            fi
        fi
    fi

    # Detect changes and print
    CHANGED=false
    if [ "$BOOT_PROGRESS" != "$PREV_PROGRESS" ] || \
       [ "$HOST_STATE" != "$PREV_HOST_STATE" ] || \
       [ "$POSTCODE_STR" != "$PREV_POSTCODE" ]; then
        CHANGED=true
    fi

    if [ "$CHANGED" = true ]; then
        if [ "$WITH_POSTCODE" = true ]; then
            printf "%-12s  %-20s  %-18s  %-10s" \
                "$TIMESTAMP" "$BOOT_PROGRESS" "$HOST_STATE" "${POSTCODE_STR:-N/A}"
        else
            printf "%-12s  %-20s  %-18s" \
                "$TIMESTAMP" "$BOOT_PROGRESS" "$HOST_STATE"
        fi

        # Mark transitions
        if [ "$BOOT_PROGRESS" != "$PREV_PROGRESS" ] && [ -n "$PREV_PROGRESS" ]; then
            TRANSITION_COUNT=$((TRANSITION_COUNT + 1))
            printf "  <-- progress changed"
        fi
        if [ "$HOST_STATE" != "$PREV_HOST_STATE" ] && [ -n "$PREV_HOST_STATE" ]; then
            printf "  <-- state changed"
        fi
        echo ""

        PREV_PROGRESS="$BOOT_PROGRESS"
        PREV_HOST_STATE="$HOST_STATE"
        PREV_POSTCODE="$POSTCODE_STR"
    fi

    # Auto-exit conditions
    if [ "$BOOT_PROGRESS" = "OSRunning" ]; then
        echo ""
        echo "Host has reached OS. Boot complete."
        exit 0
    fi

    if [ "$HOST_STATE" = "Off" ] && [ -n "$PREV_HOST_STATE" ] && \
       [ "$PREV_HOST_STATE" != "Off" ] && [ "$PREV_HOST_STATE" != "Unknown" ]; then
        echo ""
        echo "Host powered off unexpectedly during boot."
        exit 1
    fi

    sleep "$POLL_INTERVAL"
done
