#!/bin/bash
#
# PLDM Endpoint Discovery
#
# Discovers and characterizes PLDM endpoints: queries TID, supported types,
# and available commands for each discovered MCTP endpoint.
#
# Usage:
#   ./pldm_discovery.sh [eid]
#
# Arguments:
#   eid   Optional: specific EID to query (default: scan 8-20)
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - pldmtool installed
#   - MCTP endpoints configured

set -e

TARGET_EID=${1:-}

echo "========================================"
echo "PLDM Endpoint Discovery"
echo "========================================"
echo ""

# Check prerequisites
if ! command -v pldmtool &>/dev/null; then
    echo "Error: pldmtool not found"
    echo "Ensure PLDM packages are installed in image:"
    echo "  IMAGE_INSTALL:append = \" pldm libpldm \""
    exit 1
fi

discover_endpoint() {
    local EID=$1

    # Get TID
    TID_RESULT=$(pldmtool base getTID -m "$EID" 2>/dev/null || true)
    if ! echo "$TID_RESULT" | grep -q "TID" 2>/dev/null; then
        return 1
    fi

    TID=$(echo "$TID_RESULT" | grep -oP '"TID"\s*:\s*\K[0-9]+' || echo "unknown")
    echo "--- Endpoint EID=$EID (TID=$TID) ---"
    echo ""

    # Get supported PLDM types
    echo "  Supported PLDM Types:"
    TYPES_RESULT=$(pldmtool base getPLDMTypes -m "$EID" 2>/dev/null || true)
    if [ -n "$TYPES_RESULT" ]; then
        echo "$TYPES_RESULT" | grep -E "Type|name" | while read -r line; do
            echo "    $line"
        done
    fi
    echo ""

    # Get PLDM version for base type
    echo "  PLDM Base Version:"
    VER_RESULT=$(pldmtool base getPLDMVersion -m "$EID" -t 0 2>/dev/null || true)
    if [ -n "$VER_RESULT" ]; then
        echo "$VER_RESULT" | grep -i "version" | while read -r line; do
            echo "    $line"
        done
    fi
    echo ""

    # Get commands for each supported type
    for TYPE_NUM in 0 2 3 5; do
        TYPE_NAME=""
        case $TYPE_NUM in
            0) TYPE_NAME="Base (Messaging)" ;;
            2) TYPE_NAME="Platform (Sensors/Effecters)" ;;
            3) TYPE_NAME="BIOS Control" ;;
            5) TYPE_NAME="Firmware Update" ;;
        esac

        CMD_RESULT=$(pldmtool base getPLDMCommands -m "$EID" -t "$TYPE_NUM" 2>/dev/null || true)
        if echo "$CMD_RESULT" | grep -qi "command\|name" 2>/dev/null; then
            echo "  Commands for Type $TYPE_NUM ($TYPE_NAME):"
            echo "$CMD_RESULT" | grep -E "name|command" | head -20 | while read -r line; do
                echo "    $line"
            done
            echo ""
        fi
    done

    echo ""
    return 0
}

if [ -n "$TARGET_EID" ]; then
    # Query specific EID
    echo "Querying EID $TARGET_EID..."
    echo ""
    if ! discover_endpoint "$TARGET_EID"; then
        echo "No response from EID $TARGET_EID"
        exit 1
    fi
else
    # Scan EID range
    echo "Scanning EIDs 8-20..."
    echo ""
    FOUND=0
    for EID in $(seq 8 20); do
        if discover_endpoint "$EID" 2>/dev/null; then
            FOUND=$((FOUND + 1))
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "No PLDM endpoints found."
        echo ""
        echo "Check:"
        echo "  mctp endpoint              # List MCTP endpoints"
        echo "  systemctl status mctpd     # MCTP daemon running?"
        echo "  systemctl status pldmd     # PLDM daemon running?"
    else
        echo "Found $FOUND PLDM endpoint(s)"
    fi
fi
