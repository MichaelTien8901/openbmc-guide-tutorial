---
layout: default
title: Power Management Guide
parent: Core Services
nav_order: 5
difficulty: advanced
prerequisites:
  - dbus-guide
  - state-manager-guide
  - dbus-sensors-guide
---

# Power Management Guide
{: .no_toc }

Configure power sequencing, PSU monitoring, and voltage regulators.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC power management includes several components:

- **phosphor-power**: PSU management, power supply monitoring
- **phosphor-regulators**: Voltage regulator configuration
- **Power sequencing**: GPIO-based power control
- **Power capping**: System power limiting

```
┌─────────────────────────────────────────────────────────────────┐
│                   Power Management Architecture                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     phosphor-state-manager                  ││
│  │                (Chassis/Host state control)                 ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│        ┌────────────────────┼────────────────────┐              │
│        ▼                    ▼                    ▼              │
│  ┌───────────┐       ┌───────────┐        ┌───────────┐         │
│  │phosphor-  │       │phosphor-  │        │ Power     │         │
│  │power      │       │regulators │        │ Sequencer │         │
│  │(PSU mgmt) │       │(VRM cfg)  │        │ (GPIO)    │         │
│  └─────┬─────┘       └─────┬─────┘        └─────┬─────┘         │
│        │                   │                    │               │
│        ▼                   ▼                    ▼               │
│  ┌───────────┐       ┌───────────┐        ┌───────────┐         │
│  │  PMBus    │       │  I2C/VID  │        │   GPIO    │         │
│  │  PSUs     │       │Regulators │        │  Control  │         │
│  └───────────┘       └───────────┘        └───────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

Include power management components:

```bitbake
# In your machine .conf or image recipe

# Core power management
IMAGE_INSTALL:append = " phosphor-power"

# Include specific components
IMAGE_INSTALL:append = " \
    phosphor-power-psu-monitor \
    phosphor-power-regulators \
    phosphor-power-sequencer \
    phosphor-power-utils \
"

# Exclude components you don't need
IMAGE_INSTALL:remove = "phosphor-power-regulators"
```

### Meson Build Options

```bash
# phosphor-power build options
meson setup build \
    -Dpsu-monitor=enabled \
    -Dregulators=enabled \
    -Dsequencer=enabled \
    -Dutils=enabled \
    -Dtests=disabled
```

| Option | Default | Description |
|--------|---------|-------------|
| `psu-monitor` | enabled | PSU monitoring daemon |
| `regulators` | enabled | Voltage regulator control |
| `sequencer` | enabled | Power sequencing |
| `utils` | enabled | Command-line utilities |

### Runtime Enable/Disable

```bash
# Check power services status
systemctl status phosphor-psu-monitor
systemctl status phosphor-regulators

# Disable PSU monitoring
systemctl stop phosphor-psu-monitor
systemctl disable phosphor-psu-monitor

# Enable regulators service
systemctl enable phosphor-regulators
systemctl start phosphor-regulators
```

### Configuration Files

```bash
# PSU configuration (Entity Manager)
/usr/share/entity-manager/configurations/psu.json

# Regulators configuration
/usr/share/phosphor-regulators/config.json

# Power sequencer configuration
/usr/share/phosphor-power-sequencer/config.json
```

### Power Restore Policy Configuration

```bash
# Get current policy
busctl get-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_restore_policy \
    xyz.openbmc_project.Control.Power.RestorePolicy PowerRestorePolicy

# Set policy via D-Bus
# Options: AlwaysOn, AlwaysOff, Restore
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_restore_policy \
    xyz.openbmc_project.Control.Power.RestorePolicy PowerRestorePolicy s \
    "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOn"

# Configure via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"PowerRestorePolicy": "AlwaysOn"}' \
    https://localhost/redfish/v1/Systems/system
```

### Power Capping Configuration

```bash
# Enable power capping
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_cap \
    xyz.openbmc_project.Control.Power.Cap PowerCapEnable b true

# Set power cap value (watts)
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_cap \
    xyz.openbmc_project.Control.Power.Cap PowerCap u 500

# Via Redfish
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"PowerControl":[{"PowerLimit":{"LimitInWatts":500,"LimitException":"LogEventOnly"}}]}' \
    https://localhost/redfish/v1/Chassis/chassis/Power
```

### PSU Redundancy Configuration

```bash
# Get redundancy status
busctl get-property xyz.openbmc_project.Power.PSU \
    /xyz/openbmc_project/control/power_supply_redundancy \
    xyz.openbmc_project.Control.PowerSupplyRedundancy PowerSupplyRedundancyEnabled

