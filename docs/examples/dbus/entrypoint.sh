#!/bin/bash
set -e

# Bootstrap: if no session bus, start one via dbus-run-session
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    exec dbus-run-session -- "$0" "$@"
fi

# Redirect system bus to session bus so examples work in container
export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"

SERVICE="xyz.openbmc_project.Example.Server"
OBJECT="/xyz/openbmc_project/example/server"
IFACE="xyz.openbmc_project.Example.Counter"

if [ "$1" = "demo" ]; then
    echo "=== Starting D-Bus Server ==="
    ./builddir/dbus_server &
    SERVER_PID=$!
    sleep 1

    echo ""
    echo "=== Introspecting Server ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Introspectable.Introspect \
        | head -40
    echo "  ..."
    echo ""

    echo "=== Calling Increment ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT $IFACE.Increment
    echo ""

    echo "=== Reading Counter ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.Get \
        string:$IFACE string:Counter
    echo ""

    echo "=== Setting Counter to 42 ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.Set \
        string:$IFACE string:Counter variant:int64:42

    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.Get \
        string:$IFACE string:Counter
    echo ""

    echo "=== Calling Add(8) ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT $IFACE.Add int64:8
    echo ""

    echo "=== Calling Reset ==="
    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT $IFACE.Reset

    dbus-send --system --dest=$SERVICE --print-reply \
        $OBJECT org.freedesktop.DBus.Properties.Get \
        string:$IFACE string:Counter

    kill "$SERVER_PID" 2>/dev/null || true
    echo ""
    echo "Demo complete!"

elif [ "$1" = "shell" ]; then
    echo "D-Bus session ready. Start the server with:"
    echo "  ./builddir/dbus_server &"
    echo ""
    echo "Then interact with dbus-send:"
    echo "  dbus-send --system --dest=$SERVICE --print-reply $OBJECT $IFACE.Increment"
    echo ""
    exec bash

else
    exec "$@"
fi
