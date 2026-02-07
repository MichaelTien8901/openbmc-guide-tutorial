---
layout: default
title: PECI Thermal Monitoring
parent: Core Services
nav_order: 15
difficulty: intermediate
prerequisites:
  - environment-setup
  - first-build
last_modified_date: 2026-02-06
---

# PECI Thermal Monitoring
{: .no_toc }

Configure PECI (Platform Environment Control Interface) to read CPU and DIMM temperatures through the BMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**PECI** (Platform Environment Control Interface) is Intel's single-wire serial bus that connects the BMC to one or more host CPUs. Through PECI, the BMC reads CPU die temperatures, DIMM temperatures, package configuration data, and model-specific registers -- all without consuming an I2C bus or requiring the host OS to be running.

On OpenBMC, PECI thermal monitoring involves three layers: the ASPEED PECI hardware controller, Linux kernel PECI drivers that expose readings through hwmon sysfs, and dbus-sensors daemons that publish those readings on D-Bus for consumption by bmcweb, ipmid, and fan control.

This guide walks you through the full stack: understanding the PECI protocol, configuring the device tree and kernel drivers, setting up Entity Manager for sensor discovery, reading temperatures through D-Bus and Redfish, and diagnosing common failures.

**Key concepts covered:**
- PECI single-wire protocol and CPU addressing (0x30, 0x31)
- PECI command types: Ping, GetTemp, RdPkgConfig, RdIAMSR
- Kernel drivers: peci-aspeed, peci-cputemp, peci-dimmtemp
- Device tree configuration for AST2500/AST2600
- dbus-sensors integration with Entity Manager
- Troubleshooting PECI connectivity and sensor failures

{: .note }
PECI is **not testable in QEMU**. The QEMU AST2600 model does not emulate the PECI controller or CPU thermal data. You need physical hardware with an Intel CPU connected via PECI to test this guide.

---

## Architecture

PECI uses a single wire between the BMC and each CPU socket. The BMC acts as the originator (master) and each CPU acts as a responder (client). The bus operates at 2 kbps to 2 Mbps, negotiated automatically.

### Protocol Fundamentals

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PECI Bus Topology                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ┌───────────────┐         Single Wire (PECI)                          │
│   │     BMC       │──────────────────────────┬──────────────────────┐   │
│   │  (Originator) │                          │                      │   │
│   │  ASPEED       │                  ┌───────┴───────┐      ┌───────┴───────┐
│   │  AST2500/2600 │                  │    CPU 0      │      │    CPU 1      │
│   └───────────────┘                  │  (Responder)  │      │  (Responder)  │
│                                      │  Addr: 0x30   │      │  Addr: 0x31   │
│                                      └───────────────┘      └───────────────┘
│                                                                         │
│   Signal: Open-drain, negotiated bit rate                               │
│   Voltage: 1.1V nominal (varies by CPU generation)                      │
│   Max clients: Typically 2 (dual-socket), up to 8 by spec              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### CPU Address Assignment

Each CPU on the PECI bus has a fixed address determined by its socket position:

| Socket | PECI Address | Description |
|--------|-------------|-------------|
| CPU 0  | `0x30`      | First processor socket |
| CPU 1  | `0x31`      | Second processor socket |
| CPU 2  | `0x32`      | Third processor socket (4S platforms) |
| CPU 3  | `0x33`      | Fourth processor socket (4S platforms) |

{: .note }
PECI addresses are hardwired by the CPU socket position on the motherboard. You do not configure them in software.

### PECI Command Types

| Command | Code | Description | Typical Use |
|---------|------|-------------|-------------|
| `Ping` | `0x00` | Check if CPU is alive and responding | Connectivity test |
| `GetTemp` | `0x01` | Read CPU die temperature (DTS) | Primary thermal monitoring |
| `RdPkgConfig` | `0xA1` | Read package configuration data | DIMM temps, TDP, core count |
| `WrPkgConfig` | `0xA5` | Write package configuration data | Set thermal thresholds |
| `RdIAMSR` | `0xB1` | Read IA model-specific register | Power, frequency, C-state data |

