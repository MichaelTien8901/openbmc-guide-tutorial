#!/bin/bash
#
# MCTP/PLDM Health Check
#
# Verifies MCTP and PLDM stack connectivity on a running OpenBMC system.
# Checks daemon status, link state, endpoints, and basic PLDM responses.
#
# Usage:
#   ./mctp_health_check.sh
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - mctpd and pldmd services enabled

set -e

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

echo "========================================"
echo "MCTP/PLDM Health Check"
echo "========================================"
echo ""

# --- 1. Kernel MCTP support ---
echo "1. Kernel MCTP Support"
if lsmod 2>/dev/null | grep -q mctp; then
    pass "MCTP kernel module loaded"
elif [ -d /sys/class/net ] && ls /sys/class/net/ | grep -q mctp 2>/dev/null; then
    pass "MCTP kernel support built-in"
else
    warn "MCTP kernel module not detected (may be built-in)"
fi
echo ""

# --- 2. MCTP daemon ---
echo "2. MCTP Daemon (mctpd)"
if systemctl is-active --quiet mctpd 2>/dev/null; then
    pass "mctpd is running"
else
    fail "mctpd is not running"
    echo "       Try: systemctl start mctpd"
fi
echo ""

# --- 3. PLDM daemon ---
echo "3. PLDM Daemon (pldmd)"
if systemctl is-active --quiet pldmd 2>/dev/null; then
    pass "pldmd is running"
else
    fail "pldmd is not running"
    echo "       Try: systemctl start pldmd"
fi
echo ""

# --- 4. MCTP links ---
echo "4. MCTP Links"
if command -v mctp &>/dev/null; then
    LINKS=$(mctp link 2>/dev/null || true)
    if [ -n "$LINKS" ]; then
        echo "$LINKS" | while read -r line; do
            echo "       $line"
        done
        pass "MCTP links found"
    else
        warn "No MCTP links configured"
        echo "       Try: mctp link add mctpi2c1 type i2c bus 1"
    fi
else
    warn "'mctp' command not found"
fi
echo ""

# --- 5. MCTP endpoints ---
echo "5. MCTP Endpoints"
if command -v mctp &>/dev/null; then
    ENDPOINTS=$(mctp endpoint 2>/dev/null || true)
    if [ -n "$ENDPOINTS" ]; then
        echo "$ENDPOINTS" | while read -r line; do
            echo "       $line"
        done
        pass "MCTP endpoints discovered"
    else
        warn "No MCTP endpoints found"
    fi
else
    warn "'mctp' command not found"
fi
echo ""

# --- 6. MCTP D-Bus service ---
echo "6. MCTP D-Bus Service"
if busctl list 2>/dev/null | grep -q "xyz.openbmc_project.MCTP"; then
    pass "MCTP D-Bus service registered"
    echo "       Hierarchy:"
    busctl tree xyz.openbmc_project.MCTP 2>/dev/null | head -20 | while read -r line; do
        echo "         $line"
    done
else
    warn "MCTP D-Bus service not found"
fi
echo ""

# --- 7. PLDM D-Bus service ---
echo "7. PLDM D-Bus Service"
if busctl list 2>/dev/null | grep -q "xyz.openbmc_project.PLDM"; then
    pass "PLDM D-Bus service registered"
    echo "       Hierarchy:"
    busctl tree xyz.openbmc_project.PLDM 2>/dev/null | head -20 | while read -r line; do
        echo "         $line"
    done
else
    warn "PLDM D-Bus service not found"
fi
echo ""

# --- 8. PLDM endpoint TID check ---
echo "8. PLDM Endpoint Communication"
if command -v pldmtool &>/dev/null; then
    # Try common EIDs (host is typically 9)
    for EID in 9 10 11; do
        RESULT=$(pldmtool base getTID -m "$EID" 2>/dev/null || true)
        if echo "$RESULT" | grep -q "TID" 2>/dev/null; then
            TID=$(echo "$RESULT" | grep -oP '"TID"\s*:\s*\K[0-9]+' || echo "?")
            pass "EID $EID responds (TID=$TID)"
        fi
    done
    if [ $PASS -eq 0 ] 2>/dev/null; then
        warn "No PLDM endpoints responded at EIDs 9, 10, 11"
    fi
else
    warn "'pldmtool' command not found"
fi
echo ""

# --- Summary ---
echo "========================================"
echo "Summary: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Troubleshooting:"
    echo "  journalctl -u mctpd -f    # MCTP daemon logs"
    echo "  journalctl -u pldmd -f    # PLDM daemon logs"
    echo "  mctp link                  # List MCTP interfaces"
    echo "  mctp endpoint              # List discovered endpoints"
    exit 1
fi
