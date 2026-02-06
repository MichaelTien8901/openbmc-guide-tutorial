#!/bin/bash
# Run the D-Bus examples container
# Usage:
#   ./run.sh          # run demo
#   ./run.sh shell    # interactive shell
set -e

docker run --rm -it openbmc-dbus-examples "${1:-demo}"