{: .tip }
`GetTemp` returns the CPU die temperature as a relative value below the thermal control circuit (TCC) activation temperature. The kernel driver converts this to an absolute temperature using the TCC offset stored in the CPU's package configuration.

### Software Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    PECI Thermal Monitoring Stack                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  D-Bus Consumers: bmcweb (Redfish)  │  ipmid  │  fan-control    │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                         │
│  ┌────────────────────────────┴─────────────────────────────────────┐   │
│  │  D-Bus: xyz.openbmc_project.Sensor.Value                        │   │
│  │  /xyz/openbmc_project/sensors/temperature/CPU0_Temp              │   │
│  │  /xyz/openbmc_project/sensors/temperature/CPU0_DIMM0_Temp       │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                         │
│  ┌────────────────────────────┴─────────────────────────────────────┐   │
│  │  dbus-sensors PECISensor (configured via Entity Manager JSON)   │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                         │
│  ┌────────────────────────────┴─────────────────────────────────────┐   │
│  │  Kernel: peci-cputemp, peci-dimmtemp ──> /sys/class/hwmon/      │   │
│  │          peci-aspeed ──> PECI bus controller                     │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                         │
│  ┌────────────────────────────┴─────────────────────────────────────┐   │
│  │  Hardware: AST2500/AST2600 PECI Controller ←── Wire ──→ CPU(s)  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.Sensor.Value` | `/xyz/openbmc_project/sensors/temperature/<name>` | CPU or DIMM temperature reading |
| `xyz.openbmc_project.Sensor.Threshold.Warning` | `/xyz/openbmc_project/sensors/temperature/<name>` | Warning threshold levels |
| `xyz.openbmc_project.Sensor.Threshold.Critical` | `/xyz/openbmc_project/sensors/temperature/<name>` | Critical threshold levels |

### Key Dependencies

- **peci-aspeed**: Kernel driver for the ASPEED PECI hardware controller
- **peci-cputemp**: Reads CPU die temperatures via PECI GetTemp command
- **peci-dimmtemp**: Reads DIMM temperatures via PECI RdPkgConfig command
- **dbus-sensors**: Polls hwmon sysfs and publishes readings on D-Bus
- **Entity Manager**: JSON-based configuration for PECI sensor discovery

---

## Configuration

### Kernel Driver Configuration

The PECI subsystem requires three kernel drivers working together:

| Driver | Module | Purpose |
|--------|--------|---------|
| `peci-aspeed` | `peci_aspeed` | Controls the ASPEED SoC PECI hardware engine |
| `peci-cputemp` | `peci_cputemp` | Reads CPU die temperature via GetTemp command |
| `peci-dimmtemp` | `peci_dimmtemp` | Reads DIMM temperatures via RdPkgConfig command |

Enable these options in your kernel configuration fragment (e.g., `peci.cfg`):

```
CONFIG_PECI=y
CONFIG_PECI_ASPEED=y
CONFIG_SENSORS_PECI_CPUTEMP=y
CONFIG_SENSORS_PECI_DIMMTEMP=y
```

### Device Tree Configuration

Add the PECI controller and client sub-nodes for each CPU socket in your platform device tree.

#### AST2600 Example

```dts
/* aspeed-bmc-myplatform.dts */
&peci0 {
    status = "okay";

    /* CPU 0 at PECI address 0x30 */
    peci-client@30 {
        compatible = "intel,peci-client";
        reg = <0x30>;
    };

    /* CPU 1 at PECI address 0x31 (dual-socket only) */
    peci-client@31 {
        compatible = "intel,peci-client";
        reg = <0x31>;
    };
};
```

{: .warning }
The `reg` value must match the CPU's PECI address. Using the wrong address causes all PECI commands to that client to fail with no response. Check your platform's hardware schematic for socket-to-address mapping.

### Build-Time Configuration (Yocto)

Include PECI sensor daemons in your image and add the kernel config fragment:

```bitbake
# In your machine .conf or image recipe
IMAGE_INSTALL:append = " dbus-sensors"
```

```bitbake
# meta-myplatform/recipes-kernel/linux/linux-aspeed_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://peci.cfg"
```

### Meson Build Options (dbus-sensors)

When building dbus-sensors from source:

```bash
meson setup build -Dpeci=enabled
```

---

## Entity Manager PECI Configuration

Entity Manager provides the JSON configuration that tells dbus-sensors how to discover and expose PECI sensors. The PECI sensor daemon watches for Entity Manager configuration objects of type `XeonCPU` and creates hwmon-backed D-Bus sensor objects for each CPU and its DIMMs.

### Configuration File

Create a JSON configuration at `/usr/share/entity-manager/configurations/`:

```json
{
    "Exposes": [
        {
            "Name": "CPU0",
            "Type": "XeonCPU",
            "Bus": 0,
            "Address": "0x30",
            "CpuID": 0,
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 95
                },
                {
                    "Direction": "greater than",
                    "Name": "upper warning",
                    "Severity": 0,
                    "Value": 85
                }
            ]
        },
        {
            "Name": "CPU1",
            "Type": "XeonCPU",
            "Bus": 0,
            "Address": "0x31",
            "CpuID": 1,
            "Thresholds": [
                {
                    "Direction": "greater than",
                    "Name": "upper critical",
                    "Severity": 1,
                    "Value": 95
                },
                {
                    "Direction": "greater than",
                    "Name": "upper warning",
                    "Severity": 0,
                    "Value": 85
                }
            ]
        }
    ],
    "Name": "PeciSensors",
    "Probe": "TRUE",
    "Type": "Board"
}
```

### Entity Manager Properties for PECI

| Property | Type | Description |
|----------|------|-------------|
| `Name` | string | Sensor name prefix (e.g., "CPU0") |
| `Type` | string | Must be `XeonCPU` for PECI sensors |
| `Bus` | integer | PECI bus number (typically 0) |
| `Address` | string | CPU PECI address in hex (e.g., "0x30") |
| `CpuID` | integer | CPU socket index (0, 1, 2, 3) |
| `Thresholds` | array | Warning and critical temperature thresholds |

### Deploying Configuration via bbappend

Install the Entity Manager configuration through your machine layer:

```bitbake
# meta-myplatform/recipes-phosphor/configuration/entity-manager_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://peci-sensors.json"

