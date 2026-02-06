#!/bin/bash
set -e

# Bootstrap: if no session bus, start one via dbus-run-session
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    exec dbus-run-session -- "$0" "$@"
fi

# Redirect system bus to session bus so examples work in container
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"

SERVICE="xyz.openbmc_project.VirtualSensor.TotalPower"
OBJECT="/xyz/openbmc_project/sensors/power/Total_Power"
IFACE="xyz.openbmc_project.Sensor.Value"

if [ "$1" = "demo" ]; then
    echo "=== Starting Virtual Sensor ==="
    ./builddir/virtual_sensor &
    SENSOR_PID=$!
    sleep 2

    echo ""
    echo "=== Introspecting Virtual Sensor ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Introspectable.Introspect \
        | head -30
    echo "  ..."
    echo ""

    echo "=== Reading Sensor Value ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.Get \
        string:$IFACE string:Value
    echo ""

    echo "=== Reading All Properties ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.GetAll \
        string:$IFACE
    echo ""

    echo "=== Running sensor_reader (no physical sensors in container) ==="
    ./builddir/sensor_reader || true

    kill "$SENSOR_PID" 2>/dev/null || true
    echo ""
    echo "Demo complete!"

elif [ "$1" = "shell" ]; then
    echo "D-Bus session ready. Try:"
    echo "  ./builddir/virtual_sensor &"
    echo "  ./builddir/sensor_reader"
    echo ""
    exec bash

else
    exec "$@"
fi
