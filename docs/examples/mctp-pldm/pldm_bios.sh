#!/bin/bash
#
# PLDM BIOS Attribute Reader
#
# Queries BIOS tables (Type 3) from a PLDM endpoint.
# Retrieves string table, attribute table, and attribute values.
#
# Usage:
#   ./pldm_bios.sh <eid> [attribute-name]
#
# Arguments:
#   eid              MCTP Endpoint ID (required)
#   attribute-name   Optional: get specific attribute value
#
# Examples:
#   ./pldm_bios.sh 9                   # Dump all BIOS tables
#   ./pldm_bios.sh 9 boot_order        # Get specific attribute
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - pldmtool installed
#   - Endpoint supports PLDM Type 3 (BIOS Control)

set -e

EID=${1:?Usage: $0 <eid> [attribute-name]}
ATTR_NAME=${2:-}

echo "========================================"
echo "PLDM BIOS Attributes (EID=$EID)"
echo "========================================"
echo ""

if ! command -v pldmtool &>/dev/null; then
    echo "Error: pldmtool not found"
    exit 1
fi

# Verify endpoint supports BIOS type
echo "Checking PLDM Type 3 (BIOS) support..."
TYPES=$(pldmtool base getPLDMTypes -m "$EID" 2>/dev/null || true)
if ! echo "$TYPES" | grep -qi "3\|bios" 2>/dev/null; then
    echo "Warning: Endpoint may not support PLDM BIOS type"
    echo "Proceeding anyway..."
fi
echo ""

if [ -n "$ATTR_NAME" ]; then
    # Get specific attribute
    echo "Getting attribute: $ATTR_NAME"
    echo ""
    pldmtool bios GetBIOSAttributeCurrentValueByHandle -m "$EID" -a "$ATTR_NAME" 2>/dev/null || \
        echo "Error: Could not read attribute '$ATTR_NAME'"
else
    # Dump all tables
    echo "=== String Table ==="
    pldmtool bios GetBIOSTable -m "$EID" -t StringTable 2>/dev/null || \
        echo "  Not available"
    echo ""

    echo "=== Attribute Table ==="
    pldmtool bios GetBIOSTable -m "$EID" -t AttributeTable 2>/dev/null || \
        echo "  Not available"
    echo ""

    echo "=== Attribute Value Table ==="
    pldmtool bios GetBIOSTable -m "$EID" -t AttributeValueTable 2>/dev/null || \
        echo "  Not available"
fi
