#!/bin/bash
# Create event log entries
# Usage: create-event.sh [info|warning|error|critical] "message"

SERVICE="xyz.openbmc_project.Logging"
PATH_LOG="/xyz/openbmc_project/logging"
IFACE="xyz.openbmc_project.Logging.Create"

LEVEL_PREFIX="xyz.openbmc_project.Logging.Entry.Level"
ERROR_TYPE="xyz.openbmc_project.Common.Error.InternalFailure"

case "$1" in
    info)
        LEVEL="${LEVEL_PREFIX}.Informational"
        ;;
    warning)
        LEVEL="${LEVEL_PREFIX}.Warning"
        ;;
    error)
        LEVEL="${LEVEL_PREFIX}.Error"
        ;;
    critical)
        LEVEL="${LEVEL_PREFIX}.Critical"
        ;;
    *)
        echo "Usage: $0 [info|warning|error|critical] \"message\""
        echo ""
        echo "Examples:"
        echo "  $0 info \"System started successfully\""
        echo "  $0 warning \"Temperature approaching threshold\""
        echo "  $0 error \"Sensor read failed\""
        echo "  $0 critical \"Power supply failure detected\""
        exit 1
        ;;
esac

MESSAGE="${2:-No message provided}"

busctl call $SERVICE $PATH_LOG $IFACE Create "ssa{ss}" \
    "$ERROR_TYPE" \
    "$LEVEL" \
    1 "REASON" "$MESSAGE"

echo "Created $1 log entry: $MESSAGE"
