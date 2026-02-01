---
layout: default
title: D-Bus Sensors Guide
parent: Core Services
nav_order: 1
difficulty: intermediate
prerequisites:
  - dbus-guide
  - entity-manager-guide
---

# D-Bus Sensors Guide
{: .no_toc }

Configure and use dbus-sensors for hardware monitoring.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**dbus-sensors** is a collection of sensor daemons that expose hardware sensor data via D-Bus. Each daemon handles a specific sensor type and integrates with Entity Manager for configuration.

```
┌────────────────────────────────────────────────────────────────┐
│                      dbus-sensors Architecture                 │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │
│  │  ADCSensor     │  │ HwmonTempSensor│  │  PSUSensor     │    │
│  │  (ADC inputs)  │  │  (I2C temps)   │  │  (PMBus PSU)   │    │
│  └───────┬────────┘  └───────┬────────┘  └───────┬────────┘    │
│          │                   │                   │             │
│  ┌───────┴───────────────────┴───────────────────┴───────┐     │
│  │                     D-Bus                             │     │
│  │          xyz.openbmc_project.Sensor.Value             │     │
│  └───────────────────────────┬───────────────────────────┘     │
│                              │                                 │
│  ┌───────────────────────────┴───────────────────────────┐     │
│  │                   Entity Manager                      │     │
│  │              (JSON Configuration)                     │     │
│  └───────────────────────────────────────────────────────┘     │
│                              │                                 │
│  ┌───────────────────────────┴───────────────────────────┐     │
│  │                   Linux Kernel                        │     │
│  │          /sys/class/hwmon, /sys/bus/iio               │     │
│  └───────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────┘
```

---

## Sensor Daemons

| Daemon | Sensor Types | Data Source |
|--------|--------------|-------------|
| `adcsensor` | ADC voltage inputs | IIO subsystem |
| `hwmontempsensor` | I2C temperature sensors | hwmon sysfs |
| `psusensor` | PSU voltage, current, power | PMBus hwmon |
| `fansensor` | Fan tachometers, PWM | hwmon sysfs |
| `intrusionsensor` | Chassis intrusion | GPIO |
| `ipmbsensor` | IPMB sensors | IPMB interface |
| `mcutempsensor` | MCU temperature | I2C |
| `nvmesensor` | NVMe temperature | NVMe-MI |
| `externalsensor` | Virtual sensors | D-Bus input |

---

## Configuration & Setup

### Build-Time Configuration (Yocto)

Enable or disable specific sensor daemons in your machine configuration:

```bitbake
# In your machine .conf or image recipe

# Include all sensor daemons (default)
IMAGE_INSTALL:append = " dbus-sensors"

# Or include specific sensor daemons only
IMAGE_INSTALL:append = " \
    adcsensor \
    hwmontempsensor \
    fansensor \
    psusensor \
"

# Exclude specific daemons
RDEPENDS:${PN}:remove:pn-dbus-sensors = "intrusionsensor ipmbsensor"
```

### Meson Build Options

When building dbus-sensors from source:

```bash
# View all options
meson configure build

# Common options
meson setup build \
    -Dadc=enabled \
    -Dhwmon-temp=enabled \
    -Dfan=enabled \
    -Dpsu=enabled \
    -Dintrusion=disabled \
    -Dipmb=disabled \
    -Dnvme=enabled \
    -Dexternal=enabled
```

| Option | Default | Description |
|--------|---------|-------------|
| `adc` | enabled | ADC voltage sensors |
| `hwmon-temp` | enabled | I2C temperature sensors |
| `fan` | enabled | Fan tachometer sensors |
| `psu` | enabled | PMBus PSU sensors |
| `intrusion` | enabled | Chassis intrusion sensor |
| `ipmb` | enabled | IPMB sensors |
| `nvme` | enabled | NVMe temperature sensors |
| `external` | enabled | External/virtual sensors |
| `mcu-temp` | enabled | MCU temperature sensor |

### Runtime Enable/Disable

Control sensor daemons at runtime via systemd:

```bash
# Disable a sensor daemon
systemctl disable xyz.openbmc_project.adcsensor
systemctl stop xyz.openbmc_project.adcsensor

# Enable a sensor daemon
systemctl enable xyz.openbmc_project.hwmontempsensor
systemctl start xyz.openbmc_project.hwmontempsensor

# Check status
systemctl status xyz.openbmc_project.fansensor

# List all sensor services
systemctl list-units | grep sensor
```

