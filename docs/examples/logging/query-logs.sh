#!/bin/bash
# Query and display log entries
# Usage: query-logs.sh [list|count|clear|show ID]

SERVICE="xyz.openbmc_project.Logging"
PATH_LOG="/xyz/openbmc_project/logging"

case "$1" in
    list)
        echo "=== Log Entries ==="
        # Get all entry paths
        ENTRIES=$(busctl tree $SERVICE 2>/dev/null | grep "/xyz/openbmc_project/logging/entry/" | awk '{print $1}')

        if [ -z "$ENTRIES" ]; then
            echo "No log entries found"
            exit 0
        fi

        for entry in $ENTRIES; do
            ID=$(basename $entry)
            SEVERITY=$(busctl get-property $SERVICE $entry xyz.openbmc_project.Logging.Entry Severity 2>/dev/null | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}')
            MESSAGE=$(busctl get-property $SERVICE $entry xyz.openbmc_project.Logging.Entry Message 2>/dev/null | awk -F'"' '{print $2}')
            TIMESTAMP=$(busctl get-property $SERVICE $entry xyz.openbmc_project.Logging.Entry Timestamp 2>/dev/null | awk '{print $2}')

            echo "[$ID] [$SEVERITY] $MESSAGE (ts: $TIMESTAMP)"
        done
        ;;

    count)
        COUNT=$(busctl tree $SERVICE 2>/dev/null | grep -c "/xyz/openbmc_project/logging/entry/")
        echo "Total log entries: $COUNT"
        ;;

    clear)
        echo "Clearing all log entries..."
        busctl call $SERVICE $PATH_LOG xyz.openbmc_project.Collection.DeleteAll DeleteAll
        echo "All log entries cleared"
        ;;

    show)
        if [ -z "$2" ]; then
            echo "Usage: $0 show ID"
            exit 1
        fi
        ENTRY_PATH="${PATH_LOG}/entry/$2"
        echo "=== Log Entry $2 ==="
        busctl introspect $SERVICE $ENTRY_PATH xyz.openbmc_project.Logging.Entry 2>/dev/null || echo "Entry not found"
        ;;

    *)
        echo "Usage: $0 [list|count|clear|show ID]"
        echo ""
        echo "Commands:"
        echo "  list    - List all log entries"
        echo "  count   - Show total number of entries"
        echo "  clear   - Delete all log entries"
        echo "  show ID - Show details of specific entry"
        exit 1
        ;;
esac
