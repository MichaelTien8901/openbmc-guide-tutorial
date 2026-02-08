---
layout: default
title: PLDM Platform Monitoring
parent: Advanced Topics
nav_order: 19
difficulty: advanced
prerequisites:
  - mctp-pldm-guide
  - sensor-monitoring-guide
last_modified_date: 2026-02-07
---

# PLDM Platform Monitoring & Control (Type 2)
{: .no_toc }

Use PLDM Type 2 (DSP0248) for sensor monitoring, effecter control, Platform Descriptor Records (PDRs), and event handling on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**PLDM for Platform Monitoring and Control** (DMTF [DSP0248](https://www.dmtf.org/sites/default/files/standards/documents/DSP0248_1.2.1.pdf)) is the most heavily used PLDM type in OpenBMC. It replaces IPMI's SDR/sensor model with a richer, self-describing system based on Platform Descriptor Records (PDRs).

With PLDM Type 2, the BMC can:
- **Discover sensors and effecters** automatically through PDR exchange — no manual SDR configuration
- **Read numeric sensors** (temperature, voltage, current, power, fan speed) from any PLDM-capable device
- **Read state sensors** (presence, operational state, health status) for logical entities
- **Control effecters** to set fan speeds, power states, or trigger device actions
- **Receive asynchronous events** when sensor thresholds are crossed or states change

This is how the BMC monitors GPUs, NICs, NVMe drives, power supplies, Bridge ICs (OpenBIC), and other platform devices that speak PLDM over MCTP.

**Key concepts covered:**
- Platform Descriptor Records (PDRs) — the self-describing sensor/effecter database
- Numeric and state sensors — reading values from PLDM termini
- Effecters — controlling devices through PLDM
- Event handling — asynchronous threshold and state change notifications
- D-Bus and Redfish integration — how PLDM sensors appear to consumers
- `pldmtool platform` commands for debugging

{: .note }
This guide focuses on PLDM Type 2 specifically. For MCTP transport configuration and general PLDM concepts, see the [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}). For BIOS configuration (Type 3), see the [BIOS Firmware Management Guide]({% link docs/05-advanced/16-bios-firmware-management-guide.md %}).

---

## Architecture

### How PLDM Monitoring Works in OpenBMC

```
┌────────────────────────────────────────────────────────────────────┐
│           PLDM Type 2 Monitoring Architecture                      │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐                                │
│  │ bmcweb       │  │ phosphor-    │                                │
│  │ (Redfish)    │  │ virtual-     │   Consumers read               │
│  │ /Thermal     │  │ sensor       │   D-Bus sensor values          │
│  │ /Power       │  │ (fan PID)    │                                │
│  └──────┬───────┘  └──────┬───────┘                                │
│         │                 │                                        │
│  ┌──────┴─────────────────┴───────────────────────────────────┐    │
│  │                     D-Bus                                  │    │
│  │  xyz.openbmc_project.Sensor.Value                          │    │
│  │  xyz.openbmc_project.State.Decorator.OperationalStatus     │    │
│  │  xyz.openbmc_project.Inventory.Item                        │    │
│  └──────────────────────┬─────────────────────────────────────┘    │
│                         │                                          │
│  ┌──────────────────────┴─────────────────────────────────────┐    │
│  │                    pldmd (platform-mc)                     │    │
│  │                                                            │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │    │
│  │  │ PDR Manager  │  │ Sensor       │  │ Event        │      │    │
│  │  │ Fetch & parse│  │ Poller       │  │ Handler      │      │    │
│  │  │ PDRs from    │  │ Periodic     │  │ Async alerts │      │    │
│  │  │ each terminus│  │ GetSensor    │  │ from devices │      │    │
│  │  └──────────────┘  │ Reading      │  └──────────────┘      │    │
│  │                    └──────────────┘                        │    │
│  └────────────────────────┬───────────────────────────────────┘    │
│                           │  PLDM over MCTP                        │
│            ┌──────────────┼──────────────┐                         │
│            │              │              │                         │
│      ┌─────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐                   │
│      │  GPU      │ │  NIC       │ │  BIC       │  PLDM Termini     │
│      │  EID:10   │ │  EID:11    │ │  EID:12    │  (Responders)     │
│      │  Sensors: │ │  Sensors:  │ │  Sensors:  │                   │
│      │  - Temp   │ │  - Temp    │ │  - CPU T   │                   │
│      │  - Power  │ │  - Link    │ │  - DIMM T  │                   │
│      │  - Util%  │ │  - Errors  │ │  - Volt    │                   │
│      └───────────┘ └────────────┘ └────────────┘                   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Discovery and Monitoring Flow

1. **MCTP endpoint discovery** — `mctpd` discovers new MCTP endpoints (EIDs)
2. **PLDM terminus initialization** — `pldmd` queries each endpoint for supported PLDM types
3. **PDR fetch** — `pldmd` retrieves all PDRs from the terminus using `GetPDR` commands
4. **Sensor/effecter creation** — PDRs are parsed; D-Bus sensor and effecter objects are created
5. **Polling loop** — `pldmd` periodically reads sensor values via `GetSensorReading` / `GetStateSensorReadings`
6. **Event handling** — Devices send `PlatformEventMessage` asynchronously when thresholds are crossed

### Key Components

| Component | Role |
|-----------|------|
| **pldmd (platform-mc)** | Core PLDM monitoring engine — fetches PDRs, polls sensors, handles events |
| **libpldm** | C library for encoding/decoding PLDM messages |
| **mctpd** | MCTP transport — delivers PLDM messages to/from devices |
| **pldmtool** | CLI for debugging — manual PDR queries and sensor reads |

---

## Platform Descriptor Records (PDRs)

PDRs are the foundation of PLDM monitoring. Each PLDM terminus (device) maintains a local PDR repository that describes all its sensors, effecters, and entity relationships. The BMC fetches these PDRs to learn what the device can report and control.

### PDR Types

| PDR Type | ID | Description |
|----------|-----|-------------|
| **Terminus Locator** | 1 | Identifies the terminus and its MCTP EID |
| **Numeric Sensor** | 2 | Defines a numeric sensor (temp, voltage, power, etc.) |
| **Numeric Sensor Init** | 3 | Initial values for a numeric sensor |
| **State Sensor** | 4 | Defines a state sensor (presence, health, operational state) |
| **Sensor Auxiliary Names** | 6 | Human-readable sensor names |
| **Effecter Auxiliary Names** | 13 | Human-readable effecter names |
| **Numeric Effecter** | 9 | Defines a numeric effecter (fan speed, voltage set point) |
| **State Effecter** | 11 | Defines a state effecter (power control, LED control) |
| **Entity Association** | 15 | Parent-child relationships between entities |
| **FRU Record Set** | 20 | Links FRU data to entities |
| **Compact Numeric Sensor** | 21 | Space-efficient numeric sensor (PLDM 1.3+) |

### PDR Structure (Common Header)

Every PDR starts with a common header:

```
┌─────────────────────────────────────────────────────────────┐
│                   PDR Common Header                         │
├─────────────────────────────────────────────────────────────┤
│  Record Handle      (4 bytes)  Unique ID in the repo        │
│  PDR Header Version (1 byte)   Always 0x01                  │
│  PDR Type           (1 byte)   See PDR Types table above    │
│  Record Change #    (2 bytes)  Incremented on change        │
│  Data Length        (2 bytes)  Length of type-specific data │
├─────────────────────────────────────────────────────────────┤
│  Type-specific PDR data (variable)                          │
└─────────────────────────────────────────────────────────────┘
```

### Numeric Sensor PDR

A Numeric Sensor PDR fully describes one numeric sensor:

```
┌────────────────────────────────────────────────────────────┐
│              Numeric Sensor PDR (Type 2)                   │
├────────────────────────────────────────────────────────────┤
│  PLDMTerminusHandle    Which terminus owns this sensor     │
│  SensorID              Unique sensor ID within terminus    │
│  EntityType            What entity (CPU, DIMM, fan, etc.)  │
│  EntityInstanceNumber  Which instance of that entity       │
│  SensorInit            Initialization behavior             │
│  SensorAuxNamesPDR     Handle of aux names PDR             │
│  BaseUnit              Units (Celsius, Volts, Watts, RPM)  │
│  UnitModifier          Scale factor (10^modifier)          │
│  RateUnit              Per-second, per-minute, etc.        │
│  SensorDataSize        uint8, sint8, uint16, sint16, uint32│
│  Resolution            Sensor resolution                   │
│  Offset                Value offset                        │
│  RangeFieldSupport     Which thresholds are defined        │
│  WarningHigh           Warning high threshold              │
│  CriticalHigh          Critical high threshold             │
│  FatalHigh             Fatal high threshold                │
│  WarningLow            Warning low threshold               │
│  CriticalLow           Critical low threshold              │
│  FatalLow              Fatal low threshold                 │
└────────────────────────────────────────────────────────────┘
```

### State Sensor PDR

```
┌────────────────────────────────────────────────────────────┐
│              State Sensor PDR (Type 4)                     │
├────────────────────────────────────────────────────────────┤
│  PLDMTerminusHandle    Which terminus owns this sensor     │
│  SensorID              Unique sensor ID within terminus    │
│  EntityType            What entity                         │
│  EntityInstanceNumber  Which instance                      │
│  CompositeCount        Number of state sets                │
│  For each state set:                                       │
│    StateSetID          Which state set (see State Sets)    │
│    PossibleStatesSize  How many possible states            │
│    PossibleStates      Bitmask of valid states             │
└────────────────────────────────────────────────────────────┘
```

### Entity Types (Common)

| Entity Type | ID | Description |
|-------------|-----|-------------|
| Processor | 135 | CPU/SoC |
| Memory Module | 142 | DIMM |
| Fan | 29 | Cooling fan |
| Power Supply | 120 | PSU |
| System Board | 64 | Motherboard |
| Add-in Card | 69 | PCIe card (GPU, NIC) |
| Drive Bay | 137 | Storage bay |
| Connector | 82 | Physical connector |
| Chassis | 45 | Physical enclosure |

### State Sets (Common)

| State Set | ID | Possible States |
|-----------|-----|----------------|
| Health State | 2 | Normal, Non-Critical, Critical, Fatal, Unknown |
| Operational State | 5 | Enabled, Disabled, Unavailable, Shutting Down, In Test |
| Presence | 11 | Present, Not Present |
| Link State | 18 | Up, Down, Error, Unknown |
| Boot Progress | 196 | PCI Init, OS Boot, Base Board Init, ... |

### Querying PDRs with pldmtool

```bash
# Get PDR repository info (total PDR count, repo size)
pldmtool platform GetPDRRepositoryInfo

# Example output:
# {
#     "repositoryState": "available",
#     "recordCount": 42,
#     "repositorySize": 8192,
#     "largestRecordSize": 256
# }

# Fetch all PDRs sequentially (start from record handle 0)
pldmtool platform GetPDR -d 0    # First PDR
pldmtool platform GetPDR -d 1    # Second PDR
# ... continue until nextRecordHandle = 0

# Get a specific PDR by record handle
pldmtool platform GetPDR -d 17

# Example Numeric Sensor PDR output:
# {
#     "PDRType": "Numeric Sensor PDR",
#     "PLDMTerminusHandle": 1,
#     "sensorID": 5,
#     "entityType": "Processor",
#     "entityInstanceNumber": 0,
#     "baseUnit": "degreesCelsius",
#     "sensorDataSize": "sint16",
#     "warningHigh": 85.0,
#     "criticalHigh": 95.0,
#     "fatalHigh": 105.0
# }

# Example State Sensor PDR output:
# {
#     "PDRType": "State Sensor PDR",
#     "sensorID": 25,
#     "entityType": "Fan",
#     "entityInstanceNumber": 0,
#     "stateSetID": "Operational State",
#     "possibleStates": ["Enabled", "Disabled", "Unavailable"]
# }
```

---

## Sensors

### Numeric Sensors

Numeric sensors report continuous values like temperature, voltage, current, power, and fan speed.

#### Reading Numeric Sensors

```bash
# Read a numeric sensor value
pldmtool platform GetSensorReading -i <sensorID> -m <mctpEID>

# Example: Read GPU temperature (sensor ID 5, MCTP EID 10)
pldmtool platform GetSensorReading -i 5 -m 10

# Example output:
# {
#     "sensorDataSize": "sint16",
#     "sensorOperationalState": "enabled",
#     "sensorEventMessageEnable": "eventsEnabled",
#     "presentState": "normal",
#     "previousState": "normal",
#     "presentReading": 72
# }
```

#### Sensor States

Each numeric sensor reading includes the current threshold state:

| State | Meaning |
|-------|---------|
| `unknown` | Sensor not yet read |
| `normal` | Within normal range |
| `warningLow` / `warningHigh` | Exceeded warning threshold |
| `criticalLow` / `criticalHigh` | Exceeded critical threshold |
| `fatalLow` / `fatalHigh` | Exceeded fatal threshold |
| `upperNonRecoverable` / `lowerNonRecoverable` | Non-recoverable condition |

#### How Numeric Sensors Map to D-Bus

When `pldmd` discovers a numeric sensor via PDR, it creates a D-Bus object:

```
D-Bus Object Path:
  /xyz/openbmc_project/sensors/<type>/<terminus>_<name>

Interfaces:
  xyz.openbmc_project.Sensor.Value
    - Value (double): current reading
    - Unit (string): "xyz.openbmc_project.Sensor.Value.Unit.DegreesC"
    - MaxValue / MinValue (double): sensor range

  xyz.openbmc_project.Sensor.Threshold.Warning
    - WarningHigh (double)
    - WarningLow (double)
    - WarningAlarmHigh (bool): currently in alarm?

  xyz.openbmc_project.Sensor.Threshold.Critical
    - CriticalHigh (double)
    - CriticalLow (double)
    - CriticalAlarmHigh (bool)
```

```bash
# Read a PLDM sensor via D-Bus (after pldmd creates it)
busctl get-property xyz.openbmc_project.PLDM \
    /xyz/openbmc_project/sensors/temperature/GPU_0_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Read via Redfish
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/Chassis/chassis/Thermal
```

### State Sensors

State sensors report discrete states rather than continuous values — for example, device presence, operational state, or health status.

#### Reading State Sensors

```bash
# Read a state sensor
pldmtool platform GetStateSensorReadings -i <sensorID> -m <mctpEID>

# Example: Read fan presence (sensor ID 25, MCTP EID 10)
pldmtool platform GetStateSensorReadings -i 25 -m 10

# Example output:
# {
#     "compositeSensorCount": 1,
#     "sensorOpState": ["enabled"],
#     "presentState": ["present"],
#     "previousState": ["present"],
#     "eventState": ["present"]
# }
```

### Sensor Base Units

| Unit | ID | Examples |
|------|-----|---------|
| Degrees Celsius | 2 | CPU temp, DIMM temp, board temp |
| Volts | 5 | 12V rail, 3.3V, VCore |
| Amps | 6 | PSU current, CPU current |
| Watts | 7 | System power, CPU power, GPU power |
| RPM | 18 | Fan speed |
| Percentage | 21 | Utilization, health percentage |
| Counts | 1 | Error counters, correctable ECC errors |

---

## Effecters

Effecters are the control counterpart to sensors. While sensors read values, effecters write values to devices — setting fan speeds, controlling power states, or triggering LED patterns.

### Numeric Effecters

```bash
# Set a numeric effecter value (e.g., fan speed setpoint)
pldmtool platform SetNumericEffecterValue -i <effecterID> -m <mctpEID> -d <value>

# Example: Set fan 0 to 5000 RPM
pldmtool platform SetNumericEffecterValue -i 10 -m 12 -d 5000

# Read current effecter value
pldmtool platform GetNumericEffecterValue -i <effecterID> -m <mctpEID>
```

### State Effecters

```bash
# Set a state effecter (e.g., power control)
pldmtool platform SetStateEffecterStates -i <effecterID> -m <mctpEID> -c 1 -d <stateValue>

# Example: Set host power state to "power on" (effecter ID 1, state 1)
pldmtool platform SetStateEffecterStates -i 1 -m 12 -c 1 -d 1

# Get current state effecter value
pldmtool platform GetStateEffecterStates -i <effecterID> -m <mctpEID>
```

### Effecter PDR to D-Bus Mapping

Numeric effecters map to D-Bus control interfaces, and state effecters typically map to operational state controls. The `pldmd` platform-mc module creates the appropriate D-Bus objects when effecter PDRs are discovered.

---

## Event Handling

PLDM devices can send asynchronous event notifications to the BMC using the `PlatformEventMessage` command (0x0A). This is more efficient than polling — devices only send messages when something interesting happens.

### Event Types

| Event Type | Class | Description |
|------------|-------|-------------|
| `sensorEvent` | 0x00 | Numeric or state sensor crossed a threshold or changed state |
| `effecterEvent` | 0x01 | Effecter state changed |
| `redfishTaskExecutedEvent` | 0x02 | A Redfish task completed on the device |
| `redfishMessageEvent` | 0x03 | A Redfish-format event from the device |
| `pldmPDRRepositoryChgEvent` | 0x04 | Device's PDR repo changed (sensors added/removed) |
| `pldmMessagePollEvent` | 0x05 | Device has queued events to be polled |
| `heartbeatTimerElapsed` | 0x06 | Heartbeat timer expired |
| `oemEvent` | 0xFF | Vendor-specific event |

### Sensor Event Flow

```
Device (PLDM Terminus)                     BMC (pldmd)
      │                                        │
      │  Sensor exceeds critical threshold     │
      │                                        │
      │  PlatformEventMessage                  │
      │  ─────────────────────────────────────▶│
      │  formatVersion: 0x01                   │
      │  TID: 1                                │
      │  eventClass: sensorEvent (0x00)        │
      │  sensorID: 5                           │
      │  sensorEventClass: numericThreshold    │
      │  eventState: criticalHigh              │
      │  previousState: normal                 │
      │  sensorDataPresent: true               │
      │  presentReading: 96                    │
      │                                        │
      │  PlatformEventMessage ACK              │
      │◀────────────────────────────────────── │
      │                                        │
      │                          pldmd updates D-Bus:
      │                          CriticalAlarmHigh = true
      │                          Value = 96
      │                          → bmcweb sends Redfish event
      │                          → phosphor-logging creates SEL
```

### PDR Repository Change Event

When a device's sensor configuration changes at runtime (hotplug, firmware update), it sends a `pldmPDRRepositoryChgEvent`. The BMC then re-fetches the PDR repository to discover new or removed sensors.

```bash
# Monitor PLDM events in real-time
journalctl -u pldmd -f | grep -i event

# Check D-Bus for sensor alarm states
busctl get-property xyz.openbmc_project.PLDM \
    /xyz/openbmc_project/sensors/temperature/GPU_0_Temp \
    xyz.openbmc_project.Sensor.Threshold.Critical \
    CriticalAlarmHigh
```

---

## D-Bus and Redfish Integration

### Sensor D-Bus Object Tree

`pldmd` creates sensor objects under the standard OpenBMC sensor hierarchy:

```bash
# PLDM sensor D-Bus tree
busctl tree xyz.openbmc_project.PLDM

# /xyz/openbmc_project
# ├── sensors
# │   ├── temperature
# │   │   ├── PLDM_Device_0_CPU_Temp
# │   │   ├── PLDM_Device_0_DIMM0_Temp
# │   │   └── PLDM_Device_1_Board_Temp
# │   ├── voltage
# │   │   ├── PLDM_Device_0_P12V
# │   │   └── PLDM_Device_0_VCore
# │   ├── power
# │   │   └── PLDM_Device_0_Total_Power
# │   └── fan_tach
# │       ├── PLDM_Device_0_Fan0
# │       └── PLDM_Device_0_Fan1
# ├── state
# │   └── PLDM_Device_0_Operational
# └── inventory
#     └── PLDM_Device_0
```

### Redfish Mapping

PLDM sensors appear in standard Redfish resources:

| PLDM Sensor Type | Redfish Resource |
|------------------|-----------------|
| Temperature | `/redfish/v1/Chassis/{id}/Thermal` → `Temperatures[]` |
| Voltage | `/redfish/v1/Chassis/{id}/Power` → `Voltages[]` |
| Power | `/redfish/v1/Chassis/{id}/Power` → `PowerControl[]` |
| Fan speed | `/redfish/v1/Chassis/{id}/Thermal` → `Fans[]` |
| State sensors | `/redfish/v1/Chassis/{id}` → `Status.Health` |

```bash
# Query all thermal sensors (includes PLDM-sourced sensors)
curl -k -u root:0penBmc \
    https://${BMC_IP}/redfish/v1/Chassis/chassis/Thermal

# Example response showing a PLDM GPU temperature sensor:
# {
#     "Temperatures": [
#         {
#             "Name": "GPU_0_Temp",
#             "ReadingCelsius": 72,
#             "UpperThresholdNonCritical": 85,
#             "UpperThresholdCritical": 95,
#             "UpperThresholdFatal": 105,
#             "Status": {"State": "Enabled", "Health": "OK"}
#         }
#     ]
# }
```

---

## Configuration

### pldmd Platform Monitoring Options

```bash
# pldmd is started with platform-mc enabled by default
# Key meson build options:
# -Dplatform-mc=enabled      Enable platform monitoring & control
# -Dsensor-polling-time=1    Sensor polling interval in seconds
```

### Sensor Polling Interval

The default polling interval determines how frequently `pldmd` reads sensor values from each terminus. Shorter intervals give more responsive monitoring but increase I2C/MCTP bus traffic.

| Use Case | Recommended Interval | Notes |
|----------|---------------------|-------|
| Thermal monitoring | 1-2 seconds | Fast response for fan PID control |
| Power monitoring | 2-5 seconds | Adequate for power capping |
| Inventory/presence | 10-30 seconds | Rarely changes |
| Non-critical sensors | 5-10 seconds | Reduce bus load |

### Entity Manager Integration

For platforms that use `entity-manager` for configuration, PLDM sensors can be associated with physical entities through entity-manager JSON configs:

```json
{
    "Exposes": [
        {
            "Name": "GPU_0_Temp",
            "Type": "PLDMNumericSensor",
            "TerminusID": 1,
            "SensorID": 5,
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 95
                }
            ]
        }
    ]
}
```

---

## Troubleshooting

### Issue: No PLDM Sensors Appearing on D-Bus

**Symptom**: `busctl tree xyz.openbmc_project.PLDM` shows no sensor objects.

**Cause**: PDR fetch failed, terminus not discovered, or platform-mc disabled.

**Solution**:
```bash
# Check if MCTP endpoints are discovered
busctl tree xyz.openbmc_project.MCTP

