---
layout: default
title: PSU & PMBus Management
parent: Core Services
nav_order: 17
difficulty: intermediate
prerequisites:
  - environment-setup
  - i2c-device-integration-guide
last_modified_date: 2026-02-06
---

# PSU & PMBus Management
{: .no_toc }

Monitor power supplies through the PMBus protocol, from kernel hwmon interfaces through D-Bus sensors to Redfish telemetry.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Power Supply Units (PSUs) in server platforms communicate over the **PMBus** protocol, an I2C-based standard for power device management. OpenBMC provides a full monitoring pipeline that reads PMBus telemetry from hardware and exposes it through standardized interfaces for out-of-band management.

The pipeline flows through five layers:

1. **PMBus hardware** -- the PSU responds to I2C commands defined by the PMBus specification
2. **Linux hwmon** -- the kernel `pmbus` driver translates PMBus registers into sysfs attributes
3. **phosphor-power / dbus-sensors** -- userspace daemons read hwmon and publish D-Bus sensor objects
4. **D-Bus** -- the common bus where all OpenBMC services exchange sensor data and inventory
5. **Redfish / IPMI** -- northbound interfaces that expose PSU data to remote management tools

This guide covers the complete workflow: configuring the kernel driver, writing Entity Manager JSON for PSU discovery, setting up phosphor-regulators for voltage regulator control, reading sensor data through D-Bus and Redfish, and troubleshooting common issues.

{: .note }
PSU monitoring is **partially testable** in QEMU. The ast2600-evb QEMU target emulates I2C buses, but real PMBus device responses require physical hardware or a PMBus simulator connected to the I2C bus.

---

## Architecture

### PSU Monitoring Data Flow

```
PSU (PMBus Device on I2C Bus)
        |
        v
Linux Kernel: pmbus driver
  /sys/class/hwmon/hwmonN/
  ├── in1_input    (input voltage)
  ├── in2_input    (output voltage)
  ├── curr1_input  (input current)
  ├── curr2_input  (output current)
  ├── power1_input (input power)
  ├── power2_input (output power)
  ├── temp1_input  (hotspot temp)
  └── fan1_input   (internal fan RPM)
        |
        v
Userspace Daemons
  ├── PSUSensor (dbus-sensors)     -- reads hwmon, publishes sensors
  ├── phosphor-psu-monitor         -- PSU presence, faults, inventory
  └── phosphor-regulators          -- VR config and rail monitoring
        |
        v
D-Bus
  ├── xyz.openbmc_project.Sensor.Value        (telemetry)
  ├── xyz.openbmc_project.Inventory.Item      (presence)
  ├── xyz.openbmc_project.State.Decorator.OperationalStatus (health)
  └── xyz.openbmc_project.Inventory.Decorator.Asset (FRU data)
        |
        v
Northbound Interfaces
  ├── bmcweb (Redfish)  --> /redfish/v1/Chassis/chassis/Power
  └── ipmid  (IPMI)    --> SDR / SEL entries
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.Sensor.Value` | `/xyz/openbmc_project/sensors/voltage/PSU0_Input_Voltage` | Voltage, current, power, temperature readings |
| `xyz.openbmc_project.Inventory.Item` | `/xyz/openbmc_project/inventory/system/chassis/powersupply0` | PSU presence and identity |
| `xyz.openbmc_project.Inventory.Decorator.Asset` | `/xyz/openbmc_project/inventory/system/chassis/powersupply0` | Manufacturer, model, serial number |
| `xyz.openbmc_project.State.Decorator.OperationalStatus` | `/xyz/openbmc_project/inventory/system/chassis/powersupply0` | Functional status (true/false) |

### Key Repositories