### Sensor Custom Properties

Sensors support additional configuration properties in Entity Manager:

```json
{
    "Exposes": [
        {
            "Name": "CPU Temp",
            "Type": "TMP75",
            "Bus": 1,
            "Address": "0x48",

            "PowerState": "On",
            "ReadState": "On",
            "PollRate": 1.0,
            "Offset": 0.0,
            "ScaleFactor": 1.0,
            "Label": "CPU Core Temperature",
            "MaxValue": 125,
            "MinValue": -40,

            "Thresholds": [...]
        }
    ]
}
```

| Property | Type | Description |
|----------|------|-------------|
| `PowerState` | string | When to poll: `On`, `BiosPost`, `Always` |
| `ReadState` | string | Alternate power state control |
| `PollRate` | float | Polling interval in seconds (default: 1.0) |
| `Offset` | float | Value offset adjustment |
| `ScaleFactor` | float | Multiplier for raw value |
| `Label` | string | Human-readable label |
| `MaxValue` | float | Maximum expected value |
| `MinValue` | float | Minimum expected value |

### Hysteresis Configuration

Configure threshold hysteresis to prevent alarm flapping:

```json
{
    "Thresholds": [
        {
            "Direction": "greater than",
            "Name": "upper critical",
            "Severity": 1,
            "Value": 95,
            "Hysteresis": 2.0
        }
    ]
}
```

The alarm clears when value drops below `Value - Hysteresis` (93°C in this example).

---

## D-Bus Sensor Interface

All sensors implement `xyz.openbmc_project.Sensor.Value`:

```bash
# Introspect a sensor
busctl introspect xyz.openbmc_project.ADCSensor \
    /xyz/openbmc_project/sensors/voltage/P12V

# Properties:
#   Value          - Current sensor reading (double)
#   MaxValue       - Maximum possible value
#   MinValue       - Minimum possible value
#   Unit           - Measurement unit
```

### Threshold Interfaces

Sensors can have warning and critical thresholds:

```
xyz.openbmc_project.Sensor.Threshold.Warning
  - WarningHigh
  - WarningLow
  - WarningAlarmHigh
  - WarningAlarmLow

xyz.openbmc_project.Sensor.Threshold.Critical
  - CriticalHigh
  - CriticalLow
  - CriticalAlarmHigh
  - CriticalAlarmLow
```

---

## ADC Sensors

ADC sensors read analog voltage inputs via the Linux IIO subsystem.

### Device Tree Configuration

```dts
// In your device tree
&adc {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_adc0_default
                 &pinctrl_adc1_default>;
};
```

### Entity Manager Configuration

```json
{
    "Exposes": [
        {
            "Index": 0,
            "Name": "P12V",
            "ScaleFactor": 4.0,
            "Type": "ADC"
        },
        {
            "Index": 1,
            "Name": "P3V3",
            "ScaleFactor": 1.0,
            "Type": "ADC",
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 3.6
                },
                {
                    "Direction": "less than",
                    "Name": "lower critical",
                    "Severity": 1,
                    "Value": 3.0
                }
            ]
        }
    ],
    "Name": "MyBoard",
    "Type": "Board"
}
```

### Key Properties

| Property | Description |
|----------|-------------|
| `Index` | ADC channel number (matches hwmon inX_input) |
| `Name` | Sensor name on D-Bus |
| `ScaleFactor` | Voltage divider ratio |
| `PowerState` | When to read (On, BiosPost, Always) |
| `Thresholds` | Warning/critical levels |

---

## Hwmon Temperature Sensors

For I2C temperature sensors (TMP75, LM75, etc.).

### Entity Manager Configuration

```json
{
    "Exposes": [
        {
            "Address": "0x48",
            "Bus": 1,
            "Name": "CPU Temp",
            "Type": "TMP75"
        },
        {
            "Address": "0x49",
            "Bus": 1,
            "Name": "Inlet Temp",
            "Type": "TMP75",
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 45
                }
            ]
        }
    ],
    "Name": "TempSensors",
    "Probe": "TRUE",
    "Type": "Board"
}
```

### Supported Sensor Types

| Type | Chip | Common Uses |
|------|------|-------------|
| `TMP75` | TI TMP75 | Ambient temperature |
| `TMP421` | TI TMP421 | Remote diode sensing |
| `TMP112` | TI TMP112 | Low power temp |
| `LM75A` | NXP LM75A | General purpose |
| `EMC1413` | Microchip | Multi-channel |