# Check pldmd status and logs
systemctl status pldmd
journalctl -u pldmd -f | grep -i "pdr\|sensor\|terminus"

# Manually query terminus for PLDM types
pldmtool base GetPLDMTypes -m <eid>

# Manually fetch PDRs to verify device responds
pldmtool platform GetPDRRepositoryInfo -m <eid>
pldmtool platform GetPDR -d 0 -m <eid>
```

### Issue: Sensor Reads Return "unavailable"

**Symptom**: Sensor values show as NaN or unavailable on D-Bus/Redfish.

**Cause**: The device returned `sensorOperationalState = unavailable` or MCTP communication timed out.

**Solution**:
```bash
# Read the sensor directly to check operational state
pldmtool platform GetSensorReading -i <sensorID> -m <eid>

# Check MCTP connectivity
mctp endpoint

# Check for I2C errors if using I2C/SMBus transport
dmesg | grep -i "i2c\|mctp"

# Check if terminus is still responding
pldmtool base GetTID -m <eid>
```

### Issue: Missing Thresholds in Redfish

**Symptom**: Redfish thermal sensors show readings but no threshold values.

**Cause**: The device's Numeric Sensor PDR does not populate threshold fields, or `RangeFieldSupport` bitmap is 0.

**Solution**:
```bash
# Check the PDR for threshold support
pldmtool platform GetPDR -d <sensorPDRHandle> -m <eid>
# Look for "rangeFieldSupport" and threshold values in the output

