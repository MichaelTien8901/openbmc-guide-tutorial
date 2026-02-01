---
layout: default
title: Hwmon Sensors Guide
parent: Core Services
nav_order: 2
difficulty: intermediate
prerequisites:
  - dbus-guide
  - dbus-sensors-guide
---

# Hwmon Sensors Guide
{: .no_toc }

Understanding Linux hwmon subsystem and phosphor-hwmon integration.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The Linux **hwmon** (Hardware Monitoring) subsystem provides a standardized interface for hardware monitoring devices. OpenBMC uses hwmon through two approaches:

1. **phosphor-hwmon** - Legacy daemon that reads hwmon sysfs and exposes D-Bus sensors
2. **dbus-sensors** - Modern approach with specialized sensor daemons

```
┌─────────────────────────────────────────────────────────────────┐
│                     Hwmon Architecture                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                      D-Bus Consumers                        ││
│  │              (bmcweb, ipmid, fan-control)                   ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                         D-Bus                               ││
│  │           xyz.openbmc_project.Sensor.Value                  ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│        ┌────────────────────┼────────────────────┐              │
│        │                    │                    │              │
│  ┌─────┴─────┐       ┌──────┴─────┐      ┌──────┴─────┐         │
│  │phosphor-  │       │ dbus-      │      │ dbus-      │         │
│  │hwmon      │       │ sensors    │      │ sensors    │         │
│  │(legacy)   │       │ hwmontemp  │      │ fansensor  │         │
│  └─────┬─────┘       └──────┬─────┘      └──────┬─────┘         │
│        │                    │                    │              │
│        └────────────────────┼────────────────────┘              │
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                    Linux hwmon sysfs                        ││
│  │                  /sys/class/hwmon/hwmonN/                   ││
│  └──────────────────────────┬──────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                    Kernel Drivers                           ││
│  │            (lm75, tmp75, pmbus, aspeed-adc, ...)            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

Choose between phosphor-hwmon (legacy) or dbus-sensors (modern):

```bitbake
# Modern approach: dbus-sensors (recommended for new platforms)
IMAGE_INSTALL:append = " dbus-sensors"

# Legacy approach: phosphor-hwmon
IMAGE_INSTALL:append = " phosphor-hwmon"

# Include specific dbus-sensors daemons
IMAGE_INSTALL:append = " \
    hwmontempsensor \
    fansensor \
    psusensor \
"
```

### Meson Build Options (dbus-sensors)

```bash
meson setup build \
    -Dhwmon-temp=enabled \
    -Dfan=enabled \
    -Dpsu=enabled
```

### Meson Build Options (phosphor-hwmon)

```bash
meson setup build \
    -Dupdate-functional-on-fail=enabled
```

### Runtime Enable/Disable

```bash
# For dbus-sensors hwmontempsensor
systemctl status xyz.openbmc_project.hwmontempsensor
systemctl stop xyz.openbmc_project.hwmontempsensor
systemctl disable xyz.openbmc_project.hwmontempsensor

# For phosphor-hwmon
systemctl status xyz.openbmc_project.Hwmon@<device>.service
systemctl stop "xyz.openbmc_project.Hwmon@ahb--apb--bus@1e78a000--i2c-bus@80--tmp75@48.service"
```

### Phosphor-Hwmon Configuration

Configuration files are in `/etc/default/obmc/hwmon/`:

```bash
# Create configuration file
# Filename format: device-path-with-dashes.conf
cat > /etc/default/obmc/hwmon/ahb--apb--bus@1e78a000--i2c-bus@80--tmp75@48.conf << 'EOF'
# Sensor label (required)
LABEL_temp1=ambient_temp

# Thresholds (in raw units, typically millidegrees)
WARNHI_temp1=40000
WARNLO_temp1=5000
CRITHI_temp1=45000
CRITLO_temp1=0

# Scaling
GAIN_temp1=1.0
OFFSET_temp1=0

# Remove sensor when not present
REMOVERCS_temp1=1
EOF