do_install:append() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0644 ${WORKDIR}/peci-sensors.json \
        ${D}${datadir}/entity-manager/configurations/
}

FILES:${PN} += "${datadir}/entity-manager/configurations/peci-sensors.json"
```

---

## Porting Guide

Follow these steps to enable PECI thermal monitoring on your platform:

### Step 1: Prerequisites

Ensure you have:
- [ ] An ASPEED AST2500 or AST2600 BMC with a PECI pin connected to the host CPU(s)
- [ ] Intel Xeon or compatible CPU(s) supporting PECI
- [ ] A working OpenBMC build environment with your machine layer
- [ ] The host CPU powered on (PECI requires CPU power to respond)

### Step 2: Configure the Device Tree

Add the PECI controller and client nodes to your platform device tree:

```dts
&peci0 {
    status = "okay";
    peci-client@30 {
        compatible = "intel,peci-client";
        reg = <0x30>;
    };
};
```

### Step 3: Enable Kernel Drivers

Create `peci.cfg` in your kernel recipe directory and add the bbappend as shown in [Build-Time Configuration](#build-time-configuration-yocto).

### Step 4: Create Entity Manager Configuration

Create the PECI sensor JSON and install it via a bbappend as shown in [Entity Manager PECI Configuration](#entity-manager-peci-configuration).

### Step 5: Build and Verify

```bash
# Build the image
bitbake obmc-phosphor-image

# Flash and boot the BMC, then verify:

