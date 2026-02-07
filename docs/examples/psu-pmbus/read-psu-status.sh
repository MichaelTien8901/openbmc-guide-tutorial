#!/bin/bash
#
# PSU/PMBus Status Reader
#
# Reads PSU voltage, current, power, and temperature from hwmon sysfs paths
# and decodes the PMBus STATUS_WORD register. Supports multiple PSU slots
# and optional JSON output.
#
# Usage:
#   read-psu-status.sh [options]
#
# Options:
#   -p, --psu NUM        PSU slot number (default: auto-detect all)
#   -b, --bus NUM        I2C bus number (default: auto-detect)
#   -a, --addr ADDR      I2C address in hex, e.g., 0x58 (default: auto-detect)
#   -s, --status-only    Decode STATUS_WORD only, skip analog sensors
#   -j, --json           Output in JSON format
#   -h, --help           Show this help message
#
# Prerequisites:
#   - Running on OpenBMC (QEMU or hardware)
#   - PMBus kernel driver loaded (pmbus, ibm-cffps, inspur-ipsps, etc.)
#   - i2c-tools installed (for STATUS_WORD direct read)
#
# Examples:
#   read-psu-status.sh                  # Auto-detect and read all PSUs
#   read-psu-status.sh -p 0             # Read PSU slot 0 only
#   read-psu-status.sh -b 3 -a 0x58    # Read PSU at bus 3, address 0x58
#   read-psu-status.sh --status-only    # Decode STATUS_WORD registers only
#   read-psu-status.sh --json           # Output all readings as JSON

set -euo pipefail

# --- Configuration ---
PSU_NUM=""
I2C_BUS=""
I2C_ADDR=""
STATUS_ONLY=false
JSON_OUTPUT=false

# --- STATUS_WORD bit definitions (PMBus spec Part II, Table 32) ---
declare -A STATUS_BITS
STATUS_BITS[15]="VOUT"
STATUS_BITS[14]="IOUT/POUT"
STATUS_BITS[13]="INPUT"
STATUS_BITS[12]="MFR_SPECIFIC"
STATUS_BITS[11]="POWER_GOOD#"
STATUS_BITS[10]="FANS"
STATUS_BITS[9]="OTHER"
STATUS_BITS[8]="UNKNOWN"
STATUS_BITS[7]="BUSY"
STATUS_BITS[6]="OFF"
STATUS_BITS[5]="VOUT_OV"
STATUS_BITS[4]="IOUT_OC"
STATUS_BITS[3]="VIN_UV"
STATUS_BITS[2]="TEMPERATURE"
STATUS_BITS[1]="CML"
STATUS_BITS[0]="NONE_OF_THE_ABOVE"

# --- Helper functions ---

usage() {
    sed -n '2,/^$/s/^# \?//p' "$0"
    exit 0
}

log() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo "$@"
    fi
}

warn() {
    echo "WARNING: $*" >&2
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Convert raw hwmon value to human-readable form with unit
# hwmon reports: voltage in mV, current in mA, power in uW, temp in mC
format_sensor() {
    local raw_value=$1
    local sensor_type=$2

    case "$sensor_type" in
        voltage)
            # mV -> V (divide by 1000)
            awk "BEGIN { printf \"%.3f V\", $raw_value / 1000 }"
            ;;
        current)
            # mA -> A (divide by 1000)
            awk "BEGIN { printf \"%.3f A\", $raw_value / 1000 }"
            ;;
        power)
            # uW -> W (divide by 1000000)
            awk "BEGIN { printf \"%.2f W\", $raw_value / 1000000 }"
            ;;
        temperature)
            # mC -> C (divide by 1000)
            awk "BEGIN { printf \"%.1f C\", $raw_value / 1000 }"
            ;;
        fan)
            echo "${raw_value} RPM"
            ;;
        *)
            echo "$raw_value"
            ;;
    esac
}

# Read a single hwmon sensor file, return empty string on failure
read_hwmon_file() {
    local filepath=$1
    if [ -f "$filepath" ]; then
        cat "$filepath" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Find hwmon directories belonging to PMBus PSU devices
find_psu_hwmon_dirs() {
    local dirs=()
    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        if [ ! -d "$hwmon_dir" ]; then
            continue
        fi
        local name
        name=$(read_hwmon_file "$hwmon_dir/name")
        # Match common PMBus driver names
        case "$name" in
            pmbus|ibm-cffps|inspur-ipsps|adm1275|lm25066|max20730|tps53679|ucd9000|bel-pfe|delta-dps)
                dirs+=("$hwmon_dir")
                ;;
        esac
    done
    echo "${dirs[@]}"
}

