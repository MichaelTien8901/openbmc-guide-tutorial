#!/bin/bash
#
# Trigger and download a BMC dump via Redfish DumpService
#
# Usage:
#   ./collect-dump.sh <bmc-ip[:port]> [username] [password] [output-dir]
#
# Examples:
#   ./collect-dump.sh 192.168.1.100
#   ./collect-dump.sh localhost:2443 root 0penBmc /tmp/dumps
#   ./collect-dump.sh 10.0.0.50 admin supersecret ./dumps
#
# This script:
#   1. Triggers a new BMC diagnostic dump via Redfish
#   2. Polls until the dump is complete (or times out)
#   3. Downloads the dump archive (.tar.xz) to a local directory
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BMC_IP="${1:?Usage: $0 <bmc-ip[:port]> [username] [password] [output-dir]}"
USERNAME="${2:-root}"
PASSWORD="${3:-0penBmc}"
OUTPUT_DIR="${4:-.}"

POLL_INTERVAL=5      # Seconds between status checks
POLL_TIMEOUT=300     # Maximum seconds to wait for dump completion

CURL="curl -k -s -u ${USERNAME}:${PASSWORD}"
BASE_URL="https://${BMC_IP}"
DUMP_SERVICE="${BASE_URL}/redfish/v1/Managers/bmc/LogServices/Dump"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

log_info() {
    echo "[INFO]  $(date '+%H:%M:%S')  $*"
}

log_error() {
    echo "[ERROR] $(date '+%H:%M:%S')  $*" >&2
}

check_dependencies() {
    for cmd in curl jq; do
        if ! command -v "${cmd}" > /dev/null 2>&1; then
            log_error "Required command not found: ${cmd}"
            exit 1
        fi
    done
}

# ---------------------------------------------------------------------------
# Step 1: Verify DumpService is available
# ---------------------------------------------------------------------------

