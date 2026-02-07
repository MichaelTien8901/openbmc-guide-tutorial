---
layout: default
title: GPIO Management Guide
parent: Core Services
nav_order: 14
difficulty: intermediate
prerequisites:
  - dbus-guide
  - buttons-guide
last_modified_date: 2026-02-06
---

# GPIO Management Guide
{: .no_toc }

Configure phosphor-multi-gpio-monitor to detect hardware signals and trigger system actions on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-multi-gpio-monitor** watches named GPIO lines for edge or level changes and triggers systemd targets or D-Bus actions in response. It replaces the older single-line phosphor-gpio-monitor with a unified JSON configuration that supports multiple GPIO signals in one service instance.

Every OpenBMC platform relies on GPIO monitoring for critical functions: detecting power button presses, sensing chassis intrusion, tracking device presence, and responding to hardware fault signals. This guide covers discovering GPIO line names, writing the JSON configuration, wiring events to systemd targets, choosing between continuous and one-shot monitoring, and deploying through a Yocto bbappend file.

**Key concepts covered:**
- phosphor-multi-gpio-monitor JSON configuration format
- GPIO line name mapping from device tree to libgpiod
- Edge event types: RISING, FALLING, BOTH
- Event-to-systemd-target integration
- Continuous vs one-shot monitoring modes
- Platform bbappend customization for deployment

{: .note }
GPIO monitoring is **partially testable** in QEMU. The ast2600-evb QEMU target provides emulated GPIO pins that you can toggle from the QEMU monitor, but real edge timing and electrical behavior require physical hardware.

---

## Architecture

phosphor-multi-gpio-monitor reads a JSON configuration file at startup, opens each named GPIO line through libgpiod, and polls for events. When an event matches the configured edge type, the monitor activates a systemd target or calls a D-Bus method.

### Data Flow

```
Hardware GPIO pins
        │
        v
ASPEED GPIO Controller (gpio-line-names from device tree)
        │
        v
Linux GPIO Subsystem (/dev/gpiochip0, libgpiod)
        │
        v
phosphor-multi-gpio-monitor
  ├── JSON Config Parser
  ├── Event Loop (sd_event + libgpiod polling)
  └── Action Engine
        │
        ├──> systemd targets (power off, reset, etc.)
        ├──> D-Bus property updates
        └──> Journal logging
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.Chassis.Intrusion` | `/xyz/openbmc_project/Chassis/Intrusion` | Chassis intrusion detection status |
| `xyz.openbmc_project.Inventory.Item` | `/xyz/openbmc_project/inventory/system/chassis/<device>` | Device presence state |
| `xyz.openbmc_project.State.Chassis` | `/xyz/openbmc_project/state/chassis0` | Chassis power state transitions |

### Key Dependencies

- **libgpiod**: Provides the userspace API for accessing GPIO lines by name
- **systemd**: Receives target activation requests from the monitor
- **phosphor-dbus-interfaces**: Defines standard D-Bus interfaces for chassis and inventory objects
- **Device tree gpio-line-names**: Maps hardware GPIO numbers to human-readable line names

---

## GPIO Line Name Discovery

Before you write any configuration, you need to discover the GPIO line names available on your platform. These names come from the device tree and are the keys you use in the JSON configuration.

### Device Tree gpio-line-names Property

The ASPEED device tree assigns human-readable names to GPIO pins through the `gpio-line-names` property on each GPIO controller node. Each string in the array maps positionally to a GPIO offset on that controller.

```dts
/* Example from aspeed-bmc-myplatform.dts */
&gpio0 {
    gpio-line-names =
        /*  A0-A7 */  "","","","","","","","",
        /*  B0-B7 */  "POWER_BUTTON","RESET_BUTTON","","","","","","",
        /*  C0-C7 */  "","","","","","","","",
        /*  D0-D7 */  "PS0_PRESENT","PS1_PRESENT","","","","","","",
        /*  E0-E7 */  "","","CHASSIS_INTRUSION","","","","","",
        /*  F0-F7 */  "FAN0_PRESENT","FAN1_PRESENT","FAN2_PRESENT","FAN3_PRESENT",
                      "","","","";
};
```

{: .tip }
The position of each name in the `gpio-line-names` array directly corresponds to the GPIO offset on that chip. An empty string `""` means that pin has no assigned name. Count from offset 0 at the start of the array.

### Discovering Lines with gpioinfo

