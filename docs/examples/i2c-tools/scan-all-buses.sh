#!/bin/bash
#
# I2C Bus Scanner
#
# Iterates all available I2C buses (/dev/i2c-*) and runs i2cdetect on each,
# producing a formatted summary of discovered devices. Optionally scans a
# single bus when the -b flag is provided.
#
# Usage:
#   ./scan-all-buses.sh              # Scan all buses
#   ./scan-all-buses.sh -b 0         # Scan bus 0 only
#   ./scan-all-buses.sh -h           # Show help
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - i2c-tools installed (i2cdetect)
#
# Note:
#   Uses i2cdetect -y (non-interactive). The -y flag skips the
#   confirmation prompt, which is safe for read-only detection but
#   may disturb some sensitive devices. Use with care on production
#   systems.

set -euo pipefail

# --- Configuration ---
SCAN_BUS=""
TOTAL_DEVICES=0

# --- Usage ---
usage() {
    echo "I2C Bus Scanner"
    echo ""
    echo "Usage: $0 [-b BUS] [-h]"
    echo ""
    echo "Options:"
    echo "  -b BUS   Scan only the specified bus number (e.g., 0, 1, 2)"
    echo "  -h       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Scan all I2C buses"
    echo "  $0 -b 0         # Scan bus 0 only"
    echo "  $0 -b 3         # Scan bus 3 only"
    echo ""
    echo "Requires: i2c-tools (i2cdetect)"
}

# --- Parse arguments ---
while getopts "b:h" opt; do
    case "$opt" in
        b) SCAN_BUS="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# --- Check prerequisites ---
if ! command -v i2cdetect &>/dev/null; then
    echo "Error: i2cdetect not found"
    echo "Ensure i2c-tools is installed in the image:"
    echo "  IMAGE_INSTALL:append = \" i2c-tools \""
    exit 1
fi

# --- Count devices on a single bus ---
# Parses i2cdetect output and counts non-empty addresses (UU or hex values).
count_devices() {
    local bus=$1
    local count=0
    local addresses=""

    # Run i2cdetect and parse addresses from the output.
    # i2cdetect output lines look like: "00: -- -- -- 03 -- -- -- --  ..."
    # Addresses show as two-digit hex (e.g., 48) or "UU" (in use by driver).
    while IFS= read -r line; do
        # Skip header lines (those not starting with a hex row prefix)
        if ! echo "$line" | grep -qE '^[0-9a-f][0-9a-f]:'; then
            continue
        fi

        # Extract detected addresses (hex values or UU)
        for token in $line; do
            if echo "$token" | grep -qE '^[0-9a-f][0-9a-f]$'; then
                count=$((count + 1))
                addresses="$addresses 0x$token"
            elif [ "$token" = "UU" ]; then
                count=$((count + 1))
                addresses="$addresses UU"
            fi
        done
    done < <(i2cdetect -y "$bus" 2>/dev/null)

    echo "$count"
    if [ -n "$addresses" ]; then
        echo "$addresses"
    fi
}

# --- Scan a single bus ---
scan_bus() {
    local bus=$1
    local bus_name

    # Get bus name from i2cdetect -l
    bus_name=$(i2cdetect -l 2>/dev/null | grep "i2c-${bus}[[:space:]]" | sed 's/.*\t//' || echo "unknown")

    echo "--- I2C Bus $bus ($bus_name) ---"
    echo ""

    # Run full i2cdetect scan
    i2cdetect -y "$bus" 2>/dev/null || {
        echo "  Error: could not scan bus $bus"
        echo ""
        return 1
    }
    echo ""

    # Count and list found devices
    local result
    result=$(count_devices "$bus")
    local device_count
    device_count=$(echo "$result" | head -1)
    local device_addrs
    device_addrs=$(echo "$result" | tail -1)

    if [ "$device_count" -gt 0 ] 2>/dev/null; then
        echo "  Found $device_count device(s):$device_addrs"
        TOTAL_DEVICES=$((TOTAL_DEVICES + device_count))
    else
        echo "  No devices found"
    fi
    echo ""
}

# --- Main ---
echo "========================================"
echo "I2C Bus Scanner"
echo "========================================"
echo ""

if [ -n "$SCAN_BUS" ]; then
    # Scan a specific bus
    if [ ! -e "/dev/i2c-${SCAN_BUS}" ]; then
        echo "Error: /dev/i2c-${SCAN_BUS} does not exist"
        echo ""
        echo "Available buses:"
        i2cdetect -l 2>/dev/null || ls /dev/i2c-* 2>/dev/null || echo "  No I2C buses found"
        exit 1
    fi
    scan_bus "$SCAN_BUS"
else
    # Scan all buses
    echo "Available buses:"
    i2cdetect -l 2>/dev/null || true
    echo ""

    BUS_COUNT=0
    for dev in /dev/i2c-*; do
        if [ ! -e "$dev" ]; then
            echo "No I2C buses found (/dev/i2c-* does not exist)"
            echo ""
            echo "Check:"
            echo "  - I2C kernel modules loaded: lsmod | grep i2c"
            echo "  - Device tree I2C nodes enabled: ls /sys/bus/i2c/devices/"
            exit 1
        fi

        bus_num="${dev##/dev/i2c-}"
        scan_bus "$bus_num"
        BUS_COUNT=$((BUS_COUNT + 1))
    done
fi

# --- Summary ---
echo "========================================"
if [ -n "$SCAN_BUS" ]; then
    echo "Summary: Bus $SCAN_BUS - $TOTAL_DEVICES device(s) found"
else
    echo "Summary: Scanned ${BUS_COUNT:-0} bus(es), $TOTAL_DEVICES total device(s) found"
fi
echo "========================================"
