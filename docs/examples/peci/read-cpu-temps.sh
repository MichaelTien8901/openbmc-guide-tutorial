#!/bin/bash
#
# Read CPU and DIMM Temperatures
#
# Reads temperature sensor values from the Linux hwmon sysfs interface and
# formats the output as a readable table. This script discovers PECI-based
# CPU and DIMM temperature sensors automatically by scanning hwmon devices.
#
# The PECI hwmon drivers (peci-cputemp, peci-dimmtemp) expose CPU die/core
# temperatures and DIMM temperatures under /sys/class/hwmon/hwmonN/.
#
# Usage:
#   ./read-cpu-temps.sh [options]
#
#   Options:
#     -a, --all       Show all hwmon temperature sensors (not just PECI)
#     -r, --raw       Show raw millidegree values without conversion
#     -w, --watch     Continuously monitor (refresh every 2 seconds)
#     -j, --json      Output in JSON format
#     -h, --help      Show this help message
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware) with PECI support
#   - Kernel drivers: peci-cputemp, peci-dimmtemp
#   - Host CPU powered on
#
# Examples:
#   ./read-cpu-temps.sh              # Show PECI temperatures
#   ./read-cpu-temps.sh --all        # Show all hwmon temperatures
#   ./read-cpu-temps.sh --watch      # Continuous monitoring
#   ./read-cpu-temps.sh --json       # JSON output for scripting

set -euo pipefail

# --- Options ---
SHOW_ALL=0
RAW_MODE=0
WATCH_MODE=0
JSON_MODE=0

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--all)
            SHOW_ALL=1
            shift
            ;;
        -r|--raw)
            RAW_MODE=1
            shift
            ;;
        -w|--watch)
            WATCH_MODE=1
            shift
            ;;
        -j|--json)
            JSON_MODE=1
            shift
            ;;
        -h|--help)
            # Print the usage block from the script header
            echo "Read CPU and DIMM Temperatures"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -a, --all    Show all hwmon temperature sensors (not just PECI)"
            echo "  -r, --raw    Show raw millidegree values without conversion"
            echo "  -w, --watch  Continuously monitor (refresh every 2 seconds)"
            echo "  -j, --json   Output in JSON format"
            echo "  -h, --help   Show this help message"
            echo ""
            echo "Temperature files in hwmon sysfs:"
            echo "  temp<N>_input   Current temperature (millidegrees C)"
            echo "  temp<N>_max     Maximum threshold"
            echo "  temp<N>_crit    Critical threshold"
            echo "  temp<N>_label   Human-readable sensor label"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use $0 --help for usage information."
            exit 1
            ;;
    esac
done

# Convert millidegrees Celsius to degrees with one decimal place.
# hwmon sysfs reports temperatures in millidegrees (e.g., 45000 = 45.0 C).
# Arguments: $1 = millidegree value (integer)
# Output: temperature string (e.g., "45.0")
millideg_to_deg() {
    local mdeg="$1"
    local deg=$(( mdeg / 1000 ))
    local frac=$(( (mdeg % 1000) / 100 ))
    # Handle negative temperatures
    if [ "$mdeg" -lt 0 ]; then
        frac=$(( ((-mdeg) % 1000) / 100 ))
    fi
    echo "${deg}.${frac}"
}