# Restart service
systemctl restart xyz.openbmc_project.Hwmon@ahb--apb--bus@1e78a000--i2c-bus@80--tmp75@48.service
```

### Phosphor-Hwmon Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `LABEL_<attr>` | D-Bus sensor name | `LABEL_temp1=cpu_temp` |
| `WARNHI_<attr>` | Warning high (raw) | `WARNHI_temp1=85000` |
| `WARNLO_<attr>` | Warning low (raw) | `WARNLO_temp1=0` |
| `CRITHI_<attr>` | Critical high (raw) | `CRITHI_temp1=95000` |
| `CRITLO_<attr>` | Critical low (raw) | `CRITLO_temp1=-5000` |
| `GAIN_<attr>` | Multiplier | `GAIN_in1=1.5` |
| `OFFSET_<attr>` | Offset to add | `OFFSET_temp1=1000` |
| `REMOVERCS_<attr>` | Remove when absent | `REMOVERCS_temp1=1` |
| `MODE_<attr>` | Read mode | `MODE_temp1=label` |

### Entity Manager Configuration (dbus-sensors)

Configure via JSON in `/usr/share/entity-manager/configurations/`:

```json
{
    "Exposes": [
        {
            "Name": "CPU Temp",
            "Type": "TMP75",
            "Bus": 1,
            "Address": "0x48",
            "PowerState": "On",
            "PollRate": 1.0,
            "Thresholds": [
                {"Direction": "greater than", "Name": "upper critical", "Severity": 1, "Value": 95},
                {"Direction": "greater than", "Name": "upper warning", "Severity": 0, "Value": 85}
            ]
        }
    ],
    "Name": "TempBoard",
    "Probe": "TRUE",
    "Type": "Board"
}
```

### Entity Manager Sensor Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Name` | string | required | Sensor name on D-Bus |
| `Type` | string | required | Sensor type (TMP75, LM75A, etc.) |
| `Bus` | int | required | I2C bus number |
| `Address` | string | required | I2C address (hex) |
| `PowerState` | string | `Always` | `On`, `BiosPost`, `Always` |
| `PollRate` | float | 1.0 | Seconds between readings |
| `Offset` | float | 0.0 | Value offset |
| `ScaleFactor` | float | 1.0 | Value multiplier |
| `MaxValue` | float | - | Maximum expected value |
| `MinValue` | float | - | Minimum expected value |
| `Hysteresis` | float | - | Threshold hysteresis |

### Kernel Driver Configuration

Load I2C sensor drivers:

```bash
# Check if driver is loaded
lsmod | grep tmp75

# Manually instantiate device
echo tmp75 0x48 > /sys/bus/i2c/devices/i2c-1/new_device

# Verify hwmon created
ls /sys/bus/i2c/devices/1-0048/hwmon/

# Remove device
echo 0x48 > /sys/bus/i2c/devices/i2c-1/delete_device
```

Device tree configuration:

```dts
&i2c1 {
    status = "okay";

    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
    };
};
```

---

## Linux Hwmon Basics

### Sysfs Structure

Hwmon devices appear under `/sys/class/hwmon/`:

```bash
# List hwmon devices
ls /sys/class/hwmon/
# hwmon0  hwmon1  hwmon2  ...

# Check device name
cat /sys/class/hwmon/hwmon0/name
# tmp75

# List available sensors
ls /sys/class/hwmon/hwmon0/
# name  temp1_input  temp1_max  temp1_max_hyst  ...
```

### Sensor Types and Naming

| Prefix | Type | Unit | Scale |
|--------|------|------|-------|
| `temp` | Temperature | millidegrees C | /1000 |
| `in` | Voltage | millivolts | /1000 |
| `curr` | Current | milliamps | /1000 |
| `power` | Power | microwatts | /1000000 |
| `fan` | Fan speed | RPM | 1 |
| `pwm` | PWM duty | 0-255 | /255 |

### Common Attributes

```bash
# Temperature sensor attributes
temp1_input       # Current reading (millidegrees)
temp1_max         # Maximum threshold
temp1_max_hyst    # Hysteresis for max
temp1_min         # Minimum threshold
temp1_crit        # Critical threshold
temp1_label       # Sensor label

# Voltage sensor attributes
in1_input         # Current reading (millivolts)
in1_max           # Maximum threshold
in1_min           # Minimum threshold
in1_label         # Sensor label

# Fan sensor attributes
fan1_input        # Current RPM
fan1_min          # Minimum RPM threshold
fan1_target       # Target RPM (for control)
pwm1              # PWM output (0-255)
pwm1_enable       # Control mode (0=off, 1=manual, 2=auto)
```

---

## Phosphor-Hwmon

### Overview

**phosphor-hwmon** is the legacy sensor daemon that:

- Reads hwmon sysfs periodically
- Exposes sensors on D-Bus
- Configured via YAML files
- Being replaced by dbus-sensors for new platforms

### Configuration

Configuration files in `/etc/default/obmc/hwmon/`:

