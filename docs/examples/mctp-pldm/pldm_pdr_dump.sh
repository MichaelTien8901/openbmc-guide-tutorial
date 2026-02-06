#!/bin/bash
#
# PLDM PDR Repository Dump
#
# Extracts and displays Platform Descriptor Records (PDRs) from a PLDM endpoint.
# PDRs define sensors, effecters, entity associations, and terminus info.
#
# Usage:
#   ./pldm_pdr_dump.sh <eid> [pdr-type]
#
# Arguments:
#   eid         MCTP Endpoint ID (required)
#   pdr-type    Optional: filter by type (default: all)
#               Values: all, numericSensorPDR, stateSensorPDR,
#                       numericEffecterPDR, stateEffecterPDR,
#                       terminusLocatorPDR, entityAssociationPDR
#
# Examples:
#   ./pldm_pdr_dump.sh 9                          # All PDRs
#   ./pldm_pdr_dump.sh 9 numericSensorPDR         # Only numeric sensor PDRs
#   ./pldm_pdr_dump.sh 9 terminusLocatorPDR       # Terminus info
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - pldmtool installed

set -e

EID=${1:?Usage: $0 <eid> [pdr-type]}
PDR_TYPE=${2:-all}

echo "========================================"
echo "PLDM PDR Repository Dump"
echo "EID=$EID  Type=$PDR_TYPE"
echo "========================================"
echo ""

if ! command -v pldmtool &>/dev/null; then
    echo "Error: pldmtool not found"
    exit 1
fi

# Verify endpoint
TID_RESULT=$(pldmtool base getTID -m "$EID" 2>/dev/null || true)
if ! echo "$TID_RESULT" | grep -q "TID" 2>/dev/null; then
    echo "Error: EID $EID not responding"
    exit 1
fi

if [ "$PDR_TYPE" = "all" ]; then
    # Dump all PDR types with headers
    for TYPE in terminusLocatorPDR entityAssociationPDR numericSensorPDR stateSensorPDR numericEffecterPDR stateEffecterPDR; do
        echo "=== $TYPE ==="
        RESULT=$(pldmtool platform getpdr -t "$TYPE" -m "$EID" 2>/dev/null || true)
        if [ -n "$RESULT" ] && ! echo "$RESULT" | grep -qi "error\|not found" 2>/dev/null; then
            echo "$RESULT"
        else
            echo "  (none)"
        fi
        echo ""
    done

    # Summary: count by type
    echo "=== Summary ==="
    ALL_PDRS=$(pldmtool platform getpdr -t all -m "$EID" 2>/dev/null || true)
    if [ -n "$ALL_PDRS" ]; then
        TOTAL=$(echo "$ALL_PDRS" | grep -c "recordHandle" 2>/dev/null || echo "0")
        echo "  Total PDR records: $TOTAL"
    else
        echo "  No PDRs found"
    fi
else
    # Dump specific PDR type
    echo "Querying $PDR_TYPE..."
    echo ""
    RESULT=$(pldmtool platform getpdr -t "$PDR_TYPE" -m "$EID" 2>/dev/null || true)
    if [ -n "$RESULT" ] && ! echo "$RESULT" | grep -qi "error\|not found" 2>/dev/null; then
        echo "$RESULT"
    else
        echo "No $PDR_TYPE records found at EID $EID"
    fi
fi

echo ""
echo "========================================"
echo "PDR Type Reference"
echo "========================================"
echo ""
echo "  terminusLocatorPDR     - Identifies terminus (BMC, host, device)"
echo "  entityAssociationPDR   - Parent-child entity relationships"
echo "  numericSensorPDR       - Analog sensors (temperature, voltage, power)"
echo "  stateSensorPDR         - Discrete sensors (boot progress, link state)"
echo "  numericEffecterPDR     - Analog controls (fan speed, power limit)"
echo "  stateEffecterPDR       - Discrete controls (power on/off, reset)"
echo ""
echo "Individual PDR by record handle:"
echo "  pldmtool platform getpdr -d <handle> -m $EID"