---

## PSU Sensors

For PMBus power supplies.

### Entity Manager Configuration

```json
{
    "Exposes": [
        {
            "Address": "0x58",
            "Bus": 3,
            "Name": "PSU1",
            "Type": "pmbus"
        }
    ],
    "Name": "PowerSupply",
    "Probe": "TRUE",
    "Type": "Board"
}
```

### Exposed Sensors

PSU sensor daemon automatically exposes:

- Input/output voltage
- Input/output current
- Input/output power
- Temperature
- Fan speed
- Status flags

---

## Virtual/External Sensors

For calculated values or sensors from external sources.

### Entity Manager Configuration

```json
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
    "Type": "Board"
}
```

### Setting Values via D-Bus

```bash
# External sensors can be written to
busctl set-property xyz.openbmc_project.ExternalSensor \
    /xyz/openbmc_project/sensors/power/Total_Power \
    xyz.openbmc_project.Sensor.Value Value d 450.5
```

---

## Threshold Configuration

### Threshold Levels

| Severity | Meaning |
|----------|---------|
| 0 | Warning |
| 1 | Critical |

### Direction

| Direction | Meaning |
|-----------|---------|
| `greater than` | Alarm when value > threshold |
| `less than` | Alarm when value < threshold |

### Example with All Thresholds

```json
{
    "Thresholds": [
        {
            "Direction": "greater than",
            "Name": "upper critical",
            "Severity": 1,
            "Value": 90
        },
        {
            "Direction": "greater than",
            "Name": "upper warning",
            "Severity": 0,
            "Value": 80
        },
        {
            "Direction": "less than",
            "Name": "lower warning",
            "Severity": 0,
            "Value": 10
        },
        {
            "Direction": "less than",
            "Name": "lower critical",
            "Severity": 1,
            "Value": 5
        }
    ]
}
```

---

## Reading Sensors

### Via D-Bus

```bash
# List all sensors
busctl tree xyz.openbmc_project.ADCSensor
busctl tree xyz.openbmc_project.HwmonTempSensor

# Read sensor value
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Check threshold status
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Threshold.Critical CriticalAlarmHigh
```

### Via Redfish

```bash
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors

curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors/CPU_Temp
```

---

## Troubleshooting

### Sensor not appearing

```bash
# Check Entity Manager found the device
journalctl -u xyz.openbmc_project.EntityManager | grep -i <sensor-name>

# Check hwmon sysfs exists
ls /sys/class/hwmon/

# Check sensor daemon logs
journalctl -u xyz.openbmc_project.adcsensor -f
journalctl -u xyz.openbmc_project.hwmontempsensor -f
```

### Incorrect readings

```bash
# Verify raw hwmon value
cat /sys/class/hwmon/hwmon*/temp1_input

# Check scale factor in Entity Manager config
# Value on D-Bus = raw_value * ScaleFactor

# For ADC, verify voltage divider calculation
```

### Threshold alarms not triggering

```bash
# Check threshold configuration
busctl introspect xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/<name> | grep -i threshold

# Verify SEL logger is running
systemctl status xyz.openbmc_project.sel-logger
```

---

## Deep Dive
{: .text-delta }

Advanced implementation details for sensor developers.

### Sensor Reading Pipeline

