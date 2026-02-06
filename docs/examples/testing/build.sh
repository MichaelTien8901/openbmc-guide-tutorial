#!/bin/bash
# Build the GTest examples in a Docker container
set -e

cd "$(dirname "$0")"
docker build -t openbmc-testing-examples .
echo ""
echo "Build successful! Run with:"
echo "  ./run.sh  # run tests"