Use `gpioinfo` on a running BMC to list all available GPIO lines and their current state. This is the fastest way to find the correct line name for your configuration.

```bash
# List all GPIO chips and their lines
gpioinfo
# gpiochip0 - 232 lines:
#     line   8:  "POWER_BUTTON" unused  input  active-high
#     line  24:  "PS0_PRESENT"  unused  input  active-high
#     line  34:  "CHASSIS_INTRUSION" unused input active-high

# Filter for a specific line name
gpioinfo | grep -i "power_button"

# Read current value / monitor events on a line
gpioget gpiochip0 8
gpiomon --num-events=1 --rising-edge gpiochip0 8
```

{: .warning }
GPIO line names are platform-specific. The names in your device tree must match exactly (case-sensitive) with the names in your phosphor-multi-gpio-monitor JSON configuration. A mismatch causes the monitor to fail silently for that line.

{: .tip }
In the QEMU ast2600-evb environment, run `gpiodetect` and `gpioinfo | grep -v unnamed` to see which named lines are available for testing.

---

## phosphor-multi-gpio-monitor Configuration

The monitor reads its configuration from a JSON file, typically installed at `/etc/phosphor-multi-gpio-monitor.json` or `/usr/share/phosphor-gpio-monitor/phosphor-multi-gpio-monitor.json`.

### Configuration File Format

Each entry in the `GpioConfigs` array defines one GPIO line to monitor.

```json
{
    "Name": "<gpio-line-name>",
    "LineName": "<gpio-line-name>",
    "GpioNum": 0,
    "ChipId": "",
    "EventMon": "<RISING|FALLING|BOTH>",
    "Targets": {
        "<signal-value>": ["<systemd-target-to-activate>"]
    },
    "Continue": <true|false>
}
```

| Field | Type | Description |
|-------|------|-------------|
| `Name` | string | Human-readable name for logging |
| `LineName` | string | GPIO line name from device tree (must match `gpio-line-names`) |
| `GpioNum` | integer | GPIO offset number (used only if `LineName` is empty) |
| `ChipId` | string | GPIO chip path (used only if `LineName` is empty, e.g., `/dev/gpiochip0`) |
| `EventMon` | string | Edge type to watch: `RISING`, `FALLING`, or `BOTH` |
| `Targets` | object | Maps signal values (`"0"` or `"1"`) to arrays of systemd target names |
| `Continue` | boolean | `true` for continuous monitoring, `false` for one-shot |

{: .note }
Prefer `LineName` over `GpioNum` + `ChipId`. Named lines are portable across kernel versions and device tree changes, while raw GPIO numbers can shift when pins are remapped.

### Annotated Example

The following configuration monitors a power button (one-shot, falling edge) and chassis intrusion sensor (continuous, both edges). Save this as `phosphor-multi-gpio-monitor.json`:

```json
{
    "GpioConfigs": [
        {
            "Name": "PowerButton",          // Human-readable label for logs
            "LineName": "POWER_BUTTON",     // Must match device tree gpio-line-names
            "GpioNum": 0,                   // Ignored when LineName is set
            "ChipId": "",                   // Ignored when LineName is set
            "EventMon": "FALLING",          // Trigger on button press (active-low)
            "Targets": {
                "0": ["obmc-chassis-hard-poweroff@0.target"]
            },
            "Continue": false               // One-shot: stop watching after first event
        },
        {
            "Name": "ChassisIntrusion",
            "LineName": "CHASSIS_INTRUSION",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "BOTH",             // Detect both open and close
            "Targets": {
                "0": ["chassis-intrusion-detected@0.target"],
                "1": ["chassis-intrusion-cleared@0.target"]
            },
            "Continue": true                // Continuous: keep watching
        }
    ]
}
```