# 1. Check PECI drivers
dmesg | grep -i peci

# 2. Verify PECI devices
ls /sys/bus/peci/devices/

# 3. Test connectivity
peci_cmds Ping -a 0x30

# 4. Check D-Bus sensors
busctl tree xyz.openbmc_project.PECISensor

# 5. Read temperature
busctl get-property xyz.openbmc_project.PECISensor \
    /xyz/openbmc_project/sensors/temperature/CPU0_Temp \
    xyz.openbmc_project.Sensor.Value Value
```

---

## Verifying PECI Sensors

After booting with the PECI configuration in place and the host CPU powered on, verify each layer of the stack from bottom to top.

### Verify Kernel Drivers and Hwmon

```bash
# Check PECI controller driver
dmesg | grep -i peci
# Expected: "peci-aspeed 1e78b000.peci-bus: peci bus 0 registered"

# Check for PECI clients
ls /sys/bus/peci/devices/
# Expected: 0-30  0-31

# Check hwmon devices
ls /sys/bus/peci/devices/0-30/peci-cputemp.0/hwmon/
ls /sys/bus/peci/devices/0-30/peci-dimmtemp.0/hwmon/
```

### Read Raw Hwmon Values

```bash
# Find and read all PECI hwmon sensors
for d in /sys/class/hwmon/hwmon*; do
    name=$(cat "$d/name" 2>/dev/null)
    if echo "$name" | grep -q peci; then
        echo "=== $d ($name) ==="
        for f in "$d"/temp*_input; do
            label=$(cat "${f%_input}_label" 2>/dev/null || echo "unknown")
            val=$(cat "$f" 2>/dev/null)
            if [ -n "$val" ]; then
                echo "  $label: $((val / 1000))°C"
            fi
        done
    fi
done
```

### Test with peci_cmds

The `peci_cmds` utility allows you to send raw PECI commands for testing:

```bash
# Ping CPU 0
peci_cmds Ping -a 0x30

# Read CPU 0 die temperature
peci_cmds GetTemp -a 0x30

# Read package configuration (TCC activation temp)
peci_cmds RdPkgConfig -a 0x30 -i 0 -p 16

# Read IA MSR (e.g., platform info)
peci_cmds RdIAMSR -a 0x30 -i 0 -m 0xCE
```

### Verify D-Bus Sensors

```bash
# List all PECI temperature sensors
busctl tree xyz.openbmc_project.PECISensor

# Read CPU0 die temperature
busctl get-property xyz.openbmc_project.PECISensor \
    /xyz/openbmc_project/sensors/temperature/CPU0_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Read CPU0 DIMM0 temperature
busctl get-property xyz.openbmc_project.PECISensor \
    /xyz/openbmc_project/sensors/temperature/CPU0_DIMM0_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Check threshold status
busctl get-property xyz.openbmc_project.PECISensor \
    /xyz/openbmc_project/sensors/temperature/CPU0_Temp \
    xyz.openbmc_project.Sensor.Threshold.Critical CriticalAlarmHigh
```

### Verify via Redfish

```bash
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors/CPU0_Temp

curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Thermal
```

---

## Code Examples

### Example 1: PECI Health Check Script

A shell script to verify PECI connectivity and read temperatures from all detected CPUs:

```bash
#!/bin/bash
# peci_health_check.sh - Verify PECI connectivity and read temperatures

PECI_ADDRS="0x30 0x31"

echo "=== PECI Health Check ==="

# Check kernel drivers
echo ""
echo "--- Kernel Drivers ---"
for mod in peci_aspeed peci_cputemp peci_dimmtemp; do
    if [ -d "/sys/module/$mod" ]; then
        echo "[OK] $mod loaded"
    else
        echo "[FAIL] $mod NOT loaded"
    fi
done

# Check PECI devices
echo ""
echo "--- PECI Devices ---"
ls /sys/bus/peci/devices/ 2>/dev/null || echo "No PECI devices found"