# If the device doesn't provide thresholds, you can set them
# via entity-manager configuration on the BMC side
```

### Issue: Event Messages Not Received

**Symptom**: Sensor alarms don't trigger even when values exceed thresholds.

**Cause**: The device may not support async events, or event messaging is disabled.

**Solution**:
```bash
# Check device capabilities for event support
pldmtool platform GetPDR -d <sensorPDRHandle>
# Look for "sensorEventMessageEnable"

# Check if pldmd is receiving events
journalctl -u pldmd -f | grep -i "event\|platform_event"

# Verify the device supports PlatformEventMessage
pldmtool base GetPLDMCommands -t 2 -m <eid>
```

### Debug Commands Summary

```bash
# Full PLDM platform debugging workflow
pldmtool base GetPLDMTypes -m <eid>           # What PLDM types?
pldmtool base GetPLDMCommands -t 2 -m <eid>   # What Type 2 commands?
pldmtool platform GetPDRRepositoryInfo -m <eid> # How many PDRs?
pldmtool platform GetPDR -d 0 -m <eid>         # Fetch first PDR
pldmtool platform GetSensorReading -i 1 -m <eid> # Read sensor 1
pldmtool platform GetStateSensorReadings -i 2 -m <eid> # Read state sensor

# Monitor sensor changes via D-Bus
busctl monitor xyz.openbmc_project.PLDM

