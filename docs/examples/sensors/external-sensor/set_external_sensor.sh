#!/bin/bash
#
# External Sensor Example
#
# Demonstrates setting values on an external/virtual sensor via D-Bus.
# External sensors allow non-hwmon data sources to publish sensor values.
#

SERVICE="xyz.openbmc_project.ExternalSensor"
OBJECT_PATH="/xyz/openbmc_project/sensors/power/Total_Power"
INTERFACE="xyz.openbmc_project.Sensor.Value"

# Function to set sensor value
set_sensor_value() {
    local value=$1
    echo "Setting sensor value to: $value"
    busctl set-property "$SERVICE" "$OBJECT_PATH" "$INTERFACE" Value d "$value"
    if [ $? -eq 0 ]; then
        echo "Success!"
    else
        echo "Failed to set sensor value"
        echo "Make sure the external sensor is configured in Entity Manager"
        return 1
    fi
}

# Function to get sensor value
get_sensor_value() {
    echo "Current sensor value:"
    busctl get-property "$SERVICE" "$OBJECT_PATH" "$INTERFACE" Value
}

# Function to list external sensors
list_external_sensors() {
    echo "External sensors:"
    busctl tree "$SERVICE" 2>/dev/null || echo "No external sensors found"
}

# Main
case "${1:-}" in
    set)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 set <value>"
            exit 1
        fi
        set_sensor_value "$2"
        ;;
    get)
        get_sensor_value
        ;;
    list)
        list_external_sensors
        ;;
    demo)
        echo "=== External Sensor Demo ==="
        echo ""
        echo "Simulating power consumption changes over time..."
        for value in 100 150 200 250 300 350 400 350 300 250 200; do
            set_sensor_value "$value"
            sleep 1
        done
        echo ""
        echo "Demo complete!"
        ;;
    *)
        echo "External Sensor Example"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  set <value>  - Set sensor value"
        echo "  get          - Get current sensor value"
        echo "  list         - List external sensors"
        echo "  demo         - Run demo with changing values"
        echo ""
        echo "Example:"
        echo "  $0 set 450.5"
        echo "  $0 get"
        echo ""
        echo "Note: Requires ExternalSensor configured in Entity Manager:"
        echo ""
        cat << 'EOF'
{
    "Exposes": [
        {
            "Name": "Total Power",
            "Type": "ExternalSensor",
            "Units": "Watts",
            "MinValue": 0,
            "MaxValue": 2000
        }
    ],
    "Name": "VirtualSensors",
    "Probe": "TRUE",
    "Type": "Board"
}
EOF
        ;;
esac
