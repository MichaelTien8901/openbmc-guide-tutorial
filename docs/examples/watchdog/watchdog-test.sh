#!/bin/bash
# Watchdog test script
# Usage: watchdog-test.sh [enable|disable|kick|status|set-interval MSEC]

SERVICE="xyz.openbmc_project.Watchdog"
PATH_WD="/xyz/openbmc_project/watchdog/host0"
IFACE="xyz.openbmc_project.State.Watchdog"

case "$1" in
    enable)
        busctl set-property $SERVICE $PATH_WD $IFACE Enabled b true
        echo "Watchdog enabled"
        ;;
    disable)
        busctl set-property $SERVICE $PATH_WD $IFACE Enabled b false
        echo "Watchdog disabled"
        ;;
    kick)
        busctl call $SERVICE $PATH_WD $IFACE ResetTimeRemaining
        echo "Watchdog kicked (timer reset)"
        ;;
    status)
        echo "=== Watchdog Status ==="
        ENABLED=$(busctl get-property $SERVICE $PATH_WD $IFACE Enabled | awk '{print $2}')
        INTERVAL=$(busctl get-property $SERVICE $PATH_WD $IFACE Interval | awk '{print $2}')
        REMAINING=$(busctl get-property $SERVICE $PATH_WD $IFACE TimeRemaining | awk '{print $2}')
        ACTION=$(busctl get-property $SERVICE $PATH_WD $IFACE ExpireAction | awk '{print $2}')

        echo "Enabled: $ENABLED"
        echo "Interval: ${INTERVAL}ms"
        echo "Time Remaining: ${REMAINING}ms"
        echo "Expire Action: $ACTION"
        ;;
    set-interval)
        if [ -z "$2" ]; then
            echo "Usage: $0 set-interval MILLISECONDS"
            exit 1
        fi
        busctl set-property $SERVICE $PATH_WD $IFACE Interval t "$2"
        echo "Watchdog interval set to ${2}ms"
        ;;
    set-action)
        if [ -z "$2" ]; then
            echo "Usage: $0 set-action [None|HardReset|PowerOff|PowerCycle]"
            exit 1
        fi
        busctl set-property $SERVICE $PATH_WD $IFACE ExpireAction s "xyz.openbmc_project.State.Watchdog.Action.$2"
        echo "Watchdog expire action set to $2"
        ;;
    *)
        echo "Usage: $0 [enable|disable|kick|status|set-interval MSEC|set-action ACTION]"
        echo ""
        echo "Commands:"
        echo "  enable       - Enable watchdog timer"
        echo "  disable      - Disable watchdog timer"
        echo "  kick         - Reset watchdog timer (prevent timeout)"
        echo "  status       - Show watchdog configuration"
        echo "  set-interval - Set timeout interval in milliseconds"
        echo "  set-action   - Set expire action (None|HardReset|PowerOff|PowerCycle)"
        exit 1
        ;;
esac
