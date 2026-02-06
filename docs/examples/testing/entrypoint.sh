#!/bin/bash
set -e

if [ "$1" = "test" ]; then
    echo "=== Running Sensor Tests ==="
    echo ""
    ./build/sensor_tests
else
    exec "$@"
fi