```yaml
# /etc/default/obmc/hwmon/ahb--apb--bus@1e78a000--i2c-bus@80--tmp75@48.conf
LABEL_temp1=ambient_temp
WARNHI_temp1=40000
WARNLO_temp1=5000
CRITHI_temp1=45000
CRITLO_temp1=0
```

### Configuration Options

| Option | Description |
|--------|-------------|
| `LABEL_<attr>` | D-Bus sensor name |
| `WARNHI_<attr>` | Warning high threshold (raw units) |
| `WARNLO_<attr>` | Warning low threshold |
| `CRITHI_<attr>` | Critical high threshold |
| `CRITLO_<attr>` | Critical low threshold |
| `GAIN_<attr>` | Multiplier for reading |
| `OFFSET_<attr>` | Offset to add to reading |
| `REMOVERCS_<attr>` | Remove sensor when not present |

### File Naming

Config file names match the device tree path with special characters replaced:

```
Device tree path: /ahb/apb/bus@1e78a000/i2c-bus@80/tmp75@48
Config file:      ahb--apb--bus@1e78a000--i2c-bus@80--tmp75@48.conf
```

### Example Configuration

```yaml
# Temperature sensor with thresholds
LABEL_temp1=cpu_temp
WARNHI_temp1=85000
CRITHI_temp1=95000
WARNLO_temp1=0
CRITLO_temp1=-5000

# Voltage sensor with scaling
LABEL_in1=p12v_aux
GAIN_in1=1.5
WARNHI_in1=13200
WARNLO_in1=10800
CRITHI_in1=13800
CRITLO_in1=10200
```

### systemd Service

```ini
# /lib/systemd/system/xyz.openbmc_project.Hwmon@.service
[Unit]
Description=Hwmon %I

[Service]
ExecStart=/usr/bin/phosphor-hwmon-readd \
    --path=/sys/class/hwmon/%i \
    --instance=%i
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

---

## Dbus-Sensors Hwmon

### HwmonTempSensor

The modern approach using dbus-sensors with Entity Manager.

**Service:** `xyz.openbmc_project.HwmonTempSensor`

### Entity Manager Configuration

```json
{
    "Exposes": [
        {
            "Address": "0x48",
            "Bus": 1,
            "Name": "Ambient Temp",
            "Type": "TMP75",
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 45
                },
                {
                    "Direction": "greater than",
                    "Name": "upper warning",
                    "Severity": 0,
                    "Value": 40
                }
            ]
        }
    ],
    "Name": "TempBoard",
    "Probe": "TRUE",
    "Type": "Board"
}
```

### Supported Sensor Types

| Type | Kernel Driver | Description |
|------|---------------|-------------|
| `TMP75` | tmp75 | TI TMP75 temperature sensor |
| `TMP421` | tmp421 | TI TMP421 remote diode sensor |
| `TMP112` | tmp102 | TI TMP112 low-power sensor |
| `LM75A` | lm75 | NXP LM75A temperature sensor |
| `EMC1413` | emc1403 | Microchip multi-channel |
| `MAX31725` | max31725 | Maxim precision sensor |
| `NCT7802` | nct7802 | Nuvoton multi-function |
| `W83773G` | w83773g | Nuvoton triple temp |

### FanSensor Daemon

For fan tachometer and PWM monitoring.

**Service:** `xyz.openbmc_project.FanSensor`

```json
{
    "Exposes": [
        {
            "Connector": {
                "Name": "Fan0",
                "Pwm": 0,
                "Tachs": [0]
            },
            "Name": "Fan0",
            "Type": "AspeedFan"
        }
    ],
    "Name": "FanBoard",
    "Probe": "TRUE",
    "Type": "Board"
}
```

---

## Kernel Driver Configuration

### Device Tree

```dts
// I2C temperature sensor
&i2c1 {
    status = "okay";

    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
    };

    tmp75@49 {
        compatible = "ti,tmp75";
        reg = <0x49>;
    };
};

// Aspeed ADC
&adc {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_adc0_default
                 &pinctrl_adc1_default
                 &pinctrl_adc2_default>;
};

// Aspeed PWM/Fan tach
&pwm_tacho {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_pwm0_default
                 &pinctrl_tach0_default>;

    fan@0 {
        reg = <0x00>;
        aspeed,fan-tach-ch = /bits/ 8 <0x00>;
    };
};
```

### Loading Drivers Manually

```bash
# Load I2C device
echo tmp75 0x48 > /sys/bus/i2c/devices/i2c-1/new_device

# Check if hwmon appeared
ls /sys/bus/i2c/devices/1-0048/hwmon/