# Enable redundancy monitoring
busctl set-property xyz.openbmc_project.Power.PSU \
    /xyz/openbmc_project/control/power_supply_redundancy \
    xyz.openbmc_project.Control.PowerSupplyRedundancy PowerSupplyRedundancyEnabled b true
```

### GPIO Configuration for Power Control

Define GPIO pins in your machine's device tree:

```dts
// Example device tree fragment
gpio-keys {
    compatible = "gpio-keys";

    power-button {
        label = "power-button";
        gpios = <&gpio0 ASPEED_GPIO(E, 0) GPIO_ACTIVE_LOW>;
        linux,code = <KEY_POWER>;
    };

    power-ok {
        label = "power-ok";
        gpios = <&gpio0 ASPEED_GPIO(E, 1) GPIO_ACTIVE_HIGH>;
        linux,code = <KEY_BATTERY>;
    };
};
```

Configure in JSON:

```json
{
    "gpio_configs": [
        {
            "name": "POWER_BUTTON",
            "direction": "out",
            "polarity": "active_low",
            "line": 32
        },
        {
            "name": "POWER_OK",
            "direction": "in",
            "polarity": "active_high",
            "line": 33
        }
    ]
}
```

---

## PSU Management (phosphor-power)

### PSU Monitoring

The `psu-monitor` service monitors PMBus power supplies for:

- Input/output voltage and current
- Temperature
- Fan speed
- Fault conditions

### D-Bus Interface

```bash
# List PSU inventory
busctl tree xyz.openbmc_project.Inventory.Manager | grep powersupply

# Get PSU properties
busctl introspect xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0

# Check PSU present
busctl get-property xyz.openbmc_project.Inventory.Manager \
    /xyz/openbmc_project/inventory/system/chassis/powersupply0 \
    xyz.openbmc_project.Inventory.Item Present