# Find hwmon directory for a specific I2C bus/address
find_hwmon_by_i2c() {
    local bus=$1
    local addr=$2
    # Remove 0x prefix for sysfs path matching
    local addr_dec
    addr_dec=$(printf "%d" "$addr")
    local addr_fmt
    addr_fmt=$(printf "%d-%04x" "$bus" "$addr_dec")

    local i2c_dev="/sys/bus/i2c/devices/$addr_fmt"
    if [ -d "$i2c_dev/hwmon" ]; then
        local hwmon_dir
        hwmon_dir=$(ls -d "$i2c_dev/hwmon/hwmon"* 2>/dev/null | head -1)
        if [ -n "$hwmon_dir" ]; then
            echo "$hwmon_dir"
            return 0
        fi
    fi
    return 1
}

# Extract I2C bus and address from hwmon device path
get_i2c_info() {
    local hwmon_dir=$1
    local device_link
    device_link=$(readlink -f "$hwmon_dir/device" 2>/dev/null || echo "")
    if [ -n "$device_link" ]; then
        # Path looks like /sys/devices/.../i2c-3/3-0058
        local basename
        basename=$(basename "$device_link")
        if [[ "$basename" =~ ^([0-9]+)-([0-9a-f]+)$ ]]; then
            local bus="${BASH_REMATCH[1]}"
            local addr="0x${BASH_REMATCH[2]}"
            echo "$bus $addr"
            return 0
        fi
    fi
    echo "? ?"
}

# Read all analog sensors from a hwmon directory
read_analog_sensors() {
    local hwmon_dir=$1
    local psu_label=$2

    log ""
    log "--- Analog Sensors ($psu_label) ---"

    # Sensor map: hwmon file prefix -> (type, description)
    local -A SENSOR_MAP
    SENSOR_MAP[in1]="voltage:Input Voltage (VIN)"
    SENSOR_MAP[in2]="voltage:Output Voltage (VOUT)"
    SENSOR_MAP[curr1]="current:Input Current (IIN)"
    SENSOR_MAP[curr2]="current:Output Current (IOUT)"
    SENSOR_MAP[power1]="power:Input Power (PIN)"
    SENSOR_MAP[power2]="power:Output Power (POUT)"
    SENSOR_MAP[temp1]="temperature:Temperature 1"
    SENSOR_MAP[temp2]="temperature:Temperature 2"
    SENSOR_MAP[temp3]="temperature:Temperature 3"
    SENSOR_MAP[fan1]="fan:Fan Speed 1"

    local found_any=false

    for prefix in in1 in2 curr1 curr2 power1 power2 temp1 temp2 temp3 fan1; do
        local input_file="$hwmon_dir/${prefix}_input"
        if [ ! -f "$input_file" ]; then
            continue
        fi
        found_any=true

        local raw_value
        raw_value=$(read_hwmon_file "$input_file")
        if [ -z "$raw_value" ]; then
            continue
        fi

        local type_desc="${SENSOR_MAP[$prefix]}"
        local sensor_type="${type_desc%%:*}"
        local description="${type_desc#*:}"
        local formatted
        formatted=$(format_sensor "$raw_value" "$sensor_type")

        # Check for label override in hwmon
        local label_file="$hwmon_dir/${prefix}_label"
        if [ -f "$label_file" ]; then
            local label
            label=$(read_hwmon_file "$label_file")
            if [ -n "$label" ]; then
                description="$label"
            fi
        fi

        # Read alarm/fault status if available
        local alarm_str=""
        local fault_file="$hwmon_dir/${prefix}_alarm"
        if [ -f "$fault_file" ]; then
            local alarm
            alarm=$(read_hwmon_file "$fault_file")
            if [ "$alarm" = "1" ]; then
                alarm_str=" [ALARM]"
            fi
        fi

        log "  $(printf '%-30s' "$description") $formatted$alarm_str"
    done

    if [ "$found_any" = false ]; then
        log "  (no sensor files found)"
    fi
}

