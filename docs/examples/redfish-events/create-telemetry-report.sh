#!/bin/bash
#
# Create a Redfish Telemetry MetricReportDefinition
#
# Configures periodic sensor data collection via the Redfish TelemetryService.
# The BMC will collect specified sensor readings at the defined interval and
# store them as MetricReports that can be retrieved via GET.
#
# Usage:
#   ./create-telemetry-report.sh [interval-seconds]
#
# Arguments:
#   interval-seconds  - Collection interval in seconds (default: 60)
#
# Environment variables:
#   BMC_HOST  - BMC hostname:port (default: localhost:2443)
#   BMC_USER  - Redfish username (default: root)
#   BMC_PASS  - Redfish password (default: 0penBmc)
#
# Prerequisites:
#   - Running OpenBMC with bmcweb TelemetryService enabled
#   - curl and jq installed on the client

set -euo pipefail

BMC_HOST="${BMC_HOST:-localhost:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASS="${BMC_PASS:-0penBmc}"
INTERVAL="${1:-60}"

BASE_URL="https://${BMC_HOST}/redfish/v1"
CURL="curl -k -s -u ${BMC_USER}:${BMC_PASS}"

echo "========================================"
echo "Create Telemetry MetricReportDefinition"
echo "BMC: ${BMC_HOST}"
echo "========================================"
echo ""

# Step 1: Check TelemetryService availability
echo "Step 1: Checking TelemetryService..."
TS_RESULT=$($CURL "${BASE_URL}/TelemetryService" 2>/dev/null)
if ! echo "$TS_RESULT" | jq -e '."@odata.id"' > /dev/null 2>&1; then
    echo "  ERROR: TelemetryService not available."
    echo "  Ensure bmcweb is built with: -Dredfish-telemetry-service=enabled"
    echo "  Ensure 'telemetry' package is in the image."
    exit 1
fi

echo "  TelemetryService is available."
MAX_REPORTS=$(echo "$TS_RESULT" | jq -r '.MaxReports // "N/A"')
MIN_INTERVAL=$(echo "$TS_RESULT" | jq -r '.MinCollectionInterval // "N/A"')
echo "  MaxReports: ${MAX_REPORTS}"
echo "  MinCollectionInterval: ${MIN_INTERVAL}"
echo ""

# Step 2: List existing MetricReportDefinitions
echo "Step 2: Existing MetricReportDefinitions..."
EXISTING=$($CURL "${BASE_URL}/TelemetryService/MetricReportDefinitions" 2>/dev/null)
EXISTING_COUNT=$(echo "$EXISTING" | jq '.Members | length' 2>/dev/null || echo "0")
echo "  Found ${EXISTING_COUNT} existing definition(s)."
if [ "$EXISTING_COUNT" -gt 0 ]; then
    echo "$EXISTING" | jq -r '.Members[]."@odata.id"' 2>/dev/null | while read -r URI; do
        echo "    $URI"
    done
fi
echo ""

# Step 3: Discover available sensors for metric collection
echo "Step 3: Discovering available sensor URIs..."
echo "  Checking Chassis thermal sensors..."
THERMAL=$($CURL "${BASE_URL}/Chassis/chassis/Thermal" 2>/dev/null)
TEMP_COUNT=$(echo "$THERMAL" | jq '.Temperatures | length' 2>/dev/null || echo "0")
FAN_COUNT=$(echo "$THERMAL" | jq '.Fans | length' 2>/dev/null || echo "0")
echo "  Found ${TEMP_COUNT} temperature sensor(s), ${FAN_COUNT} fan sensor(s)."
echo ""

# Step 4: Create MetricReportDefinition
echo "Step 4: Creating MetricReportDefinition..."
echo "  Report ID: TutorialSensorReport"
echo "  Interval: ${INTERVAL} seconds"
echo ""