# Check if a hwmon device is a PECI sensor.
# PECI hwmon names typically contain "peci" or "coretemp".
# Arguments: $1 = hwmon name string
# Returns: 0 if PECI-related, 1 otherwise
is_peci_sensor() {
    local name="$1"
    case "$name" in
        *peci*|*cputemp*|*dimmtemp*|*coretemp*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Read and display temperatures from a single hwmon device.
# Iterates over all temp*_input files in the hwmon directory.
# Arguments: $1 = hwmon sysfs directory path (e.g., /sys/class/hwmon/hwmon3)
read_hwmon_temps() {
    local hwmon_dir="$1"
    local hwmon_name
    hwmon_name=$(cat "$hwmon_dir/name" 2>/dev/null || echo "unknown")

    local found_temps=0

    # Iterate over temperature input files: temp1_input, temp2_input, etc.
    for temp_input in "$hwmon_dir"/temp*_input; do
        [ -f "$temp_input" ] || continue
        found_temps=1

        # Extract sensor index from filename (e.g., temp1_input -> 1)
        local idx
        idx=$(basename "$temp_input" | sed 's/temp\([0-9]*\)_input/\1/')

        # Read current temperature value
        local value
        value=$(cat "$temp_input" 2>/dev/null || echo "N/A")

        # Read label if available (e.g., "Die", "DTS", "Tcontrol", "DIMM0")
        local label="temp${idx}"
        local label_file="$hwmon_dir/temp${idx}_label"
        if [ -f "$label_file" ]; then
            label=$(cat "$label_file" 2>/dev/null || echo "temp${idx}")
        fi

        # Read thresholds if available
        local max_val=""
        local crit_val=""
        if [ -f "$hwmon_dir/temp${idx}_max" ]; then
            max_val=$(cat "$hwmon_dir/temp${idx}_max" 2>/dev/null || true)
        fi
        if [ -f "$hwmon_dir/temp${idx}_crit" ]; then
            crit_val=$(cat "$hwmon_dir/temp${idx}_crit" 2>/dev/null || true)
        fi

        if [ "$JSON_MODE" -eq 1 ]; then
            # JSON output mode
            local temp_c="null"
            local max_c="null"
            local crit_c="null"
            if [ "$value" != "N/A" ]; then
                temp_c=$(millideg_to_deg "$value")
            fi
            if [ -n "$max_val" ]; then
                max_c=$(millideg_to_deg "$max_val")
            fi
            if [ -n "$crit_val" ]; then
                crit_c=$(millideg_to_deg "$crit_val")
            fi
            echo "    {\"device\": \"$hwmon_name\", \"label\": \"$label\", \"temp_c\": $temp_c, \"max_c\": $max_c, \"crit_c\": $crit_c},"
        elif [ "$RAW_MODE" -eq 1 ]; then
            # Raw millidegree output
            printf "  %-20s %-15s %s mdeg" "$hwmon_name" "$label" "$value"
            if [ -n "$max_val" ]; then
                printf "  (max: %s)" "$max_val"
            fi
            if [ -n "$crit_val" ]; then
                printf "  (crit: %s)" "$crit_val"
            fi
            echo ""
        else
            # Formatted degree output
            local temp_str="N/A"
            if [ "$value" != "N/A" ]; then
                temp_str="$(millideg_to_deg "$value") C"
            fi

            printf "  %-20s %-15s %s" "$hwmon_name" "$label" "$temp_str"
            if [ -n "$max_val" ]; then
                printf "  (max: %s C)" "$(millideg_to_deg "$max_val")"
            fi
            if [ -n "$crit_val" ]; then
                printf "  (crit: %s C)" "$(millideg_to_deg "$crit_val")"
            fi
            echo ""
        fi
    done

    return $(( found_temps == 0 ))
}

# Main temperature reading function.
# Scans all hwmon devices and displays temperatures.
read_all_temps() {
    local sensor_count=0

    if [ "$JSON_MODE" -eq 1 ]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds 2>/dev/null || date)\","
        echo "  \"sensors\": ["
    else
        echo "========================================"
        echo "CPU / DIMM Temperature Readings"
        echo "$(date 2>/dev/null || true)"
        echo "========================================"
        echo ""
        printf "  %-20s %-15s %s\n" "DEVICE" "LABEL" "TEMPERATURE"
        printf "  %-20s %-15s %s\n" "------" "-----" "-----------"
    fi

    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon_dir" ] || continue

        local hwmon_name
        hwmon_name=$(cat "$hwmon_dir/name" 2>/dev/null || echo "unknown")

        # Filter to PECI sensors only (unless --all is specified)
        if [ "$SHOW_ALL" -eq 0 ] && ! is_peci_sensor "$hwmon_name"; then
            continue
        fi

        if read_hwmon_temps "$hwmon_dir" 2>/dev/null; then
            sensor_count=$((sensor_count + 1))
        fi
    done

    if [ "$JSON_MODE" -eq 1 ]; then
        # Remove trailing comma from last JSON entry (add empty placeholder)
        echo "    {}"
        echo "  ]"
        echo "}"
    else
        echo ""
        if [ "$sensor_count" -eq 0 ]; then
            if [ "$SHOW_ALL" -eq 0 ]; then
                echo "No PECI temperature sensors found."
                echo ""
                echo "Possible causes:"
                echo "  - Host CPU is not powered on (check: obmcutil state)"
                echo "  - PECI kernel drivers not loaded:"
                echo "      CONFIG_SENSORS_PECI_CPUTEMP=y"
                echo "      CONFIG_SENSORS_PECI_DIMMTEMP=y"
                echo "  - PECI bus not configured in device tree"
                echo ""
                echo "Try: $0 --all    (show all hwmon sensors)"
            else
                echo "No hwmon temperature sensors found."
            fi
        fi
    fi
}

# --- Entry point ---

if [ "$WATCH_MODE" -eq 1 ]; then
    echo "Monitoring temperatures (Ctrl+C to stop)..."
    echo ""
    while true; do
        # Clear screen if terminal supports it
        clear 2>/dev/null || true
        read_all_temps
        sleep 2
    done
else
    read_all_temps
fi
