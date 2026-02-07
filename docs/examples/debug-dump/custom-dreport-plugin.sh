#!/bin/bash
#
# Custom dreport plugin: Collect platform-specific diagnostic data
#
# Installation:
#   Copy this file to /usr/share/dreport.d/plugins.d/ on your OpenBMC system
#   and rename it following the dreport naming convention:
#
#     cp custom-dreport-plugin.sh \
#        /usr/share/dreport.d/plugins.d/pl_User99_platformdata
#     chmod +x /usr/share/dreport.d/plugins.d/pl_User99_platformdata
#
# Naming convention: pl_<Type><Priority>_<description>
#   - pl_         Fixed prefix for all dreport plugins
#   - User        Plugin type: runs during user-initiated dumps
#   - 99          Priority: 00 (first) to 99 (last). Use high numbers
#                 for custom plugins to run after upstream ones.
#   - platformdata  Descriptive name (no spaces or special characters)
#
# How dreport plugins work:
#   - dreport sources each plugin as a shell script
#   - The plugin uses add_copy_file() to include files in the dump archive
#   - The plugin uses log_summary() to add text entries to the dump summary
#   - Plugins receive the dump directory path via the dump_dir variable
#   - Exit 0 on success; non-zero skips this plugin gracefully
#
# Environment variables available to plugins:
#   dump_dir     - Directory where dump files are collected
#   name         - The dump name/identifier
#   dump_id      - Numeric dump ID
#   EPOCHTIME    - Timestamp when dump collection started
#

# Description shown in dreport summary
desc="Platform-specific diagnostic data"

# Source the dreport utility functions (provides add_copy_file, log_summary, etc.)
# This file is provided by phosphor-debug-collector and must be present on the BMC.
. /usr/share/dreport.d/include.d/functions

# ---------------------------------------------------------------------------
# Section 1: Collect CPLD version registers via I2C
# ---------------------------------------------------------------------------
# Many platforms have a CPLD on the baseboard that holds firmware version and
# board revision registers. Adjust the I2C bus and address for your hardware.

CPLD_BUS=1
CPLD_ADDR=0x40
CPLD_VERSION_REG=0x00
CPLD_BOARD_REV_REG=0x01

