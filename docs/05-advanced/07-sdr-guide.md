---
layout: default
title: SDR Guide
parent: Advanced Topics
nav_order: 7
difficulty: intermediate
prerequisites:
  - dbus-sensors-guide
  - ipmi-guide
---

# SDR Guide
{: .no_toc }

Configure Sensor Data Records (SDR) for IPMI sensor management.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**Sensor Data Records (SDR)** describe sensors and their properties for IPMI clients. OpenBMC dynamically generates SDR from D-Bus sensor objects.

```
┌─────────────────────────────────────────────────────────────────┐
│                      SDR Architecture                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    IPMI Client                              ││
│  │               (ipmitool sdr list)                           ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                   phosphor-ipmi-host                        ││
│  │                                                             ││
│  │   ┌────────────────────────────────────────────────────┐    ││
│  │   │              SDR Generation                        │    ││
│  │   │     (Dynamic from D-Bus sensor objects)            │    ││
│  │   └────────────────────────────────────────────────────┘    ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                    D-Bus Sensors                            ││
│  │   xyz.openbmc_project.Sensor.Value                          ││
│  │   xyz.openbmc_project.Sensor.Threshold.*                    ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## SDR Record Types

### Type 01h - Full Sensor Record

Complete sensor definition with thresholds and scaling.

| Field | Description |
|-------|-------------|
| Sensor Number | Unique sensor ID |
| Sensor Type | Temperature, Voltage, Fan, etc. |
| Unit Type | Celsius, Volts, RPM, etc. |
| M, B, Exp | Linear conversion factors |
| Thresholds | Upper/Lower critical/non-critical |

### Type 02h - Compact Sensor Record

Abbreviated sensor record for simple sensors.

### Type 11h - FRU Device Locator

Points to FRU data storage.

### Type 12h - Management Controller Locator

Describes management controllers.

---

## Viewing SDR

### ipmitool Commands

```bash
# List all SDR records
ipmitool sdr list

# Get full SDR output
ipmitool sdr list full

# Get SDR by type
ipmitool sdr type Temperature
ipmitool sdr type Voltage
ipmitool sdr type Fan

# Get SDR info
ipmitool sdr info

# Get SDR repository info
ipmitool sdr elist
```

### Example Output

```
CPU_Temp         | 45 degrees C      | ok
Board_Temp       | 32 degrees C      | ok
Fan0             | 5000 RPM          | ok
P12V             | 12.10 Volts       | ok
PSU1_Status      | 0x00              | ok
```

---

## SDR Generation

### Dynamic Generation

OpenBMC generates SDR dynamically from D-Bus:

```cpp
// phosphor-ipmi-host generates SDR from:
// 1. xyz.openbmc_project.Sensor.Value - sensor readings
// 2. xyz.openbmc_project.Sensor.Threshold.* - thresholds
// 3. xyz.openbmc_project.Association.Definitions - relationships
```

### Sensor to SDR Mapping

| D-Bus Property | SDR Field |
|----------------|-----------|
| Value | Current reading |
| Unit | Sensor unit type |
| Scale | M, B, Exp factors |
| MaxValue | Sensor max |
| MinValue | Sensor min |
| CriticalHigh | Upper critical |
| WarningHigh | Upper non-critical |
| CriticalLow | Lower critical |
| WarningLow | Lower non-critical |

---

## Sensor Types

### Common Sensor Types

| Type | Hex | Description |
|------|-----|-------------|
| Temperature | 0x01 | Temperature sensors |
| Voltage | 0x02 | Voltage sensors |
| Current | 0x03 | Current sensors |
| Fan | 0x04 | Fan speed sensors |
| Physical Security | 0x05 | Intrusion sensors |
| Platform Security | 0x06 | Security sensors |
| Processor | 0x07 | CPU sensors |
| Power Supply | 0x08 | PSU sensors |
| Power Unit | 0x09 | Power unit sensors |
| Memory | 0x0C | Memory sensors |
| System Event | 0x12 | System events |
| OEM | 0xC0+ | Vendor-specific |

---

## Configuration

### Entity Manager Sensor Configuration

```json
{
    "Name": "CPU_Temp",
    "Type": "TMP75",
    "Bus": 0,
    "Address": "0x48",
    "Thresholds": [
        {
            "Direction": "greater than",
            "Name": "upper critical",
            "Severity": 1,
            "Value": 95
        },
        {
            "Direction": "greater than",
            "Name": "upper non critical",
            "Severity": 0,
            "Value": 85
        }
    ]
}
```

### IPMI Sensor Configuration

```yaml
# phosphor-ipmi-host sensor configuration
# /usr/share/ipmi-providers/sensor-defs.yaml

0x01:
  sensorType: 0x01
  sensorName: CPU_Temp
  sensorReadingType: 0x01
  entityId: 0x03
  entityInstance: 0x01
```

---

## Threshold Events

### SDR Threshold Support

```
┌─────────────────────────────────────────┐
│              Threshold Events           │
├─────────────────────────────────────────┤
│                                         │
│  Upper Critical  ─────  Deassert/Assert │
│  Upper Non-Crit  ─────  Deassert/Assert │
│  Lower Non-Crit  ─────  Deassert/Assert │
│  Lower Critical  ─────  Deassert/Assert │
│                                         │
└─────────────────────────────────────────┘
```

### Monitor Threshold Events

```bash
# Watch SEL for threshold events
ipmitool sel list

# Example threshold event:
# Sensor CPU_Temp | Upper Critical going high | Asserted
```

---

## Reading Values

### Raw to Display Conversion

```
Display Value = (M × raw + B × 10^Bexp) × 10^Rexp

Where:
  M = Multiplier
  B = Additive offset
  Bexp = B exponent
  Rexp = Result exponent
```

### Example

```
Temperature sensor:
  raw value = 0x2D (45)
  M = 1, B = 0, Bexp = 0, Rexp = 0
  Display = (1 × 45 + 0) × 1 = 45°C
```

---

## Troubleshooting

### SDR Not Showing

```bash
# Check sensor exists in D-Bus
busctl tree xyz.openbmc_project.Sensor

# Check IPMI host daemon
systemctl status phosphor-ipmi-host
journalctl -u phosphor-ipmi-host

# Check sensor has required interfaces
busctl introspect xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp
```

### Wrong Readings

```bash
# Compare D-Bus value with IPMI
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# vs
ipmitool sensor get CPU_Temp

# Check M, B, Exp values match sensor scaling
```

### Missing Thresholds

```bash
# Verify thresholds in D-Bus
busctl introspect xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp | grep Threshold

# Check Entity Manager configuration
cat /usr/share/entity-manager/configurations/*.json | jq '.Exposes[] | select(.Name=="CPU_Temp")'
```

---

## D-Bus to SDR

### Query Sensors via D-Bus

```bash
# List all sensors
busctl tree xyz.openbmc_project.Sensor

# Get sensor reading
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Get thresholds
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Threshold.Critical CriticalHigh
```

---

## References

- [IPMI Specification](https://www.intel.com/content/dam/www/public/us/en/documents/product-briefs/ipmi-second-gen-interface-spec-v2-rev1-1.pdf)
- [phosphor-host-ipmid](https://github.com/openbmc/phosphor-host-ipmid) - D-Bus based IPMI daemon for host commands
- [phosphor-net-ipmid](https://github.com/openbmc/phosphor-net-ipmid) - Network IPMI server

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
