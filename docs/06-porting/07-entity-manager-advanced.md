---
layout: default
title: Entity Manager Advanced
parent: Porting
nav_order: 7
difficulty: advanced
prerequisites:
  - machine-layer
  - device-tree
---

# Entity Manager Advanced Configuration
{: .no_toc }

Master dynamic hardware configuration with advanced probing, FRU integration, and real-world patterns.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

This guide covers advanced Entity Manager topics for complex hardware configurations. For basic Entity Manager concepts, see the [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %}).

Entity Manager dynamically discovers hardware using JSON configuration files with "probes" that match system conditions. When probes match, Entity Manager exposes D-Bus objects that other services (sensors, fan control) use.

### When to Use This Guide

| Scenario | This Guide Helps |
|----------|------------------|
| Complex probe conditions (regex, multi-field) | ✅ |
| FRU EEPROM integration | ✅ |
| Migrating from static to dynamic config | ✅ |
| Debugging Entity Manager issues | ✅ |
| Basic Entity Manager setup | Use basic guide |

---

## Advanced Probe Patterns

Probes determine when a configuration applies. Advanced patterns allow precise hardware matching.

### Regex Probes

Use regex patterns to match variable hardware identifiers:

```json
{
    "Exposes": [...],
    "Name": "Motherboard Sensors",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': '.*Motherboard.*'})"
}
```

**Regex syntax:**

| Pattern | Matches |
|---------|---------|
| `.*` | Any characters (wildcard) |
| `^ABC` | Starts with "ABC" |
| `XYZ$` | Ends with "XYZ" |
| `V[0-9]+` | "V" followed by digits |
| `(A\|B)` | Either "A" or "B" |

**Example: Match multiple product variants:**

```json
{
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': '^(Server-2U|Server-4U).*'})"
}
```

### Multi-Condition Probes (AND)

Match multiple conditions simultaneously using array syntax:

```json
{
    "Probe": [
        "xyz.openbmc_project.FruDevice({'PRODUCT_MANUFACTURER': 'ACME'})",
        "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'PowerBoard'})"
    ]
}
```

All conditions must match (logical AND). This ensures the configuration only applies when both manufacturer AND product name match.

### OR Condition Probes

For OR logic, use the `OR` keyword:

```json
{
    "Probe": "OR",
    "ProbeValue": [
        "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'BoardTypeA'})",
        "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'BoardTypeB'})"
    ]
}
```

### GPIO-Based Hardware Detection

Detect hardware presence using GPIO pins:

```json
{
    "Probe": "xyz.openbmc_project.Inventory.Decorator.Asset({'Name': 'Riser Card'})",
    "Name": "Riser Card Sensors",
    "Exposes": [
        {
            "Name": "Riser_Temp",
            "Type": "TMP75",
            "Bus": 6,
            "Address": "0x48"
        }
    ]
}
```

For GPIO presence detection, use the GpioPresence daemon which creates inventory objects based on GPIO state:

```json
{
    "Name": "GPU Presence",
    "Type": "GpioPresence",
    "Pin": "GPU_PRSNT_N",
    "ActiveLow": true
}
```

### I2C Address Probes with Wildcards

Match devices across multiple I2C buses:

```json
{
    "Probe": "xyz.openbmc_project.FruDevice({'BUS': '.*', 'ADDRESS': '0x50'})"
}
```

**Specific bus range:**

```json
{
    "Probe": "xyz.openbmc_project.FruDevice({'BUS': '[2-5]', 'ADDRESS': '0x50'})"
}
```

---

## FruDevice Integration

FruDevice daemon scans I2C buses for FRU EEPROMs and exposes their contents via D-Bus.

### FruDevice Role

```
┌──────────────┐    ┌──────────────┐    ┌──────────────────┐
│ FRU EEPROM   │───>│  FruDevice   │───>│  D-Bus Objects   │
│ (I2C 0x50)   │    │   Daemon     │    │  FruDevice/*     │
└──────────────┘    └──────────────┘    └──────────────────┘
                                               │
                                               v
                                        ┌──────────────────┐
                                        │  Entity Manager  │
                                        │  (Probe Match)   │
                                        └──────────────────┘
```

FruDevice scans configured I2C buses at boot and exposes discovered FRU data as D-Bus objects that Entity Manager can probe against.

