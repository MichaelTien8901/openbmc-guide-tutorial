#!/bin/bash
#
# Power Sequencer Script
#
# Example script demonstrating custom power sequencing for OpenBMC.
# This script is called by power-sequencer.service during power transitions.
#
# Usage:
#   power-sequencer.sh on    # Power on sequence
#   power-sequencer.sh off   # Power off sequence
#

set -e

# Configuration - customize for your platform
POWER_GOOD_GPIO="${POWER_GOOD_GPIO:-power-ok}"
POWER_ENABLE_GPIO="${POWER_ENABLE_GPIO:-power-enable}"
POWER_GOOD_TIMEOUT=30
LOG_TAG="power-sequencer"

# Logging helper
log() {
    logger -t "$LOG_TAG" "$@"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $@"
}

# Wait for GPIO to reach expected value
wait_for_gpio() {
    local gpio_name=$1
    local expected_value=$2
    local timeout=$3
    local count=0

    log "Waiting for $gpio_name to be $expected_value (timeout: ${timeout}s)"

    while [ $count -lt $timeout ]; do
        # Read GPIO value - adjust command for your platform
        local value=$(gpioget gpiochip0 "$gpio_name" 2>/dev/null || echo "error")

        if [ "$value" = "$expected_value" ]; then
            log "$gpio_name is $expected_value"
            return 0
        fi

        sleep 1
        count=$((count + 1))
    done

    log "ERROR: Timeout waiting for $gpio_name to be $expected_value"
    return 1
}

# Power on sequence
power_on() {
    log "Starting power on sequence"

    # Step 1: Enable main power rails
    log "Step 1: Enabling power rails"
    # gpioset gpiochip0 $POWER_ENABLE_GPIO=1
    sleep 0.1

    # Step 2: Wait for power good
    log "Step 2: Waiting for power good"
    # wait_for_gpio "$POWER_GOOD_GPIO" 1 $POWER_GOOD_TIMEOUT

    # Step 3: Release CPU reset
    log "Step 3: Releasing CPU reset"
    # gpioset gpiochip0 cpu-reset=1
    sleep 0.1

    # Step 4: Enable additional rails (VRM, memory, etc.)
    log "Step 4: Enabling secondary rails"
    sleep 0.1

    log "Power on sequence complete"
}

# Power off sequence
power_off() {
    log "Starting power off sequence"

    # Step 1: Signal graceful shutdown
    log "Step 1: Initiating graceful shutdown"
    sleep 0.5

    # Step 2: Assert CPU reset
    log "Step 2: Asserting CPU reset"
    # gpioset gpiochip0 cpu-reset=0
    sleep 0.1

    # Step 3: Disable secondary rails
    log "Step 3: Disabling secondary rails"
    sleep 0.1

    # Step 4: Disable main power rails
    log "Step 4: Disabling power rails"
    # gpioset gpiochip0 $POWER_ENABLE_GPIO=0
    sleep 0.1

    # Step 5: Wait for power good to deassert
    log "Step 5: Waiting for power off"
    # wait_for_gpio "$POWER_GOOD_GPIO" 0 10

    log "Power off sequence complete"
}

# Main
case "$1" in
    on)
        power_on
        ;;
    off)
        power_off
        ;;
    *)
        echo "Usage: $0 {on|off}"
        exit 1
        ;;
esac

exit 0
