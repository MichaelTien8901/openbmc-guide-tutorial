#!/bin/bash
# Run the sensor examples container
# Usage:
#   ./run.sh          # run demo
#   ./run.sh shell    # interactive shell
set -e

docker run --rm -it openbmc-sensor-examples "${1:-demo}"