### FRU EEPROM Structure

Standard IPMI FRU format (IPMI Platform Management FRU Information Storage Definition):

| Area | Common Fields |
|------|---------------|
| **Board Info** | BOARD_MANUFACTURER, BOARD_PRODUCT_NAME, BOARD_SERIAL_NUMBER, BOARD_PART_NUMBER |
| **Product Info** | PRODUCT_MANUFACTURER, PRODUCT_PRODUCT_NAME, PRODUCT_PART_NUMBER, PRODUCT_VERSION, PRODUCT_SERIAL_NUMBER |
| **Chassis Info** | CHASSIS_TYPE, CHASSIS_PART_NUMBER, CHASSIS_SERIAL_NUMBER |

### FruDevice Probe Configuration

Configure FruDevice to scan specific I2C buses in your machine layer:

```json
{
    "Exposes": [
        {
            "Name": "Motherboard FRU",
            "Type": "EEPROM",
            "Bus": 2,
            "Address": "0x50"
        }
    ],
    "Name": "Baseboard FRU Config",
    "Probe": "TRUE"
}
```

### Referencing FRU Fields in Exposes

Use `$` syntax to reference FRU fields dynamically:

```json
{
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'PowerModule'})",
    "Name": "$PRODUCT_SERIAL_NUMBER Power Module",
    "Exposes": [
        {
            "Name": "$BOARD_PRODUCT_NAME Voltage",
            "Type": "ADC",
            "Index": 0,
            "ScaleFactor": 0.001
        }
    ]
}
```

The `$FIELD_NAME` syntax substitutes the actual FRU field value at runtime, enabling unique naming for multiple identical modules.

---

## Inventory Manager vs Entity Manager

Choose the right approach for your platform:

### Comparison Table

| Aspect | Inventory Manager (Static) | Entity Manager (Dynamic) |
|--------|---------------------------|-------------------------|
| **Configuration** | YAML files at build time | JSON files with runtime probes |
| **Hardware Discovery** | None - predefined | FRU EEPROM, GPIO, I2C scan |
| **Hot-plug Support** | No | Yes |
| **Configuration Complexity** | Simple | More complex |
| **Flexibility** | Low | High |
| **Debugging** | Easy - static | Requires understanding probes |
| **Best For** | Fixed hardware, prototypes | Production with variants |

### Decision Criteria

**Use Inventory Manager (Static) when:**
- Hardware configuration is fixed and known at build time
- Rapid prototyping or proof-of-concept
- Simple platforms without FRU EEPROMs
- Legacy platforms being maintained

**Use Entity Manager (Dynamic) when:**
- Multiple hardware variants share one image
- Hot-pluggable components (risers, drives)
- FRU EEPROMs identify components
- Production platforms with SKU variants

### Migration Path: Static to Dynamic

1. **Identify static configurations** in your YAML inventory files
2. **Document hardware variants** and how they differ
3. **Add FRU EEPROMs** to boards (or use existing ones)
4. **Create Entity Manager JSON** with probes matching FRU data
5. **Test each variant** to verify correct probe matching
6. **Remove static YAML** configurations
7. **Update recipes** to install JSON configs instead of YAML

---

## Real-World Configuration Examples

### Temperature Sensor Configuration

Configure hwmon temperature sensors discovered via Entity Manager:

```json
{
    "Exposes": [
        {
            "Address": "0x48",
            "Bus": 6,
            "Name": "CPU0 Temp",
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
            ],
            "Type": "TMP75"
        },
        {
            "Address": "0x49",
            "Bus": 6,
            "Name": "CPU1 Temp",
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
            ],
            "Type": "TMP75"
        }
    ],
    "Name": "CPU Temperature Sensors",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': '.*Motherboard.*'})"
}
```

### Fan PWM/Tach Configuration

Configure fan control with PWM output and tachometer input:

```json
{
    "Exposes": [
        {
            "Connector": {
                "Name": "System Fan 1",
                "Pwm": 0,
                "Tachs": [0]
            },
            "Name": "Fan 1",
            "Type": "AspeedFan"
        },
        {
            "Connector": {
                "Name": "System Fan 2",
                "Pwm": 1,
                "Tachs": [1]
            },
            "Name": "Fan 2",
            "Type": "AspeedFan"
        },
        {
            "Connector": {
                "Name": "System Fan 3",
                "Pwm": 2,
                "Tachs": [2, 3]
            },
            "Name": "Fan 3",
            "Type": "AspeedFan"
        }
    ],
    "Name": "Chassis Fans",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'Chassis'})"
}
```

