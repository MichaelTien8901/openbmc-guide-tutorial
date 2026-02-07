#!/bin/bash
#
# PECI Bus Probe
#
# Tests PECI connectivity to Intel CPUs on an OpenBMC system.
# Sends Ping and RdPkgConfig commands to verify the PECI bus is functional
# and the CPU is responding.
#
# Usage:
#   ./peci-probe.sh [cpu-address]
#
#   cpu-address  PECI client address (default: 0x30 for CPU 0)
#                Common values: 0x30=CPU0, 0x31=CPU1, 0x32=CPU2, 0x33=CPU3
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware) with PECI support
#   - peci_cmds utility installed (from peci-pcie package)
#   - Host CPU powered on (PECI requires CPU power)
#
# Examples:
#   ./peci-probe.sh              # Probe CPU 0 at default address 0x30
#   ./peci-probe.sh 0x31         # Probe CPU 1 at address 0x31
#   ./peci-probe.sh all          # Probe all common CPU addresses

set -euo pipefail

# Default PECI client address for CPU 0
DEFAULT_ADDR="0x30"

# All common PECI client addresses (CPU 0-3)
ALL_ADDRS=("0x30" "0x31" "0x32" "0x33")

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

usage() {
    echo "PECI Bus Probe"
    echo ""
    echo "Usage: $0 [cpu-address|all]"
    echo ""
    echo "Arguments:"
    echo "  cpu-address  PECI client address in hex (default: 0x30)"
    echo "  all          Probe all common CPU addresses (0x30-0x33)"
    echo ""
    echo "Common PECI addresses:"
    echo "  0x30  CPU 0"
    echo "  0x31  CPU 1"
    echo "  0x32  CPU 2"
    echo "  0x33  CPU 3"
    echo ""
    echo "Examples:"
    echo "  $0             # Probe CPU 0"
    echo "  $0 0x31        # Probe CPU 1"
    echo "  $0 all         # Probe all CPUs"
}

# Check that peci_cmds is available
check_prerequisites() {
    if ! command -v peci_cmds &>/dev/null; then
        echo "ERROR: peci_cmds not found."
        echo ""
        echo "Install the peci-pcie package:"
        echo "  IMAGE_INSTALL:append = \" peci-pcie \""
        echo ""
        echo "Or check if the binary is at a different path:"
        echo "  find / -name 'peci_cmds' 2>/dev/null"
        exit 1
    fi
}

# Probe a single PECI address
# Arguments: $1 = PECI client address (e.g., 0x30)
probe_address() {
    local addr="$1"
    local cpu_num
    # Derive CPU number from address (0x30=CPU0, 0x31=CPU1, etc.)
    cpu_num=$(( $(printf '%d' "$addr") - $(printf '%d' "0x30") ))

    echo "--- CPU $cpu_num (address $addr) ---"
    echo ""

    # Step 1: Ping the PECI client
    echo "1. PECI Ping"
    if peci_cmds Ping "$addr" 2>/dev/null; then
        pass "CPU $cpu_num responds to Ping at $addr"
    else
        fail "CPU $cpu_num did not respond to Ping at $addr"
        echo "       Is the host CPU powered on?"
        echo "       Check: obmcutil state"
        echo ""
        return
    fi
    echo ""

    # Step 2: Read Package Config - Index 0 (CPU temperature)
    # RdPkgConfig arguments: address, index, parameter
    # Index 0, Parameter 0 = Package temperature (DTS value)
    echo "2. RdPkgConfig (CPU Temperature - DTS)"
    local pkg_result
    pkg_result=$(peci_cmds RdPkgConfig "$addr" 0 0 2>&1) || true
    if [ -n "$pkg_result" ]; then
        echo "       Raw response: $pkg_result"
        pass "RdPkgConfig succeeded for CPU $cpu_num"
    else
        fail "RdPkgConfig failed for CPU $cpu_num"
    fi
    echo ""

    # Step 3: Read Package Config - Index 0, Parameter 2 (Tjmax)
    # Tjmax is the maximum junction temperature; actual temp = Tjmax - DTS
    echo "3. RdPkgConfig (Tjmax)"
    local tjmax_result
    tjmax_result=$(peci_cmds RdPkgConfig "$addr" 0 2 2>&1) || true
    if [ -n "$tjmax_result" ]; then
        echo "       Raw response: $tjmax_result"
        pass "Tjmax read succeeded for CPU $cpu_num"
    else
        warn "Tjmax read failed for CPU $cpu_num (may not be supported)"
    fi
    echo ""

    # Step 4: Check if PECI hwmon device exists for this CPU
    echo "4. Hwmon PECI Device"
    local found_hwmon=0
    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        if [ -f "$hwmon_dir/name" ]; then
            local hwmon_name
            hwmon_name=$(cat "$hwmon_dir/name" 2>/dev/null || true)
            if [[ "$hwmon_name" == *peci* ]] || [[ "$hwmon_name" == *coretemp* ]]; then
                echo "       Found: $hwmon_dir ($hwmon_name)"
                found_hwmon=1
            fi
        fi
    done
    if [ "$found_hwmon" -eq 1 ]; then
        pass "PECI hwmon device found"
    else
        warn "No PECI hwmon device found (driver may not be loaded)"
        echo "       Check: ls /sys/bus/peci/devices/"
        echo "       Check: dmesg | grep -i peci"
    fi
    echo ""

    # Step 5: Check PECI bus sysfs
    echo "5. PECI Bus Sysfs"
    if [ -d /sys/bus/peci ]; then
        local peci_devices
        peci_devices=$(ls /sys/bus/peci/devices/ 2>/dev/null || true)
        if [ -n "$peci_devices" ]; then
            echo "       Devices: $peci_devices"
            pass "PECI bus has registered devices"
        else
            warn "PECI bus exists but no devices registered"
        fi
    else
        fail "PECI bus not found in sysfs"
        echo "       Enable CONFIG_PECI=y and CONFIG_PECI_ASPEED=y in kernel"
    fi
    echo ""
}

# --- Main ---

check_prerequisites

# Handle -h/--help
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

echo "========================================"
echo "PECI Bus Probe"
echo "========================================"
echo ""

if [[ "${1:-}" == "all" ]]; then
    # Probe all common addresses
    for addr in "${ALL_ADDRS[@]}"; do
        probe_address "$addr"
    done
else
    # Probe single address (default or user-specified)
    ADDR="${1:-$DEFAULT_ADDR}"
    probe_address "$ADDR"
fi

# --- Summary ---
echo "========================================"
echo "Summary: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Troubleshooting:"
    echo "  obmcutil state                    # Check host power state"
    echo "  dmesg | grep -i peci             # Kernel PECI messages"
    echo "  ls /sys/bus/peci/devices/         # PECI bus devices"
    echo "  cat /sys/class/hwmon/hwmon*/name  # Hwmon device names"
    exit 1
fi
