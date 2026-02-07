#!/bin/bash
#
# Test script for OEM Redfish endpoints
#
# Verifies that custom OEM resources are accessible and return valid JSON.
# Designed for use with QEMU (port 2443) or real hardware.
#
# Usage:
#   ./test-oem-endpoint.sh [bmc-host] [username] [password] [vendor]
#
# Examples:
#   ./test-oem-endpoint.sh                           # localhost:2443, defaults
#   ./test-oem-endpoint.sh 192.168.1.100             # real BMC
#   ./test-oem-endpoint.sh localhost:2443 root 0penBmc MyVendor
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BMC_HOST="${1:-localhost:2443}"
USERNAME="${2:-root}"
PASSWORD="${3:-0penBmc}"
# TODO: Replace default vendor name with your vendor
VENDOR="${4:-YourVendor}"

BASE_URL="https://${BMC_HOST}/redfish/v1"
CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"

PASS=0
FAIL=0
SKIP=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

print_header() {
    echo ""
    echo "========================================"
    echo "  OEM Redfish Endpoint Tests"
    echo "  Host:   ${BMC_HOST}"
    echo "  Vendor: ${VENDOR}"
    echo "========================================"
    echo ""
}

# Run a single GET test and check for expected JSON key
# Arguments: test_name url expected_key
test_get() {
    local name="$1"
    local url="$2"
    local key="$3"

    echo "--- ${name} ---"
    echo "GET ${url}"

    local result
    local http_code
    http_code=$($CURL -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null) || true
    result=$($CURL "${url}" 2>/dev/null) || true

    if [ "$http_code" = "000" ]; then
        echo "  SKIP: Could not connect to ${BMC_HOST}"
        SKIP=$((SKIP + 1))
        echo ""
        return
    fi

    if [ "$http_code" = "404" ]; then
        echo "  SKIP: Endpoint not found (OEM routes may not be integrated)"
        echo "  HTTP ${http_code}"
        SKIP=$((SKIP + 1))
        echo ""
        return
    fi

    if [ "$http_code" != "200" ]; then
        echo "  FAIL: Unexpected HTTP status ${http_code}"
        FAIL=$((FAIL + 1))
        echo ""
        return
    fi

    # Check that response is valid JSON with expected key
    if echo "$result" | jq -e ".${key}" > /dev/null 2>&1; then
        echo "  PASS: HTTP ${http_code}, found .${key}"
        echo "$result" | jq "{\"@odata.type\", \"@odata.id\", ${key}}" 2>/dev/null || true
        PASS=$((PASS + 1))
    else
        echo "  FAIL: HTTP ${http_code}, missing .${key} in response"
        echo "$result" | jq '.' 2>/dev/null | head -20 || echo "$result" | head -5
        FAIL=$((FAIL + 1))
    fi
    echo ""
}

print_summary() {
    echo "========================================"
    echo "  Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
    echo "========================================"

    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

print_header

# Test 0: Verify Redfish service root is reachable
echo "--- Prerequisite: Redfish Service Root ---"
echo "GET ${BASE_URL}/"
SVC_CODE=$($CURL -o /dev/null -w "%{http_code}" "${BASE_URL}/" 2>/dev/null) || true

if [ "$SVC_CODE" = "000" ]; then
    echo "  ERROR: Cannot reach ${BMC_HOST}. Is the BMC running?"
    echo "  If using QEMU: ./scripts/run-qemu.sh ast2600-evb"
    exit 1
fi

if [ "$SVC_CODE" != "200" ]; then
    echo "  ERROR: Service root returned HTTP ${SVC_CODE}. Check credentials."
    exit 1
fi

echo "  OK: Service root reachable (HTTP ${SVC_CODE})"
echo ""

# Test 1: OEM Root
test_get \
    "OEM Root" \
    "${BASE_URL}/Oem/${VENDOR}/" \
    "Name"

# Test 2: OEM Health Summary
test_get \
    "OEM Health Summary" \
    "${BASE_URL}/Oem/${VENDOR}/Health" \
    "OverallHealth"

# ---------------------------------------------------------------------------
# TODO: Add tests for your additional OEM endpoints here. Examples:
#
# test_get \
#     "OEM Inventory" \
#     "${BASE_URL}/Oem/${VENDOR}/Inventory" \
#     "SerialNumber"
#
# For POST actions, add a dedicated test function:
#
# test_post() {
#     local name="$1" url="$2" body="$3" key="$4"
#     echo "--- ${name} ---"
#     echo "POST ${url}"
#     local result
#     result=$($CURL -X POST -H "Content-Type: application/json" \
#         -d "${body}" "${url}" 2>/dev/null) || true
#     # ... validate response ...
# }
# ---------------------------------------------------------------------------

# Test 3: Verify standard endpoint still works (sanity check)
test_get \
    "Standard: Managers" \
    "${BASE_URL}/Managers/bmc" \
    "Model"

print_summary