**Note:** Dual tach configuration (`"Tachs": [2, 3]`) is for fans with redundant tachometer sensors.

### Voltage Regulator Configuration

Configure voltage monitoring via ADC or PMBus:

```json
{
    "Exposes": [
        {
            "Address": "0x40",
            "Bus": 3,
            "Name": "P12V",
            "Type": "ADM1275",
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 13.2
                },
                {
                    "Direction": "less than",
                    "Name": "lower critical",
                    "Severity": 1,
                    "Value": 10.8
                }
            ]
        },
        {
            "Address": "0x41",
            "Bus": 3,
            "Name": "P3V3",
            "Type": "ADM1275",
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
    "Name": "Power Regulators",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'PowerBoard'})"
}
```

---

## Debugging and Troubleshooting

### Entity Manager Journal Logs

View Entity Manager activity:

```bash
# Follow Entity Manager logs
journalctl -f -u xyz.openbmc_project.EntityManager

# View recent Entity Manager activity
journalctl -u xyz.openbmc_project.EntityManager --since "5 minutes ago"

# Check for probe matching
journalctl -u xyz.openbmc_project.EntityManager | grep -i "probe"
```

**Common log patterns:**

| Log Message | Meaning |
|-------------|---------|
| `Probe matched` | Configuration activated |
| `Probe failed` | Conditions not met |
| `Exposing object` | D-Bus object created |
| `Failed to find` | Referenced object missing |

### busctl Commands for Inspection

Inspect Entity Manager exposed objects:

```bash
# List all Entity Manager objects
busctl tree xyz.openbmc_project.EntityManager

# View specific object properties
busctl introspect xyz.openbmc_project.EntityManager \
    /xyz/openbmc_project/inventory/system/board/Motherboard

# Get a specific property
busctl get-property xyz.openbmc_project.EntityManager \
    /xyz/openbmc_project/inventory/system/board/Motherboard \
    xyz.openbmc_project.Inventory.Decorator.Asset Name
```

**Inspect FruDevice objects:**

```bash
# List all discovered FRU devices
busctl tree xyz.openbmc_project.FruDevice

# View FRU data
busctl introspect xyz.openbmc_project.FruDevice \
    /xyz/openbmc_project/FruDevice/Motherboard_Fru
```

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| **Probe never matches** | FRU field name mismatch | Check exact field names with `busctl introspect` on FruDevice |
| **Probe matches wrong device** | Too broad regex | Make regex more specific or add AND conditions |
| **Sensors not appearing** | hwmon driver not loaded | Check `dmesg` for I2C errors, verify device tree |
| **Duplicate objects** | Multiple configs match | Add discriminating probe conditions |
| **Objects disappear after reboot** | FruDevice scan timing | Ensure FruDevice starts before Entity Manager |
| **$FIELD substitution empty** | Field doesn't exist in FRU | Verify FRU contents with `busctl` |

**Debug workflow:**

1. **Verify FRU detection:**
   ```bash
   busctl tree xyz.openbmc_project.FruDevice
   ```

2. **Check FRU field names:**
   ```bash
   busctl introspect xyz.openbmc_project.FruDevice /xyz/openbmc_project/FruDevice/<name>
   ```

3. **Test probe manually:**
   ```bash
   # Check if your probe conditions exist
   busctl call xyz.openbmc_project.ObjectMapper \
       /xyz/openbmc_project/object_mapper \
       xyz.openbmc_project.ObjectMapper GetSubTree \
       sias "/" 0 1 "xyz.openbmc_project.FruDevice"
   ```

4. **Review Entity Manager logs:**
   ```bash
   journalctl -u xyz.openbmc_project.EntityManager -n 100
   ```

---

## Next Steps

- [Machine Layer]({% link docs/06-porting/02-machine-layer.md %}) - Create your platform layer
- [Verification]({% link docs/06-porting/05-verification.md %}) - Test your configuration
- [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %}) - Sensor daemon configuration

---

{: .note }
**Tested on**: OpenBMC master branch with AST2600-EVB