collect_cpld_info() {
    local outfile="${dump_dir}/cpld_info.txt"

    log_summary "Collecting CPLD information (bus=${CPLD_BUS}, addr=${CPLD_ADDR})"

    {
        echo "=== CPLD Information ==="
        echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo ""

        # Read CPLD firmware version register
        CPLD_VER=$(i2cget -f -y "${CPLD_BUS}" "${CPLD_ADDR}" "${CPLD_VERSION_REG}" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "CPLD Version Register: ${CPLD_VER}"
        else
            echo "CPLD Version Register: read failed (bus=${CPLD_BUS} addr=${CPLD_ADDR})"
        fi

        # Read board revision register
        BOARD_REV=$(i2cget -f -y "${CPLD_BUS}" "${CPLD_ADDR}" "${CPLD_BOARD_REV_REG}" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "Board Revision Register: ${BOARD_REV}"
        else
            echo "Board Revision Register: read failed"
        fi
    } > "${outfile}" 2>&1

    add_copy_file "${outfile}" "cpld_info.txt"
}

# ---------------------------------------------------------------------------
# Section 2: Collect GPIO state snapshot
# ---------------------------------------------------------------------------
# Capture the state of all GPIOs. This is useful for diagnosing power
# sequencing issues, fan failures, or host communication problems.

collect_gpio_state() {
    local outfile="${dump_dir}/gpio_state.txt"

    log_summary "Collecting GPIO state snapshot"

    {
        echo "=== GPIO State Snapshot ==="
        echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo ""

        # List all GPIO chips and their lines
        if command -v gpioinfo > /dev/null 2>&1; then
            gpioinfo
        elif [ -d /sys/class/gpio ]; then
            echo "gpioinfo not available, reading from sysfs"
            for gpio_dir in /sys/class/gpio/gpio*; do
                [ -d "${gpio_dir}" ] || continue
                GPIO_NUM=$(basename "${gpio_dir}" | sed 's/gpio//')
                GPIO_VAL=$(cat "${gpio_dir}/value" 2>/dev/null || echo "?")
                GPIO_DIR=$(cat "${gpio_dir}/direction" 2>/dev/null || echo "?")
                echo "GPIO ${GPIO_NUM}: value=${GPIO_VAL} direction=${GPIO_DIR}"
            done
        else
            echo "No GPIO interface available"
        fi
    } > "${outfile}" 2>&1

    add_copy_file "${outfile}" "gpio_state.txt"
}

# ---------------------------------------------------------------------------
# Section 3: Collect platform sensor summary
# ---------------------------------------------------------------------------
# Dump all D-Bus sensor values for a point-in-time snapshot. This captures
# temperatures, fan speeds, voltages, and power readings.

collect_sensor_summary() {
    local outfile="${dump_dir}/sensor_summary.txt"

    log_summary "Collecting sensor summary"

    {
        echo "=== Sensor Summary ==="
        echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo ""

        # Enumerate all sensor paths under the Sensor subtree
        SENSOR_PATHS=$(busctl tree xyz.openbmc_project.HwmonTempSensor 2>/dev/null \
            | grep "/xyz/openbmc_project/sensors/")

        if [ -z "${SENSOR_PATHS}" ]; then
            # Try alternative service names used on some platforms
            SENSOR_PATHS=$(busctl tree xyz.openbmc_project.ADCSensor 2>/dev/null \
                | grep "/xyz/openbmc_project/sensors/")
        fi

        if [ -n "${SENSOR_PATHS}" ]; then
            for path in ${SENSOR_PATHS}; do
                SENSOR_NAME=$(basename "${path}")
                VALUE=$(busctl get-property xyz.openbmc_project.HwmonTempSensor \
                    "${path}" xyz.openbmc_project.Sensor.Value Value 2>/dev/null \
                    | awk '{print $2}')
                UNIT=$(busctl get-property xyz.openbmc_project.HwmonTempSensor \
                    "${path}" xyz.openbmc_project.Sensor.Value Unit 2>/dev/null \
                    | awk -F'"' '{print $2}' | awk -F'.' '{print $NF}')
                echo "${SENSOR_NAME}: ${VALUE:-N/A} (${UNIT:-unknown})"
            done
        else
            echo "No sensors found via D-Bus"
        fi

        echo ""
        echo "--- hwmon raw values ---"
        for hwmon_dir in /sys/class/hwmon/hwmon*; do
            [ -d "${hwmon_dir}" ] || continue
            HWMON_NAME=$(cat "${hwmon_dir}/name" 2>/dev/null || echo "unknown")
            echo "[${HWMON_NAME}]"
            for input in "${hwmon_dir}"/temp*_input "${hwmon_dir}"/fan*_input \
                         "${hwmon_dir}"/in*_input; do
                [ -f "${input}" ] || continue
                LABEL=$(basename "${input}")
                RAW=$(cat "${input}" 2>/dev/null || echo "?")
                echo "  ${LABEL} = ${RAW}"
            done
        done
    } > "${outfile}" 2>&1

    add_copy_file "${outfile}" "sensor_summary.txt"
}

# ---------------------------------------------------------------------------
# Section 4: Collect platform-specific configuration files
# ---------------------------------------------------------------------------
# Include key configuration files that aid in diagnosing misconfigurations.

collect_config_files() {
    log_summary "Collecting platform configuration files"

    # Machine identity
    if [ -f /etc/machine.conf ]; then
        add_copy_file /etc/machine.conf "config/machine.conf"
    fi

    # OS release info (build version, timestamp)
    if [ -f /etc/os-release ]; then
        add_copy_file /etc/os-release "config/os-release"
    fi

    # Entity Manager configurations (JSON hardware descriptions)
    EM_CONFIG_DIR="/usr/share/entity-manager/configurations"
    if [ -d "${EM_CONFIG_DIR}" ]; then
        for json_file in "${EM_CONFIG_DIR}"/*.json; do
            [ -f "${json_file}" ] || continue
            FNAME=$(basename "${json_file}")
            add_copy_file "${json_file}" "config/entity-manager/${FNAME}"
        done
    fi

    # U-Boot environment (if accessible)
    if command -v fw_printenv > /dev/null 2>&1; then
        local outfile="${dump_dir}/uboot_env.txt"
        fw_printenv > "${outfile}" 2>&1
        add_copy_file "${outfile}" "config/uboot_env.txt"
    fi
}

# ---------------------------------------------------------------------------
# Main: Run all collection functions
# ---------------------------------------------------------------------------
# Each function handles its own errors gracefully. If a subsystem is not
# present on this platform, the function logs a message and moves on.

collect_cpld_info
collect_gpio_state
collect_sensor_summary
collect_config_files

log_summary "Platform data collection complete"
exit 0
