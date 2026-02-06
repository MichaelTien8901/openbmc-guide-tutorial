#!/bin/bash
#
# SPDM Redfish ComponentIntegrity Queries
#
# Demonstrates querying SPDM attestation results via Redfish API.
# Uses the ComponentIntegrity resource defined in Redfish 2022.2+.
#
# Usage:
#   ./spdm_redfish.sh <bmc-ip> [username] [password]
#
# Prerequisites:
#   - Running OpenBMC with SPDM and bmcweb ComponentIntegrity support
#   - curl and jq installed

set -e

BMC_IP=${1:-localhost}
USERNAME=${2:-root}
PASSWORD=${3:-0penBmc}

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_IP}/redfish/v1"

echo "========================================"
echo "SPDM Redfish ComponentIntegrity"
echo "BMC: ${BMC_IP}"
echo "========================================"
echo ""

# Test 1: Get ComponentIntegrity collection
echo "Test 1: ComponentIntegrity Collection"
echo "GET ${BASE_URL}/ComponentIntegrity"
RESULT=$($CURL "${BASE_URL}/ComponentIntegrity" 2>/dev/null)
if echo "$RESULT" | jq -e '.Members' > /dev/null 2>&1; then
    COUNT=$(echo "$RESULT" | jq '.Members | length')
    echo "  Found $COUNT component(s)"
    echo "$RESULT" | jq '.Members[]."@odata.id"'
    echo ""

    # Test 2: Get details for each component
    echo "Test 2: Component Details"
    echo "$RESULT" | jq -r '.Members[]."@odata.id"' | while read -r URI; do
        echo "---"
        echo "GET ${BASE_URL}${URI}"
        DETAIL=$($CURL "https://${BMC_IP}${URI}" 2>/dev/null)
        if [ -n "$DETAIL" ]; then
            echo "$DETAIL" | jq '{
                Id,
                Name,
                ComponentIntegrityType,
                ComponentIntegrityTypeVersion,
                TargetComponentURI,
                LastUpdated
            }'

            # Show SPDM authentication status
            AUTH_STATUS=$(echo "$DETAIL" | jq -r '.SPDM.IdentityAuthentication.VerificationStatus // "N/A"')
            echo "  Authentication: $AUTH_STATUS"

            # Show measurement summary
            MEAS_COUNT=$(echo "$DETAIL" | jq '.SPDM.MeasurementSet.Measurements | length // 0' 2>/dev/null || echo "0")
            echo "  Measurements: $MEAS_COUNT"
        fi
        echo ""
    done
else
    echo "  ComponentIntegrity not available"
    echo "  Ensure bmcweb is built with: -Dredfish-component-integrity=enabled"
fi
echo ""

# Test 3: Trigger re-attestation (if supported)
echo "Test 3: Trigger Re-attestation"
echo "(Requires a specific component ID — using GPU_0 as example)"
echo ""
echo "POST ${BASE_URL}/ComponentIntegrity/GPU_0/Actions/ComponentIntegrity.SPDMGetSignedMeasurements"
RESULT=$($CURL -X POST \
    -H "Content-Type: application/json" \
    -d '{"Nonce": "test123", "MeasurementIndices": [1, 2, 3]}' \
    "${BASE_URL}/ComponentIntegrity/GPU_0/Actions/ComponentIntegrity.SPDMGetSignedMeasurements" 2>/dev/null)
if echo "$RESULT" | jq -e '.SignedMeasurements' > /dev/null 2>&1; then
    echo "$RESULT" | jq '.'
    echo "  Re-attestation successful"
else
    echo "  Re-attestation not available (expected if no GPU_0 component)"
fi
echo ""

# Test 4: Get component certificate
echo "Test 4: Component Certificate"
echo "GET ${BASE_URL}/ComponentIntegrity/GPU_0/Certificates/0"
RESULT=$($CURL "${BASE_URL}/ComponentIntegrity/GPU_0/Certificates/0" 2>/dev/null)
if echo "$RESULT" | jq -e '.CertificateString' > /dev/null 2>&1; then
    echo "$RESULT" | jq '{CertificateType, Issuer, Subject, ValidNotBefore, ValidNotAfter}'
else
    echo "  Certificate not available (expected if no GPU_0 component)"
fi
echo ""

echo "Test complete!"