Each sensor daemon follows a common pattern for reading and publishing sensor values:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Sensor Reading Pipeline                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   1. HARDWARE LAYER                                                     │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │  I2C Device → Kernel Driver → sysfs/hwmon                        │  │
│   │  Example: TMP75 at 0x48 → tmp75 driver → /sys/class/hwmon/hwmonN │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                   │                                     │
│                                   ▼                                     │
│   2. SENSOR DAEMON (e.g., hwmontempsensor)                              │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  a. Entity Manager signals new Configuration object             │   │
│   │  b. Daemon matches Type (e.g., "TMP75") to its supported types  │   │
│   │  c. Daemon locates hwmon sysfs path for bus/address             │   │
│   │  d. Creates Sensor object with D-Bus interface                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                     │
│                                   ▼                                     │
│   3. POLLING LOOP                                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  while (running) {                                              │   │
│   │      raw_value = read("/sys/class/hwmon/hwmonN/temp1_input");   │   │
│   │      scaled_value = raw_value / 1000.0 * scaleFactor;           │   │
│   │      if (value_changed) {                                       │   │
│   │          update_dbus_property("Value", scaled_value);           │   │
│   │          check_thresholds(scaled_value);                        │   │
│   │      }                                                          │   │
│   │      sleep(pollInterval);  // typically 1 second                │   │
│   │  }                                                              │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                   │                                     │
│                                   ▼                                     │
│   4. D-BUS PUBLICATION                                                  │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │  Service: xyz.openbmc_project.HwmonTempSensor                   │   │
│   │  Path: /xyz/openbmc_project/sensors/temperature/CPU_Temp        │   │
│   │  Interface: xyz.openbmc_project.Sensor.Value                    │   │
│   │      Property: Value = 45.5 (double)                            │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Source reference**: [HwmonTempSensor.cpp](https://github.com/openbmc/dbus-sensors/blob/master/src/HwmonTempSensor.cpp)

### Threshold Detection Algorithm

Thresholds use hysteresis to prevent rapid alarm toggling:

```
┌────────────────────────────────────────────────────────────────────────┐
│                    Threshold Hysteresis                                │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│   Temperature (°C)                                                     │
│        │                                                               │
│    95 ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ Upper Critical                       │
│        │                                                               │
│    90 ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ Upper Critical Hysteresis (95-5)     │
│        │                                                               │
│    85 ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ Upper Warning                        │
│        │              ╭───╮                                            │
│    80 ─┼─ ─ ─ ─ ─ ─ ─╱─ ─ ╲─ ─ ─ ─ Upper Warning Hysteresis (85-5)     │
│        │            ╱       ╲       (clear alarm below this)           │
│    75 ─┼───────────╱         ╲──────                                   │
│        │          ╱           ╲                                        │
│    70 ─┼─────────╱             ╲                                       │
│        │                                                               │
│        └────────────────────────────────────────────────────▶ Time     │
│                                                                        │
│   Alarm Logic:                                                         │
│   ├── SET alarm when: value >= threshold                               │
│   ├── CLEAR alarm when: value < (threshold - hysteresis)               │
│   └── Default hysteresis: 1.0 (configurable per threshold)             │
│                                                                        │
│   Code pattern (Thresholds.cpp):                                       │
│   if (!alarm && value >= threshold) {                                  │
│       alarm = true;                                                    │
│       log_event("threshold crossed");                                  │
│   } else if (alarm && value < (threshold - hysteresis)) {              │
│       alarm = false;                                                   │
│       log_event("threshold cleared");                                  │
│   }                                                                    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Source reference**: [Thresholds.cpp](https://github.com/openbmc/dbus-sensors/blob/master/src/Thresholds.cpp)

### Entity Manager Integration Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Sensor Discovery Flow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   1. Entity Manager loads JSON configuration                            │
│      ┌─────────────────────────────────────────────────────────────┐    │
│      │ { "Name": "CPU_Temp", "Type": "TMP75", "Bus": 1, ... }      │    │
│      └─────────────────────────────────────────────────────────────┘    │
│                                   │                                     │
│                                   ▼                                     │
│   2. Entity Manager creates D-Bus Configuration object                  │
│      Path: /xyz/openbmc_project/inventory/.../CPU_Temp                  │
│      Interface: xyz.openbmc_project.Configuration.TMP75                 │
│                                   │                                     │
│                                   ▼                                     │
│   3. HwmonTempSensor receives InterfacesAdded signal                    │
│      ┌─────────────────────────────────────────────────────────────┐    │
│      │ match = "type='signal',interface='ObjectManager',"          │    │
│      │         "member='InterfacesAdded'"                          │    │
│      └─────────────────────────────────────────────────────────────┘    │
│                                   │                                     │
│                                   ▼                                     │
│   4. Daemon checks if Type matches its supported types                  │
│      ┌──────────────────────────────────────────────────────────────┐   │
│      │ supportedTypes = {"TMP75", "TMP112", "LM75", "EMC1403", ...} │   │
│      │ if (config.Type in supportedTypes) { createSensor(); }       │   │
│      └──────────────────────────────────────────────────────────────┘   │
│                                   │                                     │
│                                   ▼                                     │
│   5. Daemon locates hwmon sysfs path                                    │
│      ┌─────────────────────────────────────────────────────────────┐    │
│      │ Scan /sys/class/hwmon/hwmon*/device/                        │    │
│      │ Match i2c-{bus}-00{address} to configuration                │    │
│      │ e.g., i2c-1-0048 for Bus=1, Address=0x48                    │    │
│      └─────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### ADC Scaling and Voltage Dividers

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ADC Voltage Calculation                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Hardware Voltage Divider:                                             │
│                                                                         │
│       Vin ──────┬──────                                                 │
│                 │                                                       │
│                ┌┴┐ R1                                                   │
│                │ │ (e.g., 10kΩ)                                         │
│                └┬┘                                                      │
│                 ├──────────▶ ADC Input                                  │
│                ┌┴┐ R2                                                   │
│                │ │ (e.g., 3.3kΩ)                                        │
│                └┬┘                                                      │
│                 │                                                       │
│       GND ──────┴──────                                                 │
│                                                                         │
│   Voltage Divider Formula:                                              │
│   V_adc = V_in × R2 / (R1 + R2)                                         │
│   V_in = V_adc × (R1 + R2) / R2                                         │
│                                                                         │
│   ScaleFactor Calculation:                                              │
│   ScaleFactor = (R1 + R2) / R2                                          │
│   Example: (10k + 3.3k) / 3.3k = 4.03                                   │
│                                                                         │
│   Entity Manager Configuration:                                         │
│   {                                                                     │
│       "Name": "P12V",                                                   │
│       "Type": "ADC",                                                    │
│       "Index": 0,                                                       │
│       "ScaleFactor": 4.03,     ← Voltage divider ratio                  │
│       "PowerState": "On"       ← Only read when host is on              │
│   }                                                                     │
│                                                                         │
│   Raw to Final Conversion:                                              │
│   raw_mv = read("/sys/bus/iio/devices/iio:device0/in_voltage0_raw");    │
│   adc_voltage = raw_mv × reference_voltage / max_raw_value;             │
│   actual_voltage = adc_voltage × ScaleFactor;                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Power State Filtering

Sensors can be configured to only read when the host is in a specific power state:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Power State Filtering                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   PowerState Options:                                                   │
│   ┌─────────────┬────────────────────────────────────────────────────┐  │
│   │ Value       │ Sensor reads when...                               │  │
│   ├─────────────┼────────────────────────────────────────────────────┤  │
│   │ "Always"    │ Always (default, standby power sensors)            │  │
│   │ "On"        │ Host is powered on (CPU/memory sensors)            │  │
│   │ "BiosPost"  │ Host is in BIOS POST (initialization sensors)      │  │
│   │ "Chassis"   │ Chassis power is on (12V rail sensors)             │  │
│   └─────────────┴────────────────────────────────────────────────────┘  │
│                                                                         │
│   Implementation:                                                       │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │ // Subscribe to host state changes                              │   │
│   │ match = "type='signal',path='/xyz/openbmc_project/state/host0'" │   │
│   │                                                                 │   │
│   │ // In polling loop                                              │   │
│   │ if (powerState == "On" && hostState != Running) {               │   │
│   │     value = NaN;  // Mark sensor unavailable                    │   │
│   │     return;                                                     │   │
│   │ }                                                               │   │
│   │ value = read_sensor();                                          │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│   When sensor is unavailable (host off), D-Bus Value = NaN              │
│   This prevents false alarms and stale readings                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Source Code Reference

Key implementation files in [dbus-sensors](https://github.com/openbmc/dbus-sensors):

| File | Description |
|------|-------------|
| `src/HwmonTempSensor.cpp` | I2C temperature sensor implementation |
| `src/ADCSensor.cpp` | ADC voltage sensor implementation |
| `src/Thresholds.cpp` | Threshold detection and hysteresis |
| `src/Utils.cpp` | Hwmon path discovery, scaling |
| `src/SensorPaths.cpp` | D-Bus path construction |
| `include/sensor.hpp` | Base sensor class interface |

---

## Examples

Working examples are available in the [examples/sensors](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/examples/sensors) directory:

- `sensor_reader.cpp` - C++ sensor reading example
- `external-sensor/` - External sensor daemon example
- `virtual-sensor/` - Virtual sensor configuration

---

## References

- [dbus-sensors](https://github.com/openbmc/dbus-sensors)
- [Entity Manager](https://github.com/openbmc/entity-manager)
- [Sensor Architecture](https://github.com/openbmc/docs/blob/master/architecture/sensor-architecture.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