```

### Entity Manager PSU Configuration

```json
{
    "Name": "PSU0",
    "Type": "Board",
    "Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': 'PSU-1000W'})",

    "Exposes": [
        {
            "Name": "PSU0",
            "Type": "pmbus",
            "Bus": 3,
            "Address": "0x58",
            "Labels": [
                "vin",
                "vout1",
                "iout1",
                "pin",
                "pout1",
                "temp1",
                "temp2",
                "fan1"
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

### PSU Redundancy

Configure redundancy policy:

```bash
# Get current redundancy mode
busctl get-property xyz.openbmc_project.Power.PSU \
    /xyz/openbmc_project/control/power_supply_redundancy \
    xyz.openbmc_project.Control.PowerSupplyRedundancy PowerSupplyRedundancyEnabled

# Set redundancy mode
busctl set-property xyz.openbmc_project.Power.PSU \
    /xyz/openbmc_project/control/power_supply_redundancy \
    xyz.openbmc_project.Control.PowerSupplyRedundancy PowerSupplyRedundancyEnabled b true
```

---

## Voltage Regulators (phosphor-regulators)

### Overview

phosphor-regulators manages voltage regulators on the system:

- Configuration during power-on
- Voltage level monitoring
- Regulator fault detection

### JSON Configuration

Configuration file: `/usr/share/phosphor-regulators/config.json`

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
                        "bus": 1,
                        "address": "0x40"
                    },
                    "configuration": {
                        "volts": 1.0,
                        "rule_id": "set_voltage_rule"
                    },
                    "rails": [
                        {
                            "id": "vdd_cpu0",
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

### Configuration Sections

#### Rules

Reusable actions:

```json
{
    "rules": [
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
    ]
}
```

#### Devices

Regulator definitions:

```json
{
    "id": "vdd_cpu0",
    "is_regulator": true,
    "fru": "/xyz/openbmc_project/inventory/system/chassis/motherboard/cpu0",
    "i2c_interface": {
        "bus": 1,
        "address": "0x40"
    },
    "presence_detection": {
        "rule_id": "detect_presence_rule"
    },
    "configuration": {
        "volts": 1.0,
        "rule_id": "set_voltage_rule"
    }
}
```

---

## Power Sequencing

### GPIO-Based Sequencing

Power sequencing is typically handled by systemd targets and GPIO control.

#### Device Tree GPIO Configuration

```dts
gpio-keys {
    compatible = "gpio-keys";

    power-good {
        label = "power-good";
        gpios = <&gpio0 ASPEED_GPIO(B, 2) GPIO_ACTIVE_HIGH>;
        linux,code = <KEY_POWER>;
    };
};

leds {
    compatible = "gpio-leds";

    power-button {
        gpios = <&gpio0 ASPEED_GPIO(D, 3) GPIO_ACTIVE_LOW>;
    };
};
```

#### Power Control Service

```ini
# /lib/systemd/system/power-control.service
[Unit]
Description=Power Control
After=xyz.openbmc_project.State.Chassis.service

[Service]
Type=oneshot
ExecStart=/usr/bin/power-control.sh on
RemainAfterExit=yes

[Install]
WantedBy=obmc-host-start@0.target
```

### Power Button Handling

```bash
# Monitor power button
journalctl -u xyz.openbmc_project.Chassis.Buttons -f

# Check button state
busctl introspect xyz.openbmc_project.Chassis.Buttons \
    /xyz/openbmc_project/chassis/buttons/power
```

---

## Power Capping

### Overview

Power capping limits total system power consumption.

### D-Bus Interface

```bash
# Get current power cap
busctl get-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_cap \
    xyz.openbmc_project.Control.Power.Cap PowerCap

# Set power cap (watts)
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_cap \
    xyz.openbmc_project.Control.Power.Cap PowerCap u 500

# Enable power cap
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_cap \
    xyz.openbmc_project.Control.Power.Cap PowerCapEnable b true
```

### Via Redfish

```bash
# Get power limit
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Power

# Set power limit
curl -k -u root:0penBmc -X PATCH \
    -H "Content-Type: application/json" \
    -d '{"PowerControl":[{"PowerLimit":{"LimitInWatts":500}}]}' \
    https://localhost/redfish/v1/Chassis/chassis/Power
```

---

## Power Restore Policy

Configure behavior after AC power loss.

```bash
# Get policy
busctl get-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_restore_policy \
    xyz.openbmc_project.Control.Power.RestorePolicy PowerRestorePolicy

# Set to AlwaysOn
busctl set-property xyz.openbmc_project.Settings \
    /xyz/openbmc_project/control/host0/power_restore_policy \
    xyz.openbmc_project.Control.Power.RestorePolicy PowerRestorePolicy s \
    "xyz.openbmc_project.Control.Power.RestorePolicy.Policy.AlwaysOn"
```

| Policy | Description |
|--------|-------------|
| `AlwaysOn` | Power on after AC restore |
| `AlwaysOff` | Stay off after AC restore |
| `Restore` | Return to previous state |

---

## PSU Event Monitoring

### SEL Events

PSU events are logged to the System Event Log:

```bash
# View PSU-related events
ipmitool sel list | grep -i power

# Via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/EventLog/Entries \
    | jq '.Members[] | select(.Message | contains("Power"))'
```

### Threshold Events

Configure PSU sensor thresholds for alerts:

```json
{
    "Exposes": [
        {
            "Name": "PSU0",
            "Type": "pmbus",
            "Bus": 3,
            "Address": "0x58",
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Label": "temp1",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 100
                },
                {
                    "Direction": "less than",
                    "Label": "vin",
                    "Name": "lower critical",
                    "Severity": 1,
                    "Value": 180
                }
            ]
        }
    ]
}
```

---

## Porting Considerations

### Required Configuration

1. **PSU I2C addresses**: Identify PMBus addresses
2. **GPIO mapping**: Power button, power good signals
3. **Sequencing requirements**: Timing constraints
4. **Redundancy mode**: N+1 or N+N configuration

### Device Tree Example

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

### Machine Layer Integration

```bitbake
# In your machine .conf
PREFERRED_PROVIDER_virtual/phosphor-power = "phosphor-power"

# Include power-related packages
IMAGE_INSTALL:append = " \
    phosphor-power \
    phosphor-regulators \
    "
```

---

## Troubleshooting

### PSU Not Detected

```bash
# Check I2C bus
i2cdetect -y 3

# Verify PMBus communication
i2cget -y 3 0x58 0x99 w  # Read MFR_ID

# Check Entity Manager logs
journalctl -u xyz.openbmc_project.EntityManager | grep -i psu
```

### Power On Failure

```bash
# Check power state
obmcutil state

# Check power good GPIO
gpioget gpiochip0 <power-good-pin>

# Check systemd targets
systemctl list-dependencies obmc-host-start@0.target
```

### PSU Fault

```bash
# Check PSU status
busctl get-property xyz.openbmc_project.PSUSensor \
    /xyz/openbmc_project/sensors/power/PSU0_Input_Power \
    xyz.openbmc_project.Sensor.Value Value

# Read PMBus status
i2cget -y 3 0x58 0x79 w  # STATUS_WORD
```

---

## References

- [phosphor-power](https://github.com/openbmc/phosphor-power)
- [phosphor-regulators](https://github.com/openbmc/phosphor-regulators)
- [PMBus Specification](https://pmbus.org/)
- [x86-power-control](https://github.com/openbmc/x86-power-control) - Power control implementation for x86 servers
- [State Management Design](https://github.com/openbmc/docs/blob/master/designs/state-management-and-external-interfaces.md)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
