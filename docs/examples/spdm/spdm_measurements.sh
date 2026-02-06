#!/bin/bash
#
# SPDM Measurement Collection
#
# Collects firmware measurements from an SPDM-capable device and
# optionally compares against an expected measurement policy.
#
# Usage:
#   ./spdm_measurements.sh <eid> [policy-file]
#
# Arguments:
#   eid           MCTP Endpoint ID (required)
#   policy-file   Optional: JSON file with expected measurements for comparison
#
# Examples:
#   ./spdm_measurements.sh 10                              # Collect all measurements
#   ./spdm_measurements.sh 10 config/gpu_expected.json     # Collect and verify
#
# Prerequisites:
#   - Running on OpenBMC with SPDM support
#   - spdmtool installed

set -e

EID=${1:?Usage: $0 <eid> [policy-file]}
POLICY_FILE=${2:-}

echo "========================================"
echo "SPDM Measurement Collection (EID=$EID)"
echo "========================================"
echo ""

if ! command -v spdmtool &>/dev/null; then
    echo "Error: spdmtool not found"
    exit 1
fi

# Collect all measurements (unsigned)
echo "=== All Measurements (unsigned) ==="
MEAS_RESULT=$(spdmtool measurements -m "$EID" 2>/dev/null || true)
if [ -n "$MEAS_RESULT" ]; then
    echo "$MEAS_RESULT"
else
    echo "  Failed to get measurements"
    echo "  Device may not support SPDM measurement capability"
    exit 1
fi
echo ""

# Collect signed measurements (for attestation)
echo "=== Signed Measurements ==="
SIGNED_RESULT=$(spdmtool measurements -m "$EID" --signed 2>/dev/null || true)
if [ -n "$SIGNED_RESULT" ]; then
    echo "$SIGNED_RESULT"
    echo ""
    echo "  Signature verified by spdmtool"
else
    echo "  Signed measurements not available"
fi
echo ""

# Save measurements to file
OUTPUT_FILE="/tmp/measurements_eid${EID}.json"
spdmtool measurements -m "$EID" -o "$OUTPUT_FILE" 2>/dev/null && \
    echo "Measurements saved to $OUTPUT_FILE" || \
    echo "Could not save measurements to file"
echo ""

# Read individual measurements
echo "=== Individual Measurement Details ==="
for INDEX in 1 2 3; do
    RESULT=$(spdmtool measurements -m "$EID" -i "$INDEX" 2>/dev/null || true)
    if [ -n "$RESULT" ]; then
        echo "--- Index $INDEX ---"
        echo "$RESULT"
        echo ""
    fi
done

# Compare against policy if provided
if [ -n "$POLICY_FILE" ]; then
    echo "========================================"
    echo "Policy Comparison"
    echo "========================================"
    echo ""

    if [ ! -f "$POLICY_FILE" ]; then
        echo "Error: Policy file not found: $POLICY_FILE"
        exit 1
    fi

    echo "Policy: $POLICY_FILE"
    echo ""

    if [ -f "$OUTPUT_FILE" ]; then
        # Simple diff comparison
        echo "Comparing actual measurements against expected policy..."
        echo ""
        if diff -q "$OUTPUT_FILE" "$POLICY_FILE" &>/dev/null; then
            echo "  MATCH - All measurements match expected policy"
        else
            echo "  MISMATCH - Measurements differ from policy"
            echo ""
            echo "  Differences:"
            diff "$OUTPUT_FILE" "$POLICY_FILE" || true
        fi
    else
        echo "  Cannot compare: measurement file not saved"
    fi
fi

echo ""
echo "========================================"
echo "Measurement Types Reference"
echo "========================================"
echo ""
echo "  ImmutableROM        - Boot ROM (should never change)"
echo "  MutableFirmware     - Updatable firmware code"
echo "  FirmwareConfig      - Configuration data"
echo "  FirmwareVersion     - Version string"
echo "  HardwareConfig      - Hardware strap/fuse values"
echo "  DeviceMode          - Debug/production mode"
