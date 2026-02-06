#!/bin/bash
#
# PLDM Sensor Reader
#
# Reads numeric and state sensors from a PLDM endpoint via pldmtool.
# Discovers available sensors from PDRs, then reads current values.
#
# Usage:
#   ./pldm_sensors.sh <eid> [sensor-id]
#
# Arguments:
#   eid         MCTP Endpoint ID (required)
#   sensor-id   Optional: read a specific sensor (default: list all)
#
# Examples:
#   ./pldm_sensors.sh 9           # List and read all sensors at EID 9
#   ./pldm_sensors.sh 9 1         # Read sensor ID 1 at EID 9
#   ./pldm_sensors.sh 10 2        # Read sensor ID 2 at EID 10 (e.g., GPU)
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - pldmtool installed

set -e

EID=${1:?Usage: $0 <eid> [sensor-id]}
SENSOR_ID=${2:-}

echo "========================================"
echo "PLDM Sensor Reader (EID=$EID)"
echo "========================================"
echo ""

if ! command -v pldmtool &>/dev/null; then
    echo "Error: pldmtool not found"
    exit 1
fi

# Verify endpoint responds
echo "Checking endpoint..."
TID_RESULT=$(pldmtool base getTID -m "$EID" 2>/dev/null || true)
if ! echo "$TID_RESULT" | grep -q "TID" 2>/dev/null; then
    echo "Error: EID $EID not responding"
    exit 1
fi
echo "Endpoint EID=$EID is responding."
echo ""

read_numeric_sensor() {
    local SID=$1
    echo "--- Numeric Sensor $SID ---"
    RESULT=$(pldmtool platform getSensorReading -m "$EID" -i "$SID" 2>/dev/null || true)
    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    else
        echo "  No response or not a numeric sensor"
    fi
    echo ""
}

read_state_sensor() {
    local SID=$1
    echo "--- State Sensor $SID ---"
    RESULT=$(pldmtool platform getStateSensorReadings -m "$EID" -i "$SID" 2>/dev/null || true)
    if [ -n "$RESULT" ]; then
        echo "$RESULT"
    else
        echo "  No response or not a state sensor"
    fi
    echo ""
}

if [ -n "$SENSOR_ID" ]; then
    # Read specific sensor (try both numeric and state)
    echo "Reading sensor $SENSOR_ID..."
    echo ""
    read_numeric_sensor "$SENSOR_ID"
    read_state_sensor "$SENSOR_ID"
else
    # Discover sensors from PDRs
    echo "Discovering sensors from PDR repository..."
    echo ""

    # Numeric sensor PDRs
    echo "=== Numeric Sensors ==="
    NUM_PDRS=$(pldmtool platform getpdr -t numericSensorPDR -m "$EID" 2>/dev/null || true)
    if [ -n "$NUM_PDRS" ]; then
        echo "$NUM_PDRS" | grep -oP '"sensorID"\s*:\s*\K[0-9]+' | sort -n -u | while read -r SID; do
            read_numeric_sensor "$SID"
        done
    else
        echo "  No numeric sensor PDRs found"
        echo ""
    fi

    # State sensor PDRs
    echo "=== State Sensors ==="
    STATE_PDRS=$(pldmtool platform getpdr -t stateSensorPDR -m "$EID" 2>/dev/null || true)
    if [ -n "$STATE_PDRS" ]; then
        echo "$STATE_PDRS" | grep -oP '"sensorID"\s*:\s*\K[0-9]+' | sort -n -u | while read -r SID; do
            read_state_sensor "$SID"
        done
    else
        echo "  No state sensor PDRs found"
        echo ""
    fi
fi

echo "========================================"
echo "Effecter Control Examples"
echo "========================================"
echo ""
echo "To set a state effecter:"
echo "  pldmtool platform setStateEffecterStates -m $EID -i <effecter-id> -c 1 -d <state>"
echo ""
echo "To set a numeric effecter:"
echo "  pldmtool platform setNumericEffecterValue -m $EID -i <effecter-id> -d <value>"
echo ""
echo "To list effecter PDRs:"
echo "  pldmtool platform getpdr -t numericEffecterPDR -m $EID"
echo "  pldmtool platform getpdr -t stateEffecterPDR -m $EID"
