#!/bin/bash
# Run the GTest examples container
set -e

docker run --rm openbmc-testing-examples "${1:-test}"