verify_dump_service() {
    log_info "Verifying DumpService at ${DUMP_SERVICE}"

    RESPONSE=$($CURL "${DUMP_SERVICE}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "${RESPONSE}" ]; then
        log_error "Cannot reach BMC at ${BMC_IP}. Check network and credentials."
        exit 1
    fi

    SERVICE_NAME=$(echo "${RESPONSE}" | jq -r '.Name // empty' 2>/dev/null)
    if [ -z "${SERVICE_NAME}" ]; then
        log_error "DumpService not available. Response:"
        echo "${RESPONSE}" | jq '.' 2>/dev/null || echo "${RESPONSE}"
        exit 1
    fi

    log_info "DumpService found: ${SERVICE_NAME}"
}

# ---------------------------------------------------------------------------
# Step 2: Get current dump count (to detect the new one)
# ---------------------------------------------------------------------------

get_dump_count() {
    $CURL "${DUMP_SERVICE}/Entries" 2>/dev/null \
        | jq -r '.Members@odata.count // 0' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Step 3: Trigger a new BMC dump
# ---------------------------------------------------------------------------

trigger_dump() {
    log_info "Triggering new BMC dump..."

    RESPONSE=$($CURL -X POST \
        -H "Content-Type: application/json" \
        -d '{"DiagnosticDataType": "Manager"}' \
        "${DUMP_SERVICE}/Actions/LogService.CollectDiagnosticData" 2>/dev/null)

    # Check for errors in the response
    ERROR_MSG=$(echo "${RESPONSE}" | jq -r '.error.message // empty' 2>/dev/null)
    if [ -n "${ERROR_MSG}" ]; then
        log_error "Failed to trigger dump: ${ERROR_MSG}"
        exit 1
    fi

    # Some implementations return a task URI for long-running operations
    TASK_URI=$(echo "${RESPONSE}" | jq -r '."@odata.id" // empty' 2>/dev/null)
    if [ -n "${TASK_URI}" ]; then
        log_info "Dump task created: ${TASK_URI}"
    else
        log_info "Dump collection initiated"
    fi
}

# ---------------------------------------------------------------------------
# Step 4: Poll for the new dump entry to appear
# ---------------------------------------------------------------------------

wait_for_dump() {
    log_info "Waiting for dump to complete (timeout: ${POLL_TIMEOUT}s)..."

    INITIAL_COUNT=$(get_dump_count)
    ELAPSED=0

    while [ "${ELAPSED}" -lt "${POLL_TIMEOUT}" ]; do
        sleep "${POLL_INTERVAL}"
        ELAPSED=$((ELAPSED + POLL_INTERVAL))

        CURRENT_COUNT=$(get_dump_count)

        if [ "${CURRENT_COUNT}" -gt "${INITIAL_COUNT}" ]; then
            log_info "New dump detected (count: ${INITIAL_COUNT} -> ${CURRENT_COUNT})"

            # Get the latest dump entry (highest ID)
            DUMP_ENTRY=$($CURL "${DUMP_SERVICE}/Entries" 2>/dev/null \
                | jq -r '.Members | sort_by(.Id | tonumber) | last | ."@odata.id" // empty' 2>/dev/null)

            if [ -n "${DUMP_ENTRY}" ]; then
                DUMP_ID=$(basename "${DUMP_ENTRY}")
                log_info "Dump entry ready: ${DUMP_ENTRY}"
                return 0
            fi
        fi

        # Show progress
        printf "\r[INFO]  $(date '+%H:%M:%S')  Polling... %ds / %ds" \
            "${ELAPSED}" "${POLL_TIMEOUT}"
    done

    echo ""
    log_error "Timed out waiting for dump to complete after ${POLL_TIMEOUT}s"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 5: Download the dump archive
# ---------------------------------------------------------------------------

download_dump() {
    log_info "Retrieving dump metadata..."

    DUMP_META=$($CURL "${BASE_URL}${DUMP_ENTRY}" 2>/dev/null)
    DUMP_SIZE=$(echo "${DUMP_META}" | jq -r '.AdditionalDataSizeBytes // "unknown"' 2>/dev/null)
    DUMP_TIME=$(echo "${DUMP_META}" | jq -r '.Created // "unknown"' 2>/dev/null)

    log_info "Dump ID: ${DUMP_ID}"
    log_info "Created: ${DUMP_TIME}"
    log_info "Size: ${DUMP_SIZE} bytes"

    # Create output directory if needed
    mkdir -p "${OUTPUT_DIR}"

    OUTPUT_FILE="${OUTPUT_DIR}/bmc-dump-${DUMP_ID}-$(date '+%Y%m%d-%H%M%S').tar.xz"

    log_info "Downloading to ${OUTPUT_FILE}..."

    $CURL -o "${OUTPUT_FILE}" \
        -H "Accept: application/octet-stream" \
        "${BASE_URL}${DUMP_ENTRY}/attachment" 2>/dev/null

    if [ -f "${OUTPUT_FILE}" ] && [ -s "${OUTPUT_FILE}" ]; then
        ACTUAL_SIZE=$(stat -c%s "${OUTPUT_FILE}" 2>/dev/null || stat -f%z "${OUTPUT_FILE}" 2>/dev/null)
        log_info "Download complete: ${OUTPUT_FILE} (${ACTUAL_SIZE} bytes)"
    else
        log_error "Download failed or file is empty"
        rm -f "${OUTPUT_FILE}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Step 6: Show dump contents summary
# ---------------------------------------------------------------------------

show_summary() {
    echo ""
    echo "=== Dump Summary ==="
    echo "File:    ${OUTPUT_FILE}"
    echo "Dump ID: ${DUMP_ID}"
    echo "Created: ${DUMP_TIME}"
    echo ""
    echo "To inspect the dump contents:"
    echo "  tar -tvf ${OUTPUT_FILE}"
    echo ""
    echo "To extract:"
    echo "  mkdir dump-${DUMP_ID} && tar -xf ${OUTPUT_FILE} -C dump-${DUMP_ID}"
    echo ""
    echo "To delete this dump from the BMC:"
    echo "  curl -k -u ${USERNAME}:${PASSWORD} -X DELETE \\"
    echo "    ${BASE_URL}${DUMP_ENTRY}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_dependencies
verify_dump_service
trigger_dump
wait_for_dump
download_dump
show_summary