See [Example 2](#example-2-multi-signal-platform-configuration) for a fuller production configuration with presence detection signals.

### Event Types Explained

| EventMon | Trigger Condition | Typical Use Case |
|----------|-------------------|------------------|
| `RISING` | GPIO transitions from low (0) to high (1) | Button release, signal asserted high |
| `FALLING` | GPIO transitions from high (1) to low (0) | Button press (active-low), signal deasserted |
| `BOTH` | Any transition in either direction | Presence detection, intrusion (need to detect insert and removal) |

{: .tip }
Most physical buttons are active-low (pressed = 0). Use `FALLING` to trigger on the press and `RISING` to trigger on the release. For presence pins that you need to track in both states, use `BOTH`.

---

## Event-to-Systemd-Target Integration

When a GPIO event fires, phosphor-multi-gpio-monitor activates one or more systemd targets listed in the `Targets` field. This is the primary mechanism for connecting hardware signals to software actions.

### How It Works

When the monitor detects an edge event, it reads the new line value (`"0"` or `"1"`), looks up the matching targets array, and calls `systemctl start <target>` for each target.

### Standard OpenBMC Targets

| Target | Purpose |
|--------|---------|
| `obmc-chassis-hard-poweroff@0.target` | Immediately cut chassis power |
| `obmc-host-shutdown@0.target` | Graceful host shutdown |
| `obmc-host-reset@0.target` | Host reset |
| `obmc-host-start@0.target` | Start host power-on sequence |
| `obmc-chassis-powerreset@0.target` | Chassis power cycle |

### Creating Custom Systemd Targets

For signals that do not map to standard targets, create your own target and service pair.

**Target file** (`chassis-intrusion-detected@.target`):

```ini
[Unit]
Description=Chassis Intrusion Detected on %i
Wants=log-chassis-intrusion@%i.service
```

**Service file** (`log-chassis-intrusion@.service`):

```ini
[Unit]
Description=Log Chassis Intrusion Event for %i

[Service]
Type=oneshot
ExecStart=/usr/bin/busctl set-property xyz.openbmc_project.Chassis.Intrusion \
    /xyz/openbmc_project/Chassis/Intrusion \
    xyz.openbmc_project.Chassis.Intrusion \
    Status s "HardwareIntrusion"
```

Then reference the target in your JSON config `Targets` field (see the [annotated example](#annotated-example) for chassis intrusion wiring).

### Multiple Targets per Event

You can activate multiple targets for a single event. List all targets in the array:

```json
"Targets": {
    "0": [
        "obmc-chassis-hard-poweroff@0.target",
        "log-power-button-pressed@0.target"
    ]
}
```

{: .warning }
Systemd target activation is asynchronous. The monitor does not wait for the target to complete before resuming GPIO polling. If you need ordering guarantees between targets, use `After=` and `Before=` directives within the target unit files.

---

## Continuous vs One-Shot Monitoring

The `Continue` field controls whether the monitor keeps watching a GPIO line after the first event.

- **One-shot (`Continue: false`)** -- After the first matching edge, the monitor stops watching this line. Use this for signals where you only respond once (e.g., a power button press that triggers a shutdown). The service continues running for other configured lines.
- **Continuous (`Continue: true`)** -- The monitor fires the appropriate target on every transition, indefinitely. Use this for signals that change repeatedly (e.g., device presence, chassis intrusion).

### Choosing the Right Mode

| Signal Type | Continue | EventMon | Rationale |
|-------------|----------|----------|-----------|
| Power button | `false` | `FALLING` | Single press triggers shutdown; further presses are ignored |
| Reset button | `false` | `FALLING` | Single press triggers reset |
| Chassis intrusion | `true` | `BOTH` | Must detect both intrusion and restoration |
| PSU presence | `true` | `BOTH` | PSU can be hot-swapped multiple times |
| Fan presence | `true` | `BOTH` | Fan trays can be inserted and removed |
| Fault signal | `true` | `FALLING` | Fault can recur after being cleared |

---

## Platform bbappend Customization

To deploy your GPIO configuration on a custom platform, create a bbappend file in your machine layer that installs the JSON configuration and any custom systemd targets.

### bbappend File

Place this file and a `files/` directory containing your JSON config and custom systemd units at `meta-myplatform/recipes-phosphor/gpio/phosphor-gpio-monitor/`:

```bitbake
# phosphor-gpio-monitor_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://phosphor-multi-gpio-monitor.json \
    file://chassis-intrusion-detected@.target \
    file://log-chassis-intrusion@.service \
"

do_install:append() {
    install -d ${D}${datadir}/phosphor-gpio-monitor
    install -m 0644 ${WORKDIR}/phosphor-multi-gpio-monitor.json \
        ${D}${datadir}/phosphor-gpio-monitor/

    install -d ${D}${systemd_system_unitdir}
    for f in chassis-intrusion-detected@.target log-chassis-intrusion@.service; do
        install -m 0644 ${WORKDIR}/$f ${D}${systemd_system_unitdir}/
    done
}

FILES:${PN} += " \
    ${datadir}/phosphor-gpio-monitor/phosphor-multi-gpio-monitor.json \
    ${systemd_system_unitdir}/*.target \
    ${systemd_system_unitdir}/log-chassis-intrusion@.service \
"
```

### Build-Time Options

| Option | Default | Description |
|--------|---------|-------------|
| `OBMC_GPIO_MONITOR_INSTANCES` | `multi` | Monitor instance type (`multi` for multi-line JSON config) |
| `SYSTEMD_SERVICE:${PN}` | `phosphor-multi-gpio-monitor.service` | Systemd service name |

Enable the GPIO monitor in your image configuration:

```bitbake
# In your machine.conf or local.conf
IMAGE_INSTALL:append = " phosphor-gpio-monitor"
```

{: .tip }
The `FILESEXTRAPATHS:prepend` variable tells BitBake to look in your layer's directory first when resolving files listed in `SRC_URI`. This allows you to override the default configuration without patching the upstream recipe.

{: .note }
Some platforms install the JSON configuration to `/etc/` instead of `/usr/share/`. Run `systemctl cat phosphor-multi-gpio-monitor.service | grep ExecStart` to check which `--config` path your service expects, and match your bbappend install path accordingly.

---

## Porting Guide

Follow these steps to enable GPIO monitoring on your platform:

1. **Discover GPIO line names** -- Boot your platform (or QEMU) and run `gpioinfo | grep -v unnamed`. Record every signal you need to monitor.
2. **Write the JSON configuration** -- Create `phosphor-multi-gpio-monitor.json` using the [annotated example](#complete-annotated-example) as a starting point. Adjust line names, event types, and targets for your hardware.
3. **Create custom targets** (if needed) -- For signals without standard OpenBMC targets, create `.target` and `.service` unit files as shown in the [Event-to-Systemd-Target Integration](#event-to-systemd-target-integration) section.
4. **Create the bbappend** -- Follow the [Platform bbappend Customization](#platform-bbappend-customization) section to install your configuration.
5. **Build and verify**:

```bash
# Build the image
bitbake obmc-phosphor-image

# Flash and boot the BMC, then verify the service
systemctl status phosphor-multi-gpio-monitor

# Check the monitor is watching the expected lines
journalctl -u phosphor-multi-gpio-monitor | head -20

# Verify GPIO lines are claimed
gpioinfo | grep -E "POWER_BUTTON|CHASSIS_INTRUSION|PS0_PRESENT"
# Lines should show "[used]" instead of "unused"
```

---

## Code Examples

### Example 1: Minimal Power Button Configuration

This is the simplest possible configuration -- one GPIO line that triggers a hard power off when pressed.

```json
{
    "GpioConfigs": [
        {
            "Name": "PowerButton",
            "LineName": "POWER_BUTTON",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "FALLING",
            "Targets": {
                "0": [
                    "obmc-chassis-hard-poweroff@0.target"
                ]
            },
            "Continue": false
        }
    ]
}
```

### Example 2: Multi-Signal Platform Configuration

A production configuration monitoring power, reset, intrusion, and fan presence. Duplicate the fan entry pattern for additional fans (FAN1, FAN2, FAN3, etc.).

```json
{
    "GpioConfigs": [
        {
            "Name": "PowerButton",
            "LineName": "POWER_BUTTON",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "FALLING",
            "Targets": {
                "0": ["obmc-chassis-hard-poweroff@0.target"]
            },
            "Continue": false
        },
        {
            "Name": "ResetButton",
            "LineName": "RESET_BUTTON",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "FALLING",
            "Targets": {
                "0": ["obmc-host-reset@0.target"]
            },
            "Continue": false
        },
        {
            "Name": "ChassisIntrusion",
            "LineName": "CHASSIS_INTRUSION",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "BOTH",
            "Targets": {
                "0": ["chassis-intrusion-detected@0.target"],
                "1": ["chassis-intrusion-cleared@0.target"]
            },
            "Continue": true
        },
        {
            "Name": "Fan0Presence",
            "LineName": "FAN0_PRESENT",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "BOTH",
            "Targets": {
                "0": ["fan0-present@0.target"],
                "1": ["fan0-absent@0.target"]
            },
            "Continue": true
        }
    ]
}
```

### Example 3: Using GpioNum Instead of LineName

If your device tree does not define `gpio-line-names`, you can fall back to specifying the GPIO chip and offset directly. This approach is less portable but works on any platform.

```json
{
    "GpioConfigs": [
        {
            "Name": "PowerButton",
            "LineName": "",
            "GpioNum": 8,
            "ChipId": "/dev/gpiochip0",
            "EventMon": "FALLING",
            "Targets": {
                "0": ["obmc-chassis-hard-poweroff@0.target"]
            },
            "Continue": false
        }
    ]
}
```

{: .warning }
Using `GpioNum` ties your configuration to a specific kernel GPIO numbering scheme. If the device tree changes or a driver is added that shifts GPIO offsets, your configuration breaks. Always prefer `LineName` when possible.

See additional working examples in the [examples/gpio-monitor/]({{ site.baseurl }}/examples/gpio-monitor/) directory.

---

## Troubleshooting

### Issue: Monitor Service Fails to Start

**Symptom**: `systemctl status phosphor-multi-gpio-monitor` shows `failed` or `activating` in a loop.

**Cause**: The JSON configuration references a GPIO line name that does not exist on this platform, or the JSON syntax is invalid.

**Solution**:
1. Check the journal for specific error messages:
   ```bash
   journalctl -u phosphor-multi-gpio-monitor -n 50
   ```
2. Validate your JSON syntax:
   ```bash
   python3 -m json.tool /usr/share/phosphor-gpio-monitor/phosphor-multi-gpio-monitor.json
   ```
3. Verify each `LineName` exists in `gpioinfo` output:
   ```bash
   gpioinfo | grep "POWER_BUTTON"
   ```

### Issue: GPIO Event Not Triggering Target

**Symptom**: You toggle the GPIO signal, but the expected systemd target does not activate.

**Cause**: The `EventMon` type does not match the actual signal transition, or the `Targets` key does not match the post-event line value.

**Solution**:
1. Confirm the GPIO line is claimed by the monitor:
   ```bash
   gpioinfo | grep "POWER_BUTTON"
   # Should show [used] not "unused"
   ```
2. Test the GPIO transition manually:
   ```bash
   gpiomon --num-events=1 gpiochip0 8
   # Toggle the signal and verify the event appears
   ```
3. Check that the `Targets` key matches the value after the transition. For a falling edge (high to low), the post-event value is `"0"`, so the target must be under `"0"`.

### Issue: Presence Detection Only Works Once

**Symptom**: Inserting a device triggers the present target, but removing and reinserting does not trigger again.

**Cause**: `Continue` is set to `false` in the configuration. The monitor stops watching after the first event.

**Solution**: Set `"Continue": true` for any signal that you need to detect repeatedly:
```json
"Continue": true
```

### Debug Commands

```bash
# Check service status and logs
systemctl status phosphor-multi-gpio-monitor
journalctl -u phosphor-multi-gpio-monitor -f

# GPIO discovery and testing
gpiodetect                              # List all GPIO chips
gpioinfo                                # Show all lines with states
gpioget gpiochip0 8                     # Read current value of a line
gpiomon --num-events=5 gpiochip0 8      # Monitor a line for events

# Verify targets and config path
systemctl list-units --type=target | grep -E "obmc|chassis|psu|fan"
systemctl cat phosphor-multi-gpio-monitor.service
```

---

## References

### Official Resources
- [phosphor-gpio-monitor Repository](https://github.com/openbmc/phosphor-gpio-monitor)
- [phosphor-dbus-interfaces (Chassis)](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/Chassis)
- [OpenBMC Documentation](https://github.com/openbmc/docs)

### Related Guides
- [Buttons Guide]({% link docs/03-core-services/13-buttons-guide.md %})
- [Power Management Guide]({% link docs/03-core-services/05-power-management-guide.md %})
- [LED Manager Guide]({% link docs/03-core-services/08-led-manager-guide.md %})

### External Documentation
- [libgpiod Documentation](https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/about/)
- [Linux GPIO Subsystem](https://www.kernel.org/doc/html/latest/driver-api/gpio/index.html)
- [Linux Device Tree GPIO Bindings](https://www.kernel.org/doc/Documentation/devicetree/bindings/gpio/gpio.txt)

---

{: .note }
**Tested on**: QEMU ast2600-evb (emulated GPIO pins, partial coverage). Full testing requires physical hardware with wired GPIO signals.
Last updated: 2026-02-06