| Repository | Component | Description |
|------------|-----------|-------------|
| [phosphor-power](https://github.com/openbmc/phosphor-power) | `phosphor-power-supply/` | PSU monitoring daemon |
| [phosphor-power](https://github.com/openbmc/phosphor-power) | `phosphor-regulators/` | Voltage regulator configuration and control |
| [dbus-sensors](https://github.com/openbmc/dbus-sensors) | `src/PSUSensor.cpp` | PSU sensor daemon (reads hwmon, publishes D-Bus) |
| [entity-manager](https://github.com/openbmc/entity-manager) | JSON configs | PSU hardware discovery and configuration |

---

## Configuration

### PMBus Sysfs Interface

When the kernel `pmbus` driver binds to a PSU, it creates hwmon attributes under `/sys/class/hwmon/hwmonN/`. The following table lists the most common attributes and their corresponding PMBus registers.

| Sysfs Attribute | PMBus Command | Code | Description | Unit |
|-----------------|---------------|------|-------------|------|
| `in1_input` | READ_VIN | 0x88 | Input voltage | millivolts |
| `in2_input` | READ_VOUT | 0x8B | Output voltage | millivolts |
| `curr1_input` | READ_IIN | 0x89 | Input current | milliamps |
| `curr2_input` | READ_IOUT | 0x8C | Output current | milliamps |
| `power1_input` | READ_PIN | 0x97 | Input power | microwatts |
| `power2_input` | READ_POUT | 0x96 | Output power | microwatts |
| `temp1_input` | READ_TEMPERATURE_1 | 0x8D | Temperature sensor 1 | millidegrees C |
| `temp2_input` | READ_TEMPERATURE_2 | 0x8E | Temperature sensor 2 | millidegrees C |
| `fan1_input` | READ_FAN_SPEED_1 | 0x90 | Fan speed | RPM |

The PMBus STATUS_WORD register (0x79) provides a summary of all fault conditions:

```bash
# Read STATUS_WORD directly from I2C
i2cget -y 3 0x58 0x79 w

# Bit definitions (STATUS_WORD, 16-bit):
#   Bit 15: VOUT fault or warning
#   Bit 14: IOUT/POUT fault or warning
#   Bit 13: INPUT fault or warning
#   Bit 12: MFR specific fault
#   Bit 11: POWER_GOOD negated
#   Bit  6: OFF (unit not providing power)
#   Bit  5: FANS fault or warning
#   Bit  4: OTHER (reserved)
#   Bit  3: VIN_UV fault
#   Bit  2: TEMPERATURE fault or warning
#   Bit  1: CML (communication/logic fault)
#   Bit  0: None of the above
```

{: .tip }
Use `i2cget` and `i2cdump` to verify PMBus communication before configuring the monitoring stack. If raw I2C reads fail, the PSU address may be wrong or the I2C bus is not enabled in the device tree.

### Device Tree Configuration

Declare the PSU on its I2C bus in the device tree so the kernel `pmbus` driver binds automatically at boot:

```dts
&i2c3 {
    status = "okay";

    psu0: psu@58 {
        compatible = "pmbus";
        reg = <0x58>;
    };

    psu1: psu@59 {
        compatible = "pmbus";
        reg = <0x59>;
    };
};
```

{: .note }
If your PSU has a vendor-specific driver (for example, `ibm,cffps` or `delta,dps800`), use the vendor compatible string instead of generic `"pmbus"`. Vendor drivers expose additional attributes such as firmware version and detailed fault registers.

### Verify Kernel Driver Binding

```bash
# Check the I2C bus for devices
i2cdetect -y 3

# Verify the pmbus driver bound
ls /sys/bus/i2c/devices/3-0058/driver
# Should show symlink to pmbus or vendor driver

# Find the hwmon path
ls /sys/bus/i2c/devices/3-0058/hwmon/
# hwmon5

# Read input voltage (millivolts)
cat /sys/class/hwmon/hwmon5/in1_input
# 229800  (229.8 V)

# Read output power (microwatts)
cat /sys/class/hwmon/hwmon5/power2_input
# 245000000  (245 W)
```

### Entity Manager PSU Configuration

Entity Manager discovers PSUs and publishes their configuration on D-Bus so that sensor daemons know which devices to monitor. Create a JSON configuration file for your platform.

**File**: `/usr/share/entity-manager/configurations/my-platform-psu.json`

```json
{
    "Name": "PSU0",
    "Type": "Board",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'MyPSU-1200W'})",

    "Exposes": [
        {
            "Name": "PSU0",
            "Type": "pmbus",
            "Bus": 3,
            "Address": "0x58",
            "Labels": [
                "vin",
                "vout1",
                "iin",
                "iout1",
                "pin",
                "pout1",
                "temp1",
                "temp2",
                "fan1"
            ],
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Label": "temp1",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 100
                },
                {
                    "Direction": "greater than",
                    "Label": "temp1",
                    "Name": "upper warning",
                    "Severity": 0,
                    "Value": 85
                },
                {
                    "Direction": "less than",
                    "Label": "vin",
                    "Name": "lower critical",
                    "Severity": 1,
                    "Value": 180
                },
                {
                    "Direction": "less than",
                    "Label": "vin",
                    "Name": "lower warning",
                    "Severity": 0,
                    "Value": 200
                }
            ]
        }
    ],

    "xyz.openbmc_project.Inventory.Item": {
        "Present": true,
        "PrettyName": "Power Supply 0"
    },

    "xyz.openbmc_project.Inventory.Decorator.Asset": {
        "Manufacturer": "$PRODUCT_MANUFACTURER",
        "Model": "$PRODUCT_PRODUCT_NAME",
        "SerialNumber": "$PRODUCT_SERIAL_NUMBER"
    }
}
```

**Key fields:**

| Field | Description |
|-------|-------------|
| `Probe` | Matches against FRU data to detect PSU presence. Use `"TRUE"` for always-present PSUs. |
| `Type` (in Exposes) | Set to `"pmbus"` so PSUSensor daemon claims this device. |
| `Bus` / `Address` | I2C bus number and 7-bit hex address of the PSU. |
| `Labels` | Which PMBus sensor channels to expose. Maps to hwmon attribute names. |
| `Thresholds` | Warning and critical limits for alarm generation. |
| `$PRODUCT_*` | Entity Manager substitutes these from FRU EEPROM data at runtime. |

{: .warning }
The `Labels` array controls which sensors appear on D-Bus. If you omit a label, PSUSensor will not create a sensor for that channel even if the hwmon attribute exists. Always verify which labels your PSU actually supports by checking the hwmon sysfs attributes.

### Voltage Regulator Configuration (phosphor-regulators)

phosphor-regulators manages on-board voltage regulators (VRMs) that use PMBus for control. It reads a JSON configuration file to set output voltages during power-on and monitor rail health during operation.

**File**: `/usr/share/phosphor-regulators/config.json`

```json
{
    "rules": [
        {
            "id": "set_voltage_rule",
            "actions": [
                {
                    "pmbus_write_vout_command": {
                        "format": "linear",
                        "exponent": -8
                    }
                }
            ]
        },
        {
            "id": "read_sensors_rule",
            "actions": [
                {
                    "pmbus_read_sensor": {
                        "type": "vout",
                        "command": "0x8B",
                        "format": "linear_16"
                    }
                },
                {
                    "pmbus_read_sensor": {
                        "type": "iout",
                        "command": "0x8C",
                        "format": "linear_11"
                    }
                },
                {
                    "pmbus_read_sensor": {
                        "type": "temperature",
                        "command": "0x8D",
                        "format": "linear_11"
                    }
                }
            ]
        }
    ],
    "chassis": [
        {
            "number": 1,
            "inventory_path": "/xyz/openbmc_project/inventory/system/chassis",
            "devices": [
                {
                    "id": "vdd_cpu0",
                    "is_regulator": true,
                    "fru": "/xyz/openbmc_project/inventory/system/chassis/motherboard/cpu0",
                    "i2c_interface": {
                        "bus": 5,
                        "address": "0x40"
                    },
                    "presence_detection": {
                        "rule_id": "detect_presence_rule"
                    },
                    "configuration": {
                        "volts": 1.0,
                        "rule_id": "set_voltage_rule"
                    },
                    "rails": [
                        {
                            "id": "vdd_cpu0_rail",
                            "sensor_monitoring": {
                                "rule_id": "read_sensors_rule"
                            }
                        }
                    ]
                }
            ]
        }
    ]
}
```

**Configuration sections:**

| Section | Purpose |
|---------|---------|
| `rules` | Reusable action sequences for reading sensors or writing voltage commands. |
| `chassis` | Top-level grouping that maps to a physical chassis in inventory. |
| `devices` | Individual voltage regulators with I2C bus/address and FRU path. |
| `configuration` | Voltage set point and rule to apply during power-on. |
| `rails` | Output rails to monitor; each rail can have sensor monitoring rules. |

{: .note }
The `format` field in `pmbus_read_sensor` specifies how to decode the PMBus register. Use `linear_11` for current, power, and temperature readings (11-bit mantissa, 5-bit exponent). Use `linear_16` for VOUT readings (16-bit mantissa with exponent from VOUT_MODE register).

### Build-Time Configuration (Yocto)

Include the PSU monitoring components in your image:

```bitbake
# In your machine .conf or image recipe

# PSU sensor daemon (from dbus-sensors)
IMAGE_INSTALL:append = " psusensor"

# PSU monitoring and inventory (from phosphor-power)
IMAGE_INSTALL:append = " \
    phosphor-power-psu-monitor \
    phosphor-power-regulators \
    phosphor-power-utils \
"
```

### Deploy Configuration via Yocto bbappend

#### Entity Manager PSU Config

```bash
# meta-myplatform/recipes-phosphor/configuration/entity-manager/
# +-- files/
# |   +-- my-platform-psu.json
# +-- entity-manager_%.bbappend

cat > entity-manager_%.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://my-platform-psu.json"

do_install:append() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0444 ${WORKDIR}/my-platform-psu.json \
        ${D}${datadir}/entity-manager/configurations/
}
EOF
```

#### Regulators Config

```bash
# meta-myplatform/recipes-phosphor/power/phosphor-regulators/
# +-- files/
# |   +-- my-regulators-config.json
# +-- phosphor-regulators_%.bbappend

cat > phosphor-regulators_%.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://my-regulators-config.json"

do_install:append() {
    install -d ${D}${datadir}/phosphor-regulators
    install -m 0644 ${WORKDIR}/my-regulators-config.json \
        ${D}${datadir}/phosphor-regulators/config.json
}
EOF
```

---

## Porting Guide

Follow these steps to bring up PSU monitoring on a new platform.

### Step 1: Identify PSU Hardware

Determine the following from your platform schematic:

| Parameter | Example | How to find |
|-----------|---------|-------------|
| I2C bus number | 3 | Schematic, trace from BMC I2C controller to PSU connector |
| PSU I2C address | 0x58 | PSU datasheet or `i2cdetect -y <bus>` |
| Number of PSUs | 2 | Platform design (N+1 redundancy) |
| PMBus commands supported | See datasheet | PSU vendor documentation |
| Vendor-specific driver | `"delta,dps800"` | Kernel driver list or `"pmbus"` for generic |

### Step 2: Add Device Tree Entries

```dts
// In your platform device tree (aspeed-bmc-myplatform.dts)
&i2c3 {
    status = "okay";

    psu0: psu@58 {
        compatible = "pmbus";
        reg = <0x58>;
    };

    psu1: psu@59 {
        compatible = "pmbus";
        reg = <0x59>;
    };
};
```

### Step 3: Verify Kernel Binding

After booting with the updated device tree:

```bash
# Confirm devices appear on the bus
i2cdetect -y 3

# Verify driver bound
ls /sys/bus/i2c/devices/3-0058/driver

# List hwmon attributes to determine which Labels to use
ls /sys/bus/i2c/devices/3-0058/hwmon/hwmon*/
# in1_input  in2_input  curr1_input  curr2_input
# power1_input  power2_input  temp1_input  fan1_input
```

### Step 4: Create Entity Manager JSON

Map each hwmon attribute to a Label in your JSON configuration. Only include labels that exist in sysfs.

### Step 5: Add Yocto bbappend Files

Install your Entity Manager JSON and, if applicable, your phosphor-regulators config through bbappend files as shown in the Configuration section.

### Step 6: Verify End-to-End

```bash
# Check Entity Manager detected the PSU
busctl tree xyz.openbmc_project.EntityManager | grep -i psu

# Verify PSU sensors on D-Bus
busctl tree xyz.openbmc_project.PSUSensor

# Read a sensor value
busctl get-property xyz.openbmc_project.PSUSensor \
    /xyz/openbmc_project/sensors/voltage/PSU0_Input_Voltage \
    xyz.openbmc_project.Sensor.Value Value

# Check via Redfish
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Power
```

---

## Code Examples

Working examples are available in the [examples/psu-pmbus](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/psu-pmbus) directory:

- `psu-entity-manager.json` -- Entity Manager configuration for a dual-PSU platform
- `regulators-config.json` -- phosphor-regulators configuration with VRM rules
- `psu-status-check.sh` -- Shell script to read PMBus STATUS_WORD and decode fault bits

### Reading PSU Sensors from D-Bus

```bash
#!/bin/bash
# Read all PSU sensors and display a summary

PSU_SERVICE="xyz.openbmc_project.PSUSensor"
SENSOR_BASE="/xyz/openbmc_project/sensors"

echo "=== PSU Sensor Readings ==="

for type in voltage current power temperature; do
    echo ""
    echo "--- ${type} ---"
    busctl tree ${PSU_SERVICE} 2>/dev/null \
        | grep "${type}" \
        | while read -r path; do
            value=$(busctl get-property ${PSU_SERVICE} \
                "${path}" \
                xyz.openbmc_project.Sensor.Value Value 2>/dev/null \
                | awk '{print $2}')
            name=$(basename "${path}")
            echo "  ${name}: ${value}"
        done
done
```

### Querying PSU Inventory via D-Bus

```bash
# List PSU inventory objects
busctl tree xyz.openbmc_project.Inventory.Manager | grep powersupply

# Get PSU presence
busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0 \
    xyz.openbmc_project.Inventory.Item Present

# Get PSU asset information (manufacturer, model, serial)
busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0 \
    xyz.openbmc_project.Inventory.Decorator.Asset Manufacturer

busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0 \
    xyz.openbmc_project.Inventory.Decorator.Asset SerialNumber
```

### Querying PSU Data via Redfish

```bash
# Get power supply collection
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Power \
    | jq '.PowerSupplies'

# Get specific sensor reading
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Sensors/PSU0_Input_Voltage

# Get power supply inventory with FRU data
curl -k -u root:0penBmc \
    https://localhost:2443/redfish/v1/Chassis/chassis/Power \
    | jq '.PowerSupplies[] | {Name, Model, Manufacturer, SerialNumber, Status}'
```

---

## Troubleshooting

### PSU Not Detected on I2C

```bash
# Scan the I2C bus
i2cdetect -y 3
# If address 0x58 shows "--", the PSU is not responding

# Check device tree
cat /sys/firmware/devicetree/base/ahb/apb/bus@1e78a000/i2c-bus@180/psu@58/compatible

# Try reading MFR_ID to confirm PMBus communication
i2cget -y 3 0x58 0x99 s   # MFR_ID (block read)
i2cget -y 3 0x58 0x79 w   # STATUS_WORD
```

{: .tip }
If `i2cdetect` shows the address but the pmbus driver does not bind, you may need to manually instantiate the device: `echo pmbus 0x58 > /sys/bus/i2c/devices/i2c-3/new_device`

### No Sensors Appearing on D-Bus

```bash
# Check PSUSensor daemon status
systemctl status xyz.openbmc_project.psusensor
journalctl -u xyz.openbmc_project.psusensor -f

# Check Entity Manager found the PSU configuration
journalctl -u xyz.openbmc_project.EntityManager | grep -i psu

# Verify the hwmon sysfs path exists
ls /sys/bus/i2c/devices/3-0058/hwmon/

# Check if Labels in Entity Manager config match actual hwmon attributes
ls /sys/bus/i2c/devices/3-0058/hwmon/hwmon*/
```

{: .warning }
A common failure is mismatched Labels. If your Entity Manager config lists `"vout1"` but the hwmon driver only creates `in2_input` (without a label file), PSUSensor may not find the sensor. Check the hwmon attribute names and adjust Labels accordingly.

### Incorrect Sensor Readings

```bash
# Compare D-Bus value with raw hwmon value
cat /sys/class/hwmon/hwmon5/in1_input
# 229800 (millivolts = 229.8 V)

busctl get-property xyz.openbmc_project.PSUSensor \
    /xyz/openbmc_project/sensors/voltage/PSU0_Input_Voltage \
    xyz.openbmc_project.Sensor.Value Value
# d 229.8

# If values differ, check for scaling issues in the kernel driver
# or Entity Manager ScaleFactor/Offset properties
```

### PSU Fault Detected

```bash
# Read STATUS_WORD to identify the fault type
i2cget -y 3 0x58 0x79 w

# Decode individual status registers for details
i2cget -y 3 0x58 0x7A b   # STATUS_VOUT
i2cget -y 3 0x58 0x7B b   # STATUS_IOUT
i2cget -y 3 0x58 0x7C b   # STATUS_INPUT
i2cget -y 3 0x58 0x7D b   # STATUS_TEMPERATURE
i2cget -y 3 0x58 0x81 b   # STATUS_FANS_1_2

# Clear faults after resolving the issue
i2cset -y 3 0x58 0x03     # CLEAR_FAULTS command

# Check PSU operational status on D-Bus
busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0 \
    xyz.openbmc_project.State.Decorator.OperationalStatus Functional
```

### Regulators Service Fails to Start

```bash
# Check service status
systemctl status phosphor-regulators
journalctl -u phosphor-regulators --no-pager | tail -30

# Validate JSON configuration syntax
python3 -m json.tool /usr/share/phosphor-regulators/config.json > /dev/null

# Common issues:
# - Invalid I2C bus/address in config (device not present)
# - Missing rule_id reference (typo in rule name)
# - Incorrect PMBus format (linear_11 vs linear_16)
```

### PSU Threshold Alarms Not Triggering

```bash
# Verify thresholds are set on D-Bus
busctl introspect xyz.openbmc_project.PSUSensor \
    /xyz/openbmc_project/sensors/temperature/PSU0_Temperature_1 \
    | grep -i threshold

# Check that sel-logger is running (required for SEL entries)
systemctl status xyz.openbmc_project.sel-logger

# Monitor threshold events in real time
journalctl -u xyz.openbmc_project.sel-logger -f | grep -i threshold
```

---

## References

- [phosphor-power](https://github.com/openbmc/phosphor-power) -- PSU monitoring, regulators, power sequencing
- [dbus-sensors PSUSensor](https://github.com/openbmc/dbus-sensors) -- PSU sensor daemon source
- [entity-manager](https://github.com/openbmc/entity-manager) -- JSON-based hardware configuration
- [PMBus Specification](https://pmbus.org/) -- PMBus protocol standard and command reference
- [Linux Kernel PMBus Documentation](https://www.kernel.org/doc/html/latest/hwmon/pmbus.html) -- Kernel PMBus core driver and sysfs interface
- [phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces) -- D-Bus interface definitions for sensors and inventory
- [Power Management Guide]({% link docs/03-core-services/05-power-management-guide.md %}) -- Related guide covering power sequencing, capping, and restore policy

---

{: .note }
**Tested on**: OpenBMC master, QEMU ast2600-evb (I2C bus enumeration verified; full PMBus telemetry requires physical PSU hardware)