# Build the metric report definition.
# MetricProperties use Redfish property URIs pointing to sensor readings.
# The BMC's telemetry daemon collects these values at the specified interval.
REPORT_BODY=$(cat <<ENDJSON
{
    "Id": "TutorialSensorReport",
    "Name": "Tutorial Sensor Telemetry Report",
    "MetricReportDefinitionType": "Periodic",
    "Schedule": {
        "RecurrenceInterval": "PT${INTERVAL}S"
    },
    "ReportActions": [
        "LogToMetricReportsCollection"
    ],
    "ReportUpdates": "Overwrite",
    "Metrics": [
        {
            "MetricId": "ChassisTempAvg",
            "MetricProperties": [
                "/redfish/v1/Chassis/chassis/Thermal#/Temperatures/0/ReadingCelsius"
            ],
            "CollectionFunction": "Average",
            "CollectionDuration": "PT${INTERVAL}S"
        },
        {
            "MetricId": "ChassisTempMax",
            "MetricProperties": [
                "/redfish/v1/Chassis/chassis/Thermal#/Temperatures/0/ReadingCelsius"
            ],
            "CollectionFunction": "Maximum",
            "CollectionDuration": "PT${INTERVAL}S"
        },
        {
            "MetricId": "FanSpeedAvg",
            "MetricProperties": [
                "/redfish/v1/Chassis/chassis/Thermal#/Fans/0/Reading"
            ],
            "CollectionFunction": "Average",
            "CollectionDuration": "PT${INTERVAL}S"
        }
    ]
}
ENDJSON
)

echo "  Request body:"
echo "$REPORT_BODY" | jq '.'
echo ""

RESULT=$($CURL -X POST \
    -H "Content-Type: application/json" \
    -d "$REPORT_BODY" \
    -w "\n%{http_code}" \
    "${BASE_URL}/TelemetryService/MetricReportDefinitions" 2>/dev/null)

HTTP_CODE=$(echo "$RESULT" | tail -1)
RESPONSE_BODY=$(echo "$RESULT" | head -n -1)

echo "  HTTP Status: ${HTTP_CODE}"
echo ""

if [ "$HTTP_CODE" = "201" ]; then
    echo "  MetricReportDefinition created successfully!"
    echo ""
    echo "  Definition details:"
    echo "$RESPONSE_BODY" | jq '{
        Id: .Id,
        Name: .Name,
        MetricReportDefinitionType: .MetricReportDefinitionType,
        Schedule: .Schedule,
        ReportActions: .ReportActions,
        MetricCount: (.Metrics | length)
    }' 2>/dev/null || echo "$RESPONSE_BODY"
elif [ "$HTTP_CODE" = "409" ]; then
    echo "  Report definition already exists (HTTP 409 Conflict)."
    echo "  Delete the existing one first:"
    echo "    curl -k -u ${BMC_USER}:${BMC_PASS} -X DELETE \\"
    echo "      ${BASE_URL}/TelemetryService/MetricReportDefinitions/TutorialSensorReport"
else
    echo "  Failed to create MetricReportDefinition."
    echo ""
    echo "  Response:"
    echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
fi
echo ""

# Step 5: Show how to retrieve reports
echo "========================================"
echo "Retrieving Metric Reports"
echo "========================================"
echo ""
echo "After the first collection interval (${INTERVAL}s), retrieve the report:"
echo ""
echo "  # List all metric reports"
echo "  curl -k -s -u ${BMC_USER}:${BMC_PASS} \\"
echo "    ${BASE_URL}/TelemetryService/MetricReports | jq ."
echo ""
echo "  # Get the specific report"
echo "  curl -k -s -u ${BMC_USER}:${BMC_PASS} \\"
echo "    ${BASE_URL}/TelemetryService/MetricReports/TutorialSensorReport | jq ."
echo ""
echo "  # Extract just the metric values"
echo "  curl -k -s -u ${BMC_USER}:${BMC_PASS} \\"
echo "    ${BASE_URL}/TelemetryService/MetricReports/TutorialSensorReport \\"
echo "    | jq '.MetricValues[] | {MetricId, MetricValue, Timestamp}'"
echo ""
echo "  # Delete the report definition when done"
echo "  curl -k -s -u ${BMC_USER}:${BMC_PASS} -X DELETE \\"
echo "    ${BASE_URL}/TelemetryService/MetricReportDefinitions/TutorialSensorReport"