# Ping each CPU and read temperature
echo ""
echo "--- PECI Connectivity ---"
for addr in $PECI_ADDRS; do
    result=$(peci_cmds Ping -a "$addr" 2>&1)
    if echo "$result" | grep -qi "succeed"; then
        temp=$(peci_cmds GetTemp -a "$addr" 2>&1)
        echo "[OK] CPU at $addr: $temp"
    else
        echo "[--] CPU at $addr: not responding"
    fi
done

# Read hwmon PECI sensors
echo ""
echo "--- Hwmon PECI Sensors ---"
for d in /sys/class/hwmon/hwmon*; do
    name=$(cat "$d/name" 2>/dev/null)
    if echo "$name" | grep -q peci; then
        echo "Device: $d ($name)"
        for f in "$d"/temp*_input; do
            [ -f "$f" ] || continue
            label=$(cat "${f%_input}_label" 2>/dev/null || basename "$f")
            val=$(cat "$f" 2>/dev/null)
            if [ -n "$val" ] && [ "$val" != "0" ]; then
                echo "  $label: $((val / 1000))°C"
            fi
        done
    fi
done
echo ""
echo "=== Check Complete ==="
```

### Example 2: Reading PECI Sensors via D-Bus (Python)

```python
#!/usr/bin/env python3
"""Read PECI CPU and DIMM temperatures from D-Bus."""
import subprocess

SERVICE = "xyz.openbmc_project.PECISensor"