# Decode STATUS_WORD register
decode_status_word() {
    local status_word=$1
    local psu_label=$2

    log ""
    log "--- STATUS_WORD ($psu_label) ---"
    log "  Raw value: $(printf '0x%04X' "$status_word")"
    log ""

    if [ "$status_word" -eq 0 ]; then
        log "  All OK -- no faults or warnings"
        return 0
    fi

    local fault_count=0
    for bit in $(seq 15 -1 0); do
        local mask=$((1 << bit))
        if (( status_word & mask )); then
            local name="${STATUS_BITS[$bit]:-RESERVED}"
            log "  Bit $bit  $name  [ACTIVE]"
            fault_count=$((fault_count + 1))
        fi
    done

    log ""
    log "  Active fault/warning bits: $fault_count"
    return 0
}

# Read STATUS_WORD from hwmon or via i2cget
read_status_word() {
    local hwmon_dir=$1
    local psu_label=$2
    local bus=$3
    local addr=$4

    # Try reading from hwmon sysfs first (some drivers expose it)
    # STATUS_WORD is PMBus command 0x79
    local status_file="$hwmon_dir/status0_input"
    if [ -f "$status_file" ]; then
        local raw
        raw=$(read_hwmon_file "$status_file")
        if [ -n "$raw" ]; then
            decode_status_word "$raw" "$psu_label"
            return 0
        fi
    fi

    # Fall back to i2cget if available and we know the bus/address
    if [ "$bus" != "?" ] && [ "$addr" != "?" ] && command -v i2cget &>/dev/null; then
        # PMBus STATUS_WORD (0x79) is a 2-byte read
        local raw_hex
        raw_hex=$(i2cget -f -y "$bus" "$addr" 0x79 w 2>/dev/null || echo "")
        if [ -n "$raw_hex" ]; then
            local raw_dec
            raw_dec=$(printf "%d" "$raw_hex")
            decode_status_word "$raw_dec" "$psu_label"
            return 0
        fi
    fi

    log ""
    log "--- STATUS_WORD ($psu_label) ---"
    log "  Unable to read STATUS_WORD (no hwmon status file, i2cget unavailable,"
    log "  or I2C bus/address unknown)"
}

# Read all data from a single PSU hwmon directory
read_psu() {
    local hwmon_dir=$1
    local psu_index=$2

    local name
    name=$(read_hwmon_file "$hwmon_dir/name")
    local i2c_info
    i2c_info=$(get_i2c_info "$hwmon_dir")
    local bus="${i2c_info%% *}"
    local addr="${i2c_info##* }"

    local psu_label="PSU${psu_index} (${name}, bus=${bus}, addr=${addr})"

    log "========================================"
    log "$psu_label"
    log "========================================"
    log "  hwmon path: $hwmon_dir"

    if [ "$STATUS_ONLY" = false ]; then
        read_analog_sensors "$hwmon_dir" "$psu_label"
    fi

    read_status_word "$hwmon_dir" "$psu_label" "$bus" "$addr"
}