# View all PLDM sensor values
busctl tree xyz.openbmc_project.PLDM | grep sensors
```

---

## References

### DMTF Specifications
- [DSP0248 — PLDM for Platform Monitoring and Control](https://www.dmtf.org/sites/default/files/standards/documents/DSP0248_1.2.1.pdf) — The core specification
- [DSP0245 — PLDM IDs and Codes](https://www.dmtf.org/sites/default/files/standards/documents/DSP0245_1.4.0.pdf) — Entity types, state sets, sensor units
- [DSP0240 — PLDM Base Specification](https://www.dmtf.org/dsp/DSP0240) — Message format, terminus discovery

### OpenBMC Repositories
- [openbmc/pldm](https://github.com/openbmc/pldm) — PLDM daemon (includes platform-mc module)
- [openbmc/libpldm](https://github.com/openbmc/libpldm) — PLDM message encode/decode library
- [openbmc/phosphor-dbus-interfaces](https://github.com/openbmc/phosphor-dbus-interfaces) — D-Bus sensor interfaces

### Related Guides
- [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) — MCTP transport and general PLDM overview
- [PLDM Firmware Update Guide]({% link docs/05-advanced/20-pldm-firmware-update-guide.md %}) — PLDM Type 5 firmware update
- [SDR Guide]({% link docs/05-advanced/07-sdr-guide.md %}) — IPMI SDR-based sensors (legacy alternative)

---

{: .note }
**Tested on**: OpenBMC master branch. PLDM monitoring requires real hardware with PLDM-capable devices or the PLDM emulator (`spdm-emu`). QEMU does not emulate PLDM termini, but you can test D-Bus integration by manually populating sensor objects.