def get_sensor_value(path):
    """Read a sensor value from D-Bus using busctl."""
    try:
        result = subprocess.run(
            ["busctl", "get-property", SERVICE, path,
             "xyz.openbmc_project.Sensor.Value", "Value"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            parts = result.stdout.strip().split()
            if len(parts) >= 2:
                return float(parts[1])
    except (subprocess.TimeoutExpired, ValueError):
        pass
    return None

def list_peci_sensors():
    """List all temperature sensors from PECISensor service."""
    result = subprocess.run(
        ["busctl", "tree", SERVICE],
        capture_output=True, text=True, timeout=5,
    )
    return [line.strip() for line in result.stdout.splitlines()
            if "/sensors/temperature/" in line]

if __name__ == "__main__":
    sensors = list_peci_sensors()
    if not sensors:
        print("No PECI sensors found. Is the host CPU powered on?")
    else:
        print(f"Found {len(sensors)} PECI sensor(s):")
        for path in sensors:
            value = get_sensor_value(path)
            name = path.split("/")[-1]
            status = f"{value:.1f} C" if value is not None else "unavailable"
            print(f"  {name}: {status}")
```

See additional examples in the [examples/peci/]({{ site.baseurl }}/examples/peci/) directory.

---

## Troubleshooting

### Issue: PECI Ping Fails (No Response from CPU)

**Symptom**: `peci_cmds Ping -a 0x30` returns an error or times out.

**Cause**: The CPU is not powered on, the PECI wire is not connected, or the PECI controller driver is not loaded.

**Solution**:
1. Verify the host CPU is powered on:
   ```bash
   busctl get-property xyz.openbmc_project.State.Host \
       /xyz/openbmc_project/state/host0 \
       xyz.openbmc_project.State.Host CurrentHostState
   ```
2. Check the PECI controller driver loaded:
   ```bash
   dmesg | grep -i peci
   ls /sys/bus/peci/
   ```
3. Verify device tree configuration:
   ```bash
   cat /sys/firmware/devicetree/base/ahb/apb/peci-bus@*/status
   ```

{: .warning }
PECI **requires** the CPU to be powered on and through its reset sequence. If the host is off or in standby, all PECI commands will fail. This is expected behavior, not a bug.

### Issue: Kernel Driver Not Loaded

**Symptom**: `dmesg | grep peci` shows no output. `/sys/bus/peci/` does not exist.

**Cause**: The PECI kernel modules are not built or not included in the image.

**Solution**:
1. Verify kernel config:
   ```bash
   zcat /proc/config.gz | grep -i peci
   ```
2. If options are missing, add the kernel config fragment and rebuild.
3. If built as modules, load manually:
   ```bash
   modprobe peci_aspeed
   modprobe peci_cputemp
   modprobe peci_dimmtemp
   ```

### Issue: Hwmon Devices Not Created

**Symptom**: PECI ping succeeds, but no hwmon entries appear under `/sys/bus/peci/devices/0-30/`.

**Cause**: The peci-cputemp or peci-dimmtemp drivers are not loaded, or the CPU has not completed POST.

**Solution**:
1. Check client sub-driver directories:
   ```bash
   ls /sys/bus/peci/devices/0-30/
   ```
2. Wait for the CPU to complete POST, then trigger a rescan:
   ```bash
   echo 1 > /sys/bus/peci/rescan
   ```

### Issue: D-Bus Sensors Show NaN

**Symptom**: `busctl get-property` returns `d nan` for PECI sensor values.

**Cause**: The host is not powered on, or the hwmon file is returning an error.

**Solution**:
1. Confirm the host power state is `Running`.
2. Read the raw hwmon value directly:
   ```bash
   cat /sys/class/hwmon/hwmon<N>/temp1_input
   ```
3. Check the PECISensor daemon logs:
   ```bash
   journalctl -u xyz.openbmc_project.pecisensor -f
   ```

### Issue: DIMM Temperatures Not Available

**Symptom**: CPU die temperature works, but DIMM temperatures are not exposed.

**Cause**: The peci-dimmtemp driver did not detect populated DIMM slots, or the CPU model does not support DIMM temperature reading via PECI.

**Solution**:
1. Check if peci-dimmtemp created hwmon entries:
   ```bash
   ls /sys/bus/peci/devices/0-30/peci-dimmtemp.0/hwmon/
   ```
2. Verify DIMM population using PECI package config:
   ```bash
   peci_cmds RdPkgConfig -a 0x30 -i 0 -p 14
   ```

### Debug Commands

```bash
# Check all PECI-related services
systemctl list-units | grep -i peci

# View PECISensor logs
journalctl -u xyz.openbmc_project.pecisensor -f

# Check Entity Manager detected PECI config
journalctl -u xyz.openbmc_project.EntityManager | grep -i peci

# Kernel PECI bus status
ls -la /sys/bus/peci/devices/
dmesg | grep -i peci

# Raw PECI commands
peci_cmds Ping -a 0x30
peci_cmds GetTemp -a 0x30
peci_cmds RdPkgConfig -a 0x30 -i 0 -p 16
```

---

## References

### Official Resources
- [dbus-sensors Repository](https://github.com/openbmc/dbus-sensors) (contains PECISensor implementation)
- [linux-aspeed PECI Driver](https://github.com/openbmc/linux/tree/dev-6.1/drivers/peci)
- [D-Bus Sensor Interface Definitions](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/Sensor)
- [Entity Manager](https://github.com/openbmc/entity-manager)

### Related Guides
- [D-Bus Sensors Guide]({% link docs/03-core-services/01-dbus-sensors-guide.md %})
- [Hwmon Sensors Guide]({% link docs/03-core-services/02-hwmon-sensors-guide.md %})
- [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %})
- [Fan Control Guide]({% link docs/03-core-services/04-fan-control-guide.md %})

### External Documentation
- [Intel PECI Specification](https://www.intel.com/content/www/us/en/developer/articles/technical/platform-environment-control-interface-peci.html)
- [Linux Kernel PECI Subsystem](https://www.kernel.org/doc/html/latest/admin-guide/peci/index.html)
- [ASPEED AST2600 Datasheet](https://www.aspeedtech.com/products.php?fPath=20&rId=440) (PECI controller chapter)

---

{: .note }
**Tested on**: Physical AST2600 EVB with Intel Xeon CPU. PECI is not emulated in QEMU -- all PECI commands and sensor readings require real hardware with a powered-on host CPU.
Last updated: 2026-02-06
