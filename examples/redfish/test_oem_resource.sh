#!/bin/bash
#
# Test script for OEM Redfish resources
#
# Usage:
#   ./test_oem_resource.sh <bmc-ip> [username] [password]
#

set -e

BMC_IP=${1:-localhost}
USERNAME=${2:-root}
PASSWORD=${3:-0penBmc}

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_IP}/redfish/v1"

echo "Testing OEM Redfish Resources on ${BMC_IP}"
echo "============================================"
echo ""

# Test 1: Service Root
echo "Test 1: Service Root"
echo "GET ${BASE_URL}/"
$CURL "${BASE_URL}/" | jq '.Name, .RedfishVersion'
echo ""

# Test 2: OEM Root
echo "Test 2: OEM Root"
echo "GET ${BASE_URL}/Oem/MyVendor/"
RESULT=$($CURL "${BASE_URL}/Oem/MyVendor/" 2>/dev/null)
if echo "$RESULT" | jq -e '.Name' > /dev/null 2>&1; then
    echo "$RESULT" | jq '.Name, .Description'
    echo "✓ OEM Root exists"
else
    echo "✗ OEM Root not found (expected if not integrated)"
fi
echo ""

# Test 3: Board Info
echo "Test 3: Board Info"
echo "GET ${BASE_URL}/Oem/MyVendor/BoardInfo"
RESULT=$($CURL "${BASE_URL}/Oem/MyVendor/BoardInfo" 2>/dev/null)
if echo "$RESULT" | jq -e '.BoardType' > /dev/null 2>&1; then
    echo "$RESULT" | jq '{BoardType, CpuSlots, DimmSlots, MaxPowerWatts}'
    echo "✓ Board Info exists"
else
    echo "✗ Board Info not found (expected if not integrated)"
fi
echo ""

# Test 4: Diagnostic Service
echo "Test 4: Diagnostic Service"
echo "GET ${BASE_URL}/Oem/MyVendor/DiagnosticService"
RESULT=$($CURL "${BASE_URL}/Oem/MyVendor/DiagnosticService" 2>/dev/null)
if echo "$RESULT" | jq -e '.AvailableTests' > /dev/null 2>&1; then
    echo "Available tests:"
    echo "$RESULT" | jq '.AvailableTests[] | {Id, Name}'
    echo "✓ Diagnostic Service exists"
else
    echo "✗ Diagnostic Service not found (expected if not integrated)"
fi
echo ""

# Test 5: Run Diagnostic (optional)
echo "Test 5: Run Diagnostic Action"
read -p "Run diagnostic test? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "POST ${BASE_URL}/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest"
    RESULT=$($CURL -X POST \
        -H "Content-Type: application/json" \
        -d '{"TestId": 1}' \
        "${BASE_URL}/Oem/MyVendor/DiagnosticService/Actions/DiagnosticService.RunTest" 2>/dev/null)
    echo "$RESULT" | jq '.'
fi
echo ""

# Test 6: Standard Redfish endpoints (for comparison)
echo "Test 6: Standard Endpoints (verification)"
echo "GET ${BASE_URL}/Systems/system"
$CURL "${BASE_URL}/Systems/system" | jq '{PowerState, Status}'
echo ""

echo "Test complete!"