# Remove device
echo 0x48 > /sys/bus/i2c/devices/i2c-1/delete_device
```

---

## Reading Sensors

### Direct Sysfs Access

```bash
# Find hwmon device
find /sys/class/hwmon -name "name" -exec sh -c 'echo "$1: $(cat $1)"' _ {} \;

# Read temperature (millidegrees to degrees)
temp=$(cat /sys/class/hwmon/hwmon0/temp1_input)
echo "Temperature: $((temp / 1000)).$((temp % 1000)) C"

# Read all temperature sensors
for f in /sys/class/hwmon/hwmon*/temp*_input; do
    name=$(dirname $f)/name
    label=$(echo $f | sed 's/_input/_label/')
    val=$(cat $f 2>/dev/null)
    if [ -n "$val" ]; then
        echo "$(cat $name 2>/dev/null) $(cat $label 2>/dev/null): $((val/1000))C"
    fi
done
```

### Via D-Bus

```bash
# List temperature sensors
busctl tree xyz.openbmc_project.HwmonTempSensor

# Read specific sensor
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Ambient_Temp \
    xyz.openbmc_project.Sensor.Value Value

# List all sensor values
busctl call xyz.openbmc_project.ObjectMapper \
    /xyz/openbmc_project/object_mapper \
    xyz.openbmc_project.ObjectMapper \
    GetSubTree sias "/xyz/openbmc_project/sensors" 0 1 \
    "xyz.openbmc_project.Sensor.Value"
```

### Via Redfish

```bash
# List all sensors
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors

# Get specific sensor
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors/Ambient_Temp
```

---

## Phosphor-Hwmon vs Dbus-Sensors

| Feature | phosphor-hwmon | dbus-sensors |
|---------|----------------|--------------|
| Configuration | YAML files | Entity Manager JSON |
| Auto-discovery | No | Yes (probes) |
| Hot-plug support | Limited | Yes |
| Sensor types | Generic | Type-specific daemons |
| Threshold config | YAML | JSON with severity |
| Recommended for | Legacy systems | New platforms |

### Migration Path

1. Identify existing phosphor-hwmon configs
2. Create Entity Manager JSON equivalents
3. Verify sensor names match
4. Test threshold behavior
5. Remove old YAML configs
6. Update machine layer

---

## Troubleshooting

### Sensor Not Appearing

```bash
# Check kernel driver loaded
dmesg | grep -i tmp75
lsmod | grep tmp75

# Verify I2C device exists
i2cdetect -y 1

# Check hwmon created
ls /sys/bus/i2c/devices/1-0048/hwmon/

# Check daemon logs
journalctl -u xyz.openbmc_project.hwmontempsensor -f
```

### Wrong Readings

```bash
# Compare raw hwmon value
cat /sys/class/hwmon/hwmon0/temp1_input
# 25500 (25.5°C in millidegrees)

# Compare D-Bus value
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Ambient_Temp \
    xyz.openbmc_project.Sensor.Value Value
# d 25.5

# Check for scaling issues in Entity Manager
# ScaleFactor, Offset properties
```

### Threshold Alarms Not Working

```bash
# Check threshold values on D-Bus
busctl introspect xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/Ambient_Temp | grep -i threshold

# Verify sel-logger is running
systemctl status xyz.openbmc_project.sel-logger

# Check for threshold events
journalctl -u xyz.openbmc_project.sel-logger | grep -i threshold
```

### Device Not Binding

```bash
# Check device tree
cat /sys/firmware/devicetree/base/ahb/apb/bus@1e78a000/i2c-bus@80/tmp75@48/compatible

# Try manual bind
echo "1-0048" > /sys/bus/i2c/drivers/tmp75/bind

# Check kernel errors
dmesg | tail -20
```

---

## Best Practices

1. **Use dbus-sensors** for new platforms
2. **Verify device tree** bindings match actual hardware
3. **Test thresholds** to ensure alarms trigger correctly
4. **Use meaningful names** that identify physical location
5. **Document scaling factors** for voltage dividers
6. **Monitor daemon logs** during development

---

## References

- [phosphor-hwmon](https://github.com/openbmc/phosphor-hwmon)
- [dbus-sensors](https://github.com/openbmc/dbus-sensors)
- [Linux hwmon Documentation](https://www.kernel.org/doc/html/latest/hwmon/index.html)
- [Entity Manager](https://github.com/openbmc/entity-manager)

---

{: .note }
**Tested on**: OpenBMC master, QEMU romulus
