#!/bin/bash
# Control identify LED via D-Bus
# Usage: identify-led.sh [on|off|blink|status]

LED_SERVICE="xyz.openbmc_project.LED.GroupManager"
LED_PATH="/xyz/openbmc_project/led/groups/enclosure_identify"
LED_IFACE="xyz.openbmc_project.Led.Group"

case "$1" in
    on)
        busctl set-property $LED_SERVICE $LED_PATH $LED_IFACE Asserted b true
        echo "Identify LED: ON"
        ;;
    off)
        busctl set-property $LED_SERVICE $LED_PATH $LED_IFACE Asserted b false
        echo "Identify LED: OFF"
        ;;
    blink)
        # Turn on (LED group config defines blink behavior)
        busctl set-property $LED_SERVICE $LED_PATH $LED_IFACE Asserted b true
        echo "Identify LED: BLINKING"
        ;;
    status)
        STATE=$(busctl get-property $LED_SERVICE $LED_PATH $LED_IFACE Asserted | awk '{print $2}')
        if [ "$STATE" = "true" ]; then
            echo "Identify LED: ON"
        else
            echo "Identify LED: OFF"
        fi
        ;;
    *)
        echo "Usage: $0 [on|off|blink|status]"
        exit 1
        ;;
esac
