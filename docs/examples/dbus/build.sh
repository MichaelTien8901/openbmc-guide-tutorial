#!/bin/bash
# Build the D-Bus examples in a Docker container
set -e

cd "$(dirname "$0")"
docker build -t openbmc-dbus-examples .
echo ""
echo "Build successful! Run with:"
echo "  ./run.sh        # run demo"
echo "  ./run.sh shell  # interactive shell"