# Collect all PSU data into a JSON structure
output_json() {
    local hwmon_dirs=("$@")
    local psu_index=0
    local first=true

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds 2>/dev/null || date)\","
    echo "  \"psus\": ["

    for hwmon_dir in "${hwmon_dirs[@]}"; do
        if [ ! -d "$hwmon_dir" ]; then
            continue
        fi

        if [ "$first" = true ]; then
            first=false
        else
            echo "    ,"
        fi

        local name
        name=$(read_hwmon_file "$hwmon_dir/name")
        local i2c_info
        i2c_info=$(get_i2c_info "$hwmon_dir")
        local bus="${i2c_info%% *}"
        local addr="${i2c_info##* }"

        echo "    {"
        echo "      \"index\": $psu_index,"
        echo "      \"driver\": \"$name\","
        echo "      \"bus\": \"$bus\","
        echo "      \"address\": \"$addr\","
        echo "      \"hwmon_path\": \"$hwmon_dir\","
        echo "      \"sensors\": {"

        # Read analog sensors into JSON
        local sensor_first=true
        for prefix in in1 in2 curr1 curr2 power1 power2 temp1 temp2 temp3 fan1; do
            local input_file="$hwmon_dir/${prefix}_input"
            if [ ! -f "$input_file" ]; then
                continue
            fi
            local raw_value
            raw_value=$(read_hwmon_file "$input_file")
            if [ -z "$raw_value" ]; then
                continue
            fi

            if [ "$sensor_first" = true ]; then
                sensor_first=false
            else
                echo ","
            fi

            # Get label if available
            local label="$prefix"
            local label_file="$hwmon_dir/${prefix}_label"
            if [ -f "$label_file" ]; then
                local custom_label
                custom_label=$(read_hwmon_file "$label_file")
                if [ -n "$custom_label" ]; then
                    label="$custom_label"
                fi
            fi

            printf "        \"%s\": { \"raw\": %s, \"label\": \"%s\" }" "$prefix" "$raw_value" "$label"
        done

        echo ""
        echo "      },"

        # Read STATUS_WORD
        local status_val="null"
        local status_file="$hwmon_dir/status0_input"
        if [ -f "$status_file" ]; then
            local raw
            raw=$(read_hwmon_file "$status_file")
            if [ -n "$raw" ]; then
                status_val="$raw"
            fi
        elif [ "$bus" != "?" ] && [ "$addr" != "?" ] && command -v i2cget &>/dev/null; then
            local raw_hex
            raw_hex=$(i2cget -f -y "$bus" "$addr" 0x79 w 2>/dev/null || echo "")
            if [ -n "$raw_hex" ]; then
                status_val=$(printf "%d" "$raw_hex")
            fi
        fi

        echo "      \"status_word\": $status_val"
        echo "    }"

        psu_index=$((psu_index + 1))
    done

    echo "  ]"
    echo "}"
}

# --- Parse arguments ---

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--psu)
            PSU_NUM="$2"
            shift 2
            ;;
        -b|--bus)
            I2C_BUS="$2"
            shift 2
            ;;
        -a|--addr)
            I2C_ADDR="$2"
            shift 2
            ;;
        -s|--status-only)
            STATUS_ONLY=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1 (use --help for usage)"
            ;;
    esac
done

# --- Main ---

log "========================================"
log "PSU/PMBus Status Reader"
log "========================================"
log "Timestamp: $(date)"
log ""

# Build list of hwmon directories to read
HWMON_DIRS=()

if [ -n "$I2C_BUS" ] && [ -n "$I2C_ADDR" ]; then
    # Specific bus/address requested
    dir=$(find_hwmon_by_i2c "$I2C_BUS" "$I2C_ADDR") || \
        die "No hwmon device found at bus=$I2C_BUS addr=$I2C_ADDR"
    HWMON_DIRS=("$dir")
elif [ -n "$PSU_NUM" ]; then
    # Specific PSU slot requested -- find all PSU hwmons and index
    read -ra ALL_DIRS <<< "$(find_psu_hwmon_dirs)"
    if [ "${#ALL_DIRS[@]}" -eq 0 ]; then
        die "No PMBus PSU hwmon devices found"
    fi
    if [ "$PSU_NUM" -ge "${#ALL_DIRS[@]}" ]; then
        die "PSU $PSU_NUM not found (only ${#ALL_DIRS[@]} PSU(s) detected)"
    fi
    HWMON_DIRS=("${ALL_DIRS[$PSU_NUM]}")
else
    # Auto-detect all PSU hwmon directories
    read -ra HWMON_DIRS <<< "$(find_psu_hwmon_dirs)"
fi

if [ "${#HWMON_DIRS[@]}" -eq 0 ]; then
    die "No PMBus PSU hwmon devices found. Check that:
  - PMBus kernel driver is loaded (lsmod | grep pmbus)
  - PSU is present and detected on I2C bus
  - Device tree or manual binding is configured
  Try: echo 'pmbus 0x58' > /sys/bus/i2c/devices/i2c-3/new_device"
fi

# JSON output mode
if [ "$JSON_OUTPUT" = true ]; then
    output_json "${HWMON_DIRS[@]}"
    exit 0
fi

# Standard text output
log "Detected ${#HWMON_DIRS[@]} PSU(s)"

psu_index=0
for dir in "${HWMON_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log ""
        read_psu "$dir" "$psu_index"
        psu_index=$((psu_index + 1))
    fi
done

log ""
log "========================================"
log "Done"
log "========================================"
