---
layout: default
title: Multi-Host Support
parent: Advanced Topics
nav_order: 14
difficulty: advanced
prerequisites:
  - state-manager-guide
  - systemd-boot-ordering-guide
last_modified_date: 2026-02-06
---

# Multi-Host Support
{: .no_toc }

Configure a single BMC to manage multiple host systems using IPMB bridging, per-host state management, D-Bus/systemd multiplexing, or satellite Bridge ICs (OpenBIC).
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Multi-host support allows a single BMC to manage two or more host systems from one firmware image. This is common in high-density server platforms such as twin-server chassis, multi-node sleds, and blade enclosures where dedicating a BMC per host is impractical due to cost, power, or space constraints.

In a multi-host OpenBMC deployment, the BMC communicates with each host over dedicated IPMB (Intelligent Platform Management Bus) links — one I2C bus per host — and maintains independent state machines, sensor namespaces, and Redfish resource trees for each host. The systemd service manager uses template units to instantiate per-host services, while D-Bus object paths are indexed by host number to keep each host's state isolated.

This guide walks you through the complete multi-host architecture: how IPMB bridges messages between the BMC and each host, how systemd template units and D-Bus object paths provide per-host isolation, how to configure your machine layer for N hosts, and how Redfish exposes each host as a separate ComputerSystem resource.

**Key concepts covered:**
- Single-BMC-to-N-host architecture over IPMB
- IPMB bridge daemon configuration (I2C bus assignment, address routing)
- Per-host state management with systemd template units
- D-Bus object path multiplexing (`/xyz/openbmc_project/state/host0`, `host1`, ...)
- Redfish ComputerSystem mapping for each host
- Yocto/BitBake configuration for multi-host builds

{: .warning }
Multi-host support requires careful hardware design. Each host needs a dedicated I2C bus for IPMB communication. Verify your baseboard schematic provides separate I2C controllers or mux channels for each host before implementing the software configuration.

{: .note }
Multi-host is distinct from multi-node MCTP/PLDM topologies. This guide covers two approaches: (1) IPMI-based multi-host where each host has a traditional IPMB link to the BMC, and (2) satellite processor (OpenBIC) multi-host where Bridge ICs act as local agents offloading the BMC. For PLDM-based multi-endpoint management, see the [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}).

---

## Architecture

### Multi-Host System Topology

A multi-host BMC manages N hosts through dedicated IPMB channels. Each host has its own I2C bus, power control GPIOs, and an independent state machine on the BMC side.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Multi-Host BMC Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                     BMC (AST2600)                        │  │
│   │                                                          │  │
│   │  ┌────────────┐  ┌────────────┐  ┌────────────┐          │  │
│   │  │ State Mgr  │  │ State Mgr  │  │ State Mgr  │  ...     │  │
│   │  │  (host0)   │  │  (host1)   │  │  (host2)   │          │  │
│   │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘          │  │
│   │        │               │               │                 │  │
│   │  ┌─────┴───────────────┴───────────────┴──────────────┐  │  │
│   │  │              D-Bus (phosphor-dbus)                 │  │  │
│   │  │  /xyz/openbmc_project/state/host0                  │  │  │
│   │  │  /xyz/openbmc_project/state/host1                  │  │  │
│   │  │  /xyz/openbmc_project/state/host2                  │  │  │
│   │  └─────┬───────────────┬───────────────┬──────────────┘  │  │
│   │        │               │               │                 │  │
│   │  ┌─────┴──────┐  ┌─────┴───────┐  ┌────┴───────┐         │  │
│   │  │ IPMB Bridge│  │ IPMB Bridge │  │ IPMB Bridge│         │  │
│   │  │  (I2C-1)   │  │  (I2C-2)    │  │  (I2C-3)   │         │  │
│   │  └─────┬──────┘  └─────┬───────┘  └─────┬──────┘         │  │
│   └────────┼───────────────┼────────────────┼────────────────┘  │
│            │               │                │                   │
│      ┌─────┴──────┐  ┌─────┴──────┐  ┌──────┴─────┐             │
│      │   Host 0   │  │   Host 1   │  │   Host 2   │             │
│      │ (CPU/BIOS) │  │ (CPU/BIOS) │  │ (CPU/BIOS) │             │
│      └────────────┘  └────────────┘  └────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### IPMB Communication Model

Each host communicates with the BMC over a dedicated I2C bus using the IPMB protocol. The BMC acts as the IPMB master (address 0x20) and each host baseboard management controller or satellite controller responds at a host-specific slave address.

```
┌─────────────────────────────────────────────────────────────────┐
│                  IPMB Message Flow                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   BMC (Master 0x20)                                             │
│    │                                                            │
│    ├── I2C Bus 1 ──── IPMB Channel 1 ──── Host 0 (Slave 0x70)   │
│    │                                                            │
│    ├── I2C Bus 2 ──── IPMB Channel 2 ──── Host 1 (Slave 0x72)   │
│    │                                                            │
│    ├── I2C Bus 3 ──── IPMB Channel 3 ──── Host 2 (Slave 0x74)   │
│    │                                                            │
│    └── I2C Bus 4 ──── IPMB Channel 4 ──── Host 3 (Slave 0x76)   │
│                                                                 │
│   IPMB Request Frame:                                           │
│   ┌────────┬────────┬──────┬──────┬────────┬─────────┬────────┐ │
│   │ rsSA   │ NetFn/ │ Chk1 │ rqSA │ rqSeq/ │ Command │ Data + │ │
│   │ (Slave)│ rsLUN  │      │(BMC) │ rqLUN  │         │  Chk2  │ │
│   └────────┴────────┴──────┴──────┴────────┴─────────┴────────┘ │
│                                                                 │
│   Key fields:                                                   │
│   ── rsSA:  Responder slave address (host-specific)             │
│   ── rqSA:  Requester slave address (BMC = 0x20)                │
│   ── NetFn: Network function (Chassis, Sensor, App, etc.)       │
│   ── Chk1/2: Header and data checksums                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### D-Bus Object Path Convention

Multi-host OpenBMC uses a numeric suffix on D-Bus object paths to identify each host. All phosphor services that are host-aware follow this naming convention.

| D-Bus Object Path | Purpose |
|-------------------|---------|
| `/xyz/openbmc_project/state/host0` | Host 0 power/boot state |
| `/xyz/openbmc_project/state/host1` | Host 1 power/boot state |
| `/xyz/openbmc_project/state/chassis0` | Chassis 0 power state |
| `/xyz/openbmc_project/state/chassis1` | Chassis 1 power state |
| `/xyz/openbmc_project/control/host0/boot` | Host 0 boot settings |
| `/xyz/openbmc_project/control/host1/boot` | Host 1 boot settings |
| `/xyz/openbmc_project/sensors/temperature/host0_cpu_temp` | Host 0 CPU temperature |
| `/xyz/openbmc_project/sensors/temperature/host1_cpu_temp` | Host 1 CPU temperature |
| `/xyz/openbmc_project/inventory/system/host0` | Host 0 inventory |
| `/xyz/openbmc_project/inventory/system/host1` | Host 1 inventory |

### Redfish Resource Mapping

Each host maps to a separate Redfish ComputerSystem resource. The BMC itself is exposed as a single Manager that manages all hosts.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Redfish Resource Tree                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  /redfish/v1/                                                   │
│  ├── Managers/                                                  │
│  │   └── bmc                          ← Single BMC manager      │
│  │       ├── ManagerType: "BMC"                                 │
│  │       └── Links/ManagerForServers:                           │
│  │           ├── /redfish/v1/Systems/host0                      │
│  │           ├── /redfish/v1/Systems/host1                      │
│  │           └── /redfish/v1/Systems/host2                      │
│  │                                                              │
│  ├── Systems/                                                   │
│  │   ├── host0                        ← Host 0 ComputerSystem   │
│  │   │   ├── PowerState: "On"                                   │
│  │   │   ├── Actions/ComputerSystem.Reset                       │
│  │   │   ├── Processors/                                        │
│  │   │   ├── Memory/                                            │
│  │   │   └── LogServices/                                       │
│  │   ├── host1                        ← Host 1 ComputerSystem   │
│  │   │   ├── PowerState: "Off"                                  │
│  │   │   ├── ...                                                │
│  │   └── host2                        ← Host 2 ComputerSystem   │
│  │       ├── ...                                                │
│  │                                                              │
│  └── Chassis/                                                   │
│      ├── chassis0                     ← Physical chassis 0      │
│      │   ├── Thermal/                                           │
│      │   ├── Power/                                             │
│      │   └── Links/ComputerSystems:                             │
│      │       └── /redfish/v1/Systems/host0                      │
│      └── chassis1                     ← Physical chassis 1      │
│          └── ...                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Key Dependencies

- **phosphor-state-manager**: Provides per-host state machines (host, chassis, BMC states)
- **ipmb-bridge / ipmbd**: Routes IPMI messages between the BMC and each host over I2C
- **phosphor-host-ipmid**: Handles IPMI commands, instantiated per host
- **bmcweb**: Serves Redfish with per-host ComputerSystem resources
- **phosphor-gpio-monitor**: Monitors per-host GPIO signals (power button, reset, etc.)

---

## Configuration

### Machine Configuration for Multi-Host

Define the number of hosts and IPMB bus assignments in your machine configuration.

```bitbake
# meta-mymachine/conf/machine/mymachine.conf

# Number of host instances (0-indexed: host0, host1, ..., hostN-1)
OBMC_HOST_INSTANCES = "0 1 2 3"

# Map each host to an I2C bus for IPMB communication
OBMC_HOST_IPMB_BUSSES = "1 2 3 4"

# IPMB slave addresses per host (7-bit format)
OBMC_HOST_IPMB_ADDRESSES = "0x70 0x72 0x74 0x76"

# Include multi-host support packages
OBMC_MACHINE_FEATURES += "obmc-host-state-mgmt obmc-chassis-state-mgmt"

# Enable per-host state manager instances
VIRTUAL-RUNTIME_obmc-host-state-manager = "phosphor-state-manager-host"
VIRTUAL-RUNTIME_obmc-chassis-state-manager = "phosphor-state-manager-chassis"
```

### IPMB Bridge Daemon Configuration

The IPMB bridge daemon (`ipmbd`) runs one instance per host, each bound to a specific I2C bus. Configuration is typically done through systemd template units.

#### ipmbd Service Template

```ini
# /lib/systemd/system/ipmbd@.service
[Unit]
Description=IPMB Bridge Daemon for host %i
After=sys-subsystem-i2c-devices-i2c\x2d%i.device
BindsTo=sys-subsystem-i2c-devices-i2c\x2d%i.device

[Service]
Type=simple
ExecStart=/usr/bin/ipmbd %i 0x20
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### Enable IPMB for Each Host

```bash
# Enable ipmbd for I2C buses 1-4 (corresponding to hosts 0-3)
systemctl enable ipmbd@1.service
systemctl enable ipmbd@2.service
systemctl enable ipmbd@3.service
systemctl enable ipmbd@4.service
```

### IPMB Channel Configuration

Define IPMB channels in the channel configuration JSON. Each channel maps to an IPMB bus and host instance.

```json
{
    "channels": [
        {
            "channel": 1,
            "type": "ipmb",
            "name": "IPMB_HOST0",
            "bus": 1,
            "slave_address": "0x70",
            "host_instance": 0
        },
        {
            "channel": 2,
            "type": "ipmb",
            "name": "IPMB_HOST1",
            "bus": 2,
            "slave_address": "0x72",
            "host_instance": 1
        },
        {
            "channel": 3,
            "type": "ipmb",
            "name": "IPMB_HOST2",
            "bus": 3,
            "slave_address": "0x74",
            "host_instance": 2
        },
        {
            "channel": 4,
            "type": "ipmb",
            "name": "IPMB_HOST3",
            "bus": 4,
            "slave_address": "0x76",
            "host_instance": 3
        }
    ]
}
```

### I2C Device Tree Configuration

Each IPMB bus requires an I2C controller in the device tree. On AST2600, assign dedicated I2C controllers for each host.

```dts
/* IPMB I2C buses for multi-host */
&i2c1 {
    status = "okay";
    /* IPMB to Host 0 */
    multi-master;
    ipmb@20 {
        compatible = "ipmb-dev";
        reg = <0x20>;
    };
};

&i2c2 {
    status = "okay";
    /* IPMB to Host 1 */
    multi-master;
    ipmb@20 {
        compatible = "ipmb-dev";
        reg = <0x20>;
    };
};

&i2c3 {
    status = "okay";
    /* IPMB to Host 2 */
    multi-master;
    ipmb@20 {
        compatible = "ipmb-dev";
        reg = <0x20>;
    };
};

&i2c4 {
    status = "okay";
    /* IPMB to Host 3 */
    multi-master;
    ipmb@20 {
        compatible = "ipmb-dev";
        reg = <0x20>;
    };
};
```

{: .tip }
The `multi-master` property enables I2C multi-master mode, which is required for IPMB because both the BMC and the host can initiate transactions on the same bus.

### Per-Host State Manager Configuration

The phosphor-state-manager uses systemd template units to create independent state machines per host.

#### Host State Template

```ini
# /lib/systemd/system/phosphor-host-state-manager@.service
[Unit]
Description=Phosphor Host State Manager for host %i
Wants=mapper-wait@-xyz-openbmc_project-state-host%i.service
After=mapper-wait@-xyz-openbmc_project-state-host%i.service

[Service]
Type=dbus
BusName=xyz.openbmc_project.State.Host%i
ExecStart=/usr/bin/phosphor-host-state-manager --host %i
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### Chassis State Template

```ini
# /lib/systemd/system/phosphor-chassis-state-manager@.service
[Unit]
Description=Phosphor Chassis State Manager for chassis %i

[Service]
Type=dbus
BusName=xyz.openbmc_project.State.Chassis%i
ExecStart=/usr/bin/phosphor-chassis-state-manager --chassis %i
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### Enable Per-Host Services

```bash
# Enable state managers for all hosts
for i in 0 1 2 3; do
    systemctl enable phosphor-host-state-manager@${i}.service
    systemctl enable phosphor-chassis-state-manager@${i}.service
done
```

### Build-Time Options

| Option | Default | Description |
|--------|---------|-------------|
| `OBMC_HOST_INSTANCES` | `"0"` | Space-separated list of host instance numbers |
| `OBMC_HOST_IPMB_BUSSES` | `"1"` | I2C bus numbers for IPMB, one per host |
| `OBMC_HOST_IPMB_ADDRESSES` | `"0x70"` | 7-bit I2C slave addresses for each host |
| `OBMC_CHASSIS_INSTANCES` | `"0"` | Chassis instance numbers (may differ from host count) |
| `OBMC_HOST_STATE_MANAGER_MULTI` | `"1"` | Set to number of hosts to enable multi-host state manager |

---

## Porting Guide

Follow these steps to enable multi-host support on your platform.

### Step 1: Prerequisites

Ensure you have:
- [ ] Dedicated I2C buses from the BMC to each host (one per host)
- [ ] Per-host GPIO signals for power control (power button, reset, etc.)
- [ ] A working single-host OpenBMC image for your platform
- [ ] Device tree source for your baseboard

### Step 2: Update Device Tree

Add I2C controller nodes for each IPMB bus and configure multi-master mode.

```dts
/* In your machine device tree overlay */
/* aspeed-bmc-mymachine.dts */

&i2c1 {
    status = "okay";
    multi-master;
    /* Host 0 IPMB */
};

&i2c2 {
    status = "okay";
    multi-master;
    /* Host 1 IPMB */
};

/* Add per-host power control GPIOs */
&gpio0 {
    host0-power-enable {
        gpio-hog;
        gpios = <ASPEED_GPIO(A, 0) GPIO_ACTIVE_HIGH>;
        output-low;
        line-name = "host0-power-enable";
    };

    host1-power-enable {
        gpio-hog;
        gpios = <ASPEED_GPIO(A, 1) GPIO_ACTIVE_HIGH>;
        output-low;
        line-name = "host1-power-enable";
    };
};
```

### Step 3: Configure Machine Layer

Update your machine configuration to declare host instances and IPMB mappings.

```bitbake
# meta-mymachine/conf/machine/mymachine.conf

OBMC_HOST_INSTANCES = "0 1"

# Map host instances to I2C buses
OBMC_HOST_IPMB_BUSSES = "1 2"
OBMC_HOST_IPMB_ADDRESSES = "0x70 0x72"

# Per-host power GPIO configuration
OBMC_POWER_GPIO_HOST0 = "host0-power-enable"
OBMC_POWER_GPIO_HOST1 = "host1-power-enable"
```

### Step 4: Create Systemd Target Dependencies

Define per-host boot targets so that services start in the correct order for each host.

```ini
# meta-mymachine/recipes-phosphor/state/files/host0-boot.target
[Unit]
Description=Host 0 Boot Target
Wants=ipmbd@1.service
Wants=phosphor-host-state-manager@0.service
Wants=phosphor-chassis-state-manager@0.service
After=ipmbd@1.service
```

```ini
# meta-mymachine/recipes-phosphor/state/files/host1-boot.target
[Unit]
Description=Host 1 Boot Target
Wants=ipmbd@2.service
Wants=phosphor-host-state-manager@1.service
Wants=phosphor-chassis-state-manager@1.service
After=ipmbd@2.service
```

### Step 5: Add IPMB Bridge Recipe Append

Create a bbappend to install per-host ipmbd service configurations.

```bitbake
# meta-mymachine/recipes-phosphor/ipmi/ipmb-bridge_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://ipmb-channels.json \
"

do_install:append() {
    install -d ${D}${datadir}/ipmb-bridge
    install -m 0644 ${WORKDIR}/ipmb-channels.json \
        ${D}${datadir}/ipmb-bridge/
}
```

### Step 6: Build and Verify

```bash
# Build the multi-host image
bitbake obmc-phosphor-image

# After flashing, verify all host state managers are running
systemctl status phosphor-host-state-manager@0
systemctl status phosphor-host-state-manager@1

# Verify IPMB bridges
systemctl status ipmbd@1
systemctl status ipmbd@2

# Check D-Bus objects
busctl tree xyz.openbmc_project.State.Host0
busctl tree xyz.openbmc_project.State.Host1
```

---

## Code Examples

### Example 1: Querying Per-Host State via D-Bus

```bash
# Get power state for each host
for i in 0 1 2 3; do
    echo "Host ${i} state:"
    busctl get-property xyz.openbmc_project.State.Host${i} \
        /xyz/openbmc_project/state/host${i} \
        xyz.openbmc_project.State.Host \
        CurrentHostState
done

# Example output:
# Host 0 state: s "xyz.openbmc_project.State.Host.HostState.Running"
# Host 1 state: s "xyz.openbmc_project.State.Host.HostState.Off"
# Host 2 state: s "xyz.openbmc_project.State.Host.HostState.Running"
# Host 3 state: s "xyz.openbmc_project.State.Host.HostState.Off"
```

### Example 2: Power Control via Redfish

```bash
# Power on Host 1
curl -k -u root:0penBmc -X POST \
    https://bmc-ip/redfish/v1/Systems/host1/Actions/ComputerSystem.Reset \
    -H "Content-Type: application/json" \
    -d '{"ResetType": "On"}'

# Graceful shutdown Host 0
curl -k -u root:0penBmc -X POST \
    https://bmc-ip/redfish/v1/Systems/host0/Actions/ComputerSystem.Reset \
    -H "Content-Type: application/json" \
    -d '{"ResetType": "GracefulShutdown"}'

# Get all systems
curl -k -u root:0penBmc \
    https://bmc-ip/redfish/v1/Systems/

# Example response (abbreviated):
# {
#     "@odata.id": "/redfish/v1/Systems",
#     "Members": [
#         {"@odata.id": "/redfish/v1/Systems/host0"},
#         {"@odata.id": "/redfish/v1/Systems/host1"},
#         {"@odata.id": "/redfish/v1/Systems/host2"},
#         {"@odata.id": "/redfish/v1/Systems/host3"}
#     ],
#     "Members@odata.count": 4
# }
```

### Example 3: Per-Host IPMB Communication

```bash
# Send an IPMI Get Device ID command to Host 0 via IPMB channel 1
ipmitool -I ipmb -H localhost -t 0x70 -b 1 raw 0x06 0x01

# Send the same command to Host 1 via IPMB channel 2
ipmitool -I ipmb -H localhost -t 0x72 -b 2 raw 0x06 0x01

# Get chassis status for Host 0
ipmitool -I ipmb -H localhost -t 0x70 -b 1 chassis status

# Get sensor list from Host 1
ipmitool -I ipmb -H localhost -t 0x72 -b 2 sdr list
```

### Example 4: Host State Monitor Script

```bash
#!/bin/bash
# monitor-hosts.sh - Monitor power state of all hosts
# See: docs/examples/multi-host/

HOSTS="0 1 2 3"
INTERVAL=5

while true; do
    clear
    echo "=== Multi-Host Status ($(date)) ==="
    echo ""
    for h in ${HOSTS}; do
        STATE=$(busctl get-property \
            xyz.openbmc_project.State.Host${h} \
            /xyz/openbmc_project/state/host${h} \
            xyz.openbmc_project.State.Host \
            CurrentHostState 2>/dev/null | awk '{print $2}' | tr -d '"')

        CHASSIS=$(busctl get-property \
            xyz.openbmc_project.State.Chassis${h} \
            /xyz/openbmc_project/state/chassis${h} \
            xyz.openbmc_project.State.Chassis \
            CurrentPowerState 2>/dev/null | awk '{print $2}' | tr -d '"')

        # Extract short state name
        HOST_SHORT="${STATE##*.}"
        CHASSIS_SHORT="${CHASSIS##*.}"

        printf "  Host %-2d : %-12s  Chassis: %-12s\n" \
            "${h}" "${HOST_SHORT:-Unknown}" "${CHASSIS_SHORT:-Unknown}"
    done
    echo ""
    echo "Refreshing every ${INTERVAL}s. Press Ctrl+C to stop."
    sleep ${INTERVAL}
done
```

### Example 5: Per-Host Sensor Namespace

```bash
# List sensors for a specific host
busctl tree xyz.openbmc_project.HostSensors${HOST_ID}

# Read Host 0 CPU temperature
busctl get-property xyz.openbmc_project.Sensor.Host0 \
    /xyz/openbmc_project/sensors/temperature/host0_cpu_temp \
    xyz.openbmc_project.Sensor.Value Value

# Read Host 1 DIMM temperature
busctl get-property xyz.openbmc_project.Sensor.Host1 \
    /xyz/openbmc_project/sensors/temperature/host1_dimm0_temp \
    xyz.openbmc_project.Sensor.Value Value

# Via Redfish - Host 0 thermal sensors
curl -k -u root:0penBmc \
    https://bmc-ip/redfish/v1/Chassis/chassis0/Thermal

# Via Redfish - Host 1 thermal sensors
curl -k -u root:0penBmc \
    https://bmc-ip/redfish/v1/Chassis/chassis1/Thermal
```

See working examples in the [examples/multi-host](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/multi-host) directory:

- `monitor-hosts.sh` - Monitor power state across all hosts
- `ipmb-health-check.sh` - Verify IPMB connectivity to each host
- `multi-host-power-cycle.sh` - Sequential power cycle all hosts
- `config/ipmb-channels.json` - IPMB channel configuration example
- `config/multi-host.conf` - Machine configuration snippet

---

## Satellite Processor Approach (OpenBIC)

An alternative to direct IPMB-per-host is using **satellite processors** — small Bridge ICs (BICs) placed on each server board that act as local BMC agents. The open-source [OpenBIC](https://github.com/facebook/OpenBIC) project provides firmware for these Bridge ICs, enabling a single BMC to manage many hosts by delegating per-host monitoring and control to dedicated satellite processors.

### What is a Bridge IC (BIC)?

A Bridge IC is a small microcontroller (typically an ASPEED AST1030) deployed on each server sled or server board. It runs OpenBIC firmware (based on Zephyr RTOS) and provides:

- **Local sensor monitoring** — reads host CPU temperatures, voltages, and power sensors directly, reducing I2C traffic to the BMC
- **Event logging** — captures and buffers host events locally before forwarding to the BMC
- **Host power sequencing** — manages local power-on/off sequences for its host
- **Firmware update agent** — handles local component firmware updates (BIOS, CPLD, etc.)
- **Protocol bridging** — translates between the host's eSPI/LPC interface and the BMC's management bus

The BIC acts as a local agent of the BMC, sharing the BMC's management burden in complex multi-host architectures.

### BIC vs Direct IPMB Architecture

| Aspect | Direct IPMB (Traditional) | Satellite BIC (OpenBIC) |
|--------|--------------------------|------------------------|
| **Host connection** | BMC connects directly to each host via I2C/IPMB | BIC on each sled connects to its host; BMC talks to BICs |
| **Scalability** | Limited by BMC I2C bus count | Scales to many hosts — each BIC handles its own host |
| **Sensor polling** | BMC polls all sensors for all hosts | BIC polls local sensors, BMC queries BIC for aggregated data |
| **Protocol** | IPMB (IPMI over I2C) | MCTP over I3C or SMBus, with PLDM for sensor/FRU data |
| **Failure isolation** | BMC I2C hang affects all hosts on that bus | BIC failure only affects its local host |
| **Hardware cost** | Lower (no extra IC) | Higher (one AST1030 per sled) |
| **Firmware complexity** | Simpler — single firmware image | Two firmware stacks: OpenBMC on BMC + OpenBIC on each BIC |
| **Example platforms** | Traditional twin-server boards | Meta Yosemite v3/v3.5/v4, OCP multi-node sleds |

### Satellite Processor Topology

```
┌──────────────────────────────────────────────────────────────────────┐
│              Satellite BIC Multi-Host Architecture                   │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐   │
│   │                    BMC (AST2600)                             │   │
│   │                                                              │   │
│   │  ┌──────────────┐  ┌──────────────┐                          │   │
│   │  │ pldmd        │  │ bmcweb       │                          │   │
│   │  │ (PLDM daemon)│  │ (Redfish)    │                          │   │
│   │  └──────┬───────┘  └──────────────┘                          │   │
│   │         │                                                    │   │
│   │  ┌──────┴───────┐                                            │   │
│   │  │ mctpd        │   MCTP endpoint discovery + routing        │   │
│   │  └──┬───┬───┬───┘                                            │   │
│   └─────┼───┼───┼────────────────────────────────────────────────┘   │
│         │   │   │   I3C / SMBus (MCTP transport)                     │
│    ┌────┘   │   └────┐                                               │
│    │        │        │                                               │
│  ┌─┴──────────┐   ┌──┴─────────┐  ┌────────────┐                     │
│  │ BIC 0      │   │ BIC 1      │  │ BIC 2      │  ...                │
│  │ (AST1030)  │   │ (AST1030)  │  │ (AST1030)  │                     │
│  │ OpenBIC FW │   │ OpenBIC FW │  │ OpenBIC FW │                     │
│  │            │   │            │  │            │                     │
│  │ ┌────────┐ │   │ ┌────────┐ │  │ ┌────────┐ │                     │
│  │ │Sensors │ │   │ │Sensors │ │  │ │Sensors │ │                     │
│  │ │Power   │ │   │ │Power   │ │  │ │Power   │ │                     │
│  │ │FW Upd  │ │   │ │FW Upd  │ │  │ │FW Upd  │ │                     │
│  │ └────────┘ │   │ └────────┘ │  │ └────────┘ │                     │
│  └─────┬──────┘   └─────┬──────┘  └─────┬──────┘                     │
│        │  eSPI          │  eSPI         │  eSPI                      │
│  ┌─────┴──────┐   ┌─────┴──────┐  ┌─────┴──────┐                     │
│  │  Host 0    │   │  Host 1    │  │  Host 2    │                     │
│  │ (CPU/BIOS) │   │ (CPU/BIOS) │  │ (CPU/BIOS) │                     │
│  └────────────┘   └────────────┘  └────────────┘                     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Communication Stack

In the BIC architecture, the BMC communicates with each Bridge IC using **MCTP** (Management Component Transport Protocol) over **I3C** or **SMBus**, with **PLDM** (Platform Level Data Model) as the application-layer protocol for sensor data, FRU information, and firmware updates.

```
┌─────────────────────────────────────────────────────────────────┐
│              BMC ←→ BIC Communication Stack                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   BMC Side                          BIC Side                    │
│   ─────────                         ────────                    │
│   ┌──────────────┐                  ┌──────────────┐            │
│   │ Redfish /    │                  │ Sensor       │            │
│   │ D-Bus apps   │                  │ Monitors     │            │
│   └──────┬───────┘                  └──────┬───────┘            │
│          │                                 │                    │
│   ┌──────┴───────┐                  ┌──────┴───────┐            │
│   │ pldmd        │  PLDM T2 (Sensor)│ PLDM         │            │
│   │              │◄── & FRU data ──►│ Responder    │            │
│   └──────┬───────┘                  └──────┬───────┘            │
│          │                                 │                    │
│   ┌──────┴───────┐                  ┌──────┴───────┐            │
│   │ mctpd        │  MCTP messages   │ MCTP         │            │
│   │              │◄────────────────►│ Service      │            │
│   └──────┬───────┘                  └──────┬───────┘            │
│          │                                 │                    │
│   ┌──────┴───────┐                  ┌──────┴───────┐            │
│   │ I3C / SMBus  │  Physical bus    │ I3C / SMBus  │            │
│   │ Controller   │◄────────────────►│ Controller   │            │
│   └──────────────┘                  └──────────────┘            │
│                                                                 │
│   MCTP Endpoint IDs (EIDs):                                     │
│   ── BMC:   0x08 (default)                                      │
│   ── BIC 0: 0x0A                                                │
│   ── BIC 1: 0x0C                                                │
│   ── BIC 2: 0x0E                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### PLDM Sensor Data Flow

Each BIC monitors local sensors and exposes them to the BMC via PLDM Type 2 (Monitoring and Control). The BMC's `pldmd` daemon discovers BIC sensors through Platform Descriptor Records (PDRs) and makes them available on D-Bus for bmcweb/Redfish.

```bash
# On the BMC — discover PLDM endpoints
pldmtool platform GetPDR -d 0   # List PDRs from terminus 0 (BIC 0)

# Read a sensor from a BIC via PLDM
pldmtool platform GetSensorReading -i <sensor_id> -t <terminus_id>

# Sensors from BICs appear on D-Bus like any other sensor
busctl get-property xyz.openbmc_project.PLDM \
    /xyz/openbmc_project/sensors/temperature/BIC_0_CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value
```

### OpenBIC Hardware: ASPEED AST1030

The [AST1030](https://www.aspeedtech.com/bic/) is ASPEED's purpose-built BIC chip:

| Feature | AST1030 |
|---------|---------|
| **CPU** | Arm Cortex-M4F |
| **Memory** | Internal flash and SRAM |
| **Host interface** | eSPI |
| **BMC interface** | I2C, I3C, SMBus |
| **USB** | USB 1.1 device |
| **RTOS** | Zephyr (via OpenBIC) |
| **Package** | 256-pin TFBGA (13mm x 13mm) |

### Reference Platform: Meta Yosemite v3.5

The [Yosemite v3.5](https://www.qemu.org/docs/master/system/arm/fby35.html) is a well-known OCP platform that uses the BIC architecture:

- **Baseboard**: AST2600 BMC running OpenBMC
- **4 server slots**: Each slot has an AST1030 BIC running OpenBIC
- **Form factor**: Sled that fits into a 40U chassis (3 sleds per chassis = 12 hosts per chassis)
- **QEMU support**: The `fby35` machine is emulated in QEMU for development

```bash
# Run Yosemite v3.5 in QEMU (BMC + one BIC)
qemu-system-arm -machine fby35 \
    -drive file=obmc-bmc.mtd,format=raw,if=mtd \
    -drive file=obmc-bic.mtd,format=raw,if=mtd \
    -nographic
```

### When to Choose Each Approach

**Use direct IPMB** when:
- You have 2-4 hosts in a simple twin-server or blade chassis
- Your platform uses traditional IPMI and you need backward compatibility
- Hardware cost is a primary constraint
- You already have a working single-host OpenBMC and just need to multiply it

**Use satellite BICs (OpenBIC)** when:
- You have 4+ hosts per BMC and need to scale management
- You need per-host failure isolation (a hung sensor poll on one host must not affect others)
- Your platform uses modern MCTP/PLDM protocols
- You want local firmware update capability on each sled
- You are building an OCP-compliant multi-node server platform

{: .tip }
The two approaches are not mutually exclusive. Some platforms use BICs for server sleds while still using IPMB for legacy expansion cards or chassis management controllers within the same system.

---

## Troubleshooting

### Issue: IPMB Bridge Fails to Start

**Symptom**: `ipmbd@1.service` fails with "No such device" or "Permission denied."

**Cause**: The I2C bus device node does not exist, or the device tree does not enable the I2C controller.

**Solution**:
1. Verify the I2C bus exists:
   ```bash
   ls /dev/i2c-*
   i2cdetect -l
   ```
2. Check the device tree enables the controller:
   ```bash
   # Look for I2C status in device tree
   cat /sys/firmware/devicetree/base/ahb/apb/i2c@1e78a080/status
   ```
3. Ensure `multi-master` is set in the device tree for IPMB buses.

### Issue: Host State Manager Shows "Unknown" State

**Symptom**: `busctl get-property` returns no value or an error for a host instance.

**Cause**: The state manager template unit is not instantiated for that host number, or `OBMC_HOST_INSTANCES` does not include the host.

**Solution**:
1. Check whether the service is running:
   ```bash
   systemctl status phosphor-host-state-manager@1
   ```
2. Verify `OBMC_HOST_INSTANCES` in your machine config includes the host.
3. Ensure the D-Bus service file matches the host instance number:
   ```bash
   busctl list | grep State.Host
   ```

### Issue: IPMB Messages Time Out

**Symptom**: IPMI commands sent over IPMB return timeout errors.

**Cause**: I2C bus contention, incorrect slave address, or the host-side IPMB responder is not running.

**Solution**:
1. Verify the target address is correct with `i2cdetect`:
   ```bash
   i2cdetect -y 1   # Check bus 1 for Host 0
   ```
2. Check for I2C errors in the kernel log:
   ```bash
   dmesg | grep -i i2c
   ```
3. Confirm the host-side IPMB controller is active (requires host console access).
4. Try reducing I2C clock speed if the bus length is long:
   ```dts
   &i2c1 {
       clock-frequency = <100000>;  /* 100 kHz standard mode */
   };
   ```

### Issue: Redfish Shows Only One System

**Symptom**: `/redfish/v1/Systems/` returns only `host0` even though multiple hosts are configured.

**Cause**: bmcweb only exposes ComputerSystem resources for hosts whose state managers are registered on D-Bus.

**Solution**:
1. Verify all host state managers are active:
   ```bash
   busctl list | grep State.Host
   ```
2. Check bmcweb logs for discovery issues:
   ```bash
   journalctl -u bmcweb -f
   ```
3. Ensure `OBMC_HOST_INSTANCES` is correctly set and the image was rebuilt with the multi-host configuration.

### Issue: Per-Host Sensors Not Appearing

**Symptom**: Sensors for Host 1 or higher-numbered hosts are missing from D-Bus and Redfish.

**Cause**: Sensor configuration files are not templated for multiple hosts, or the sensor daemon is not host-aware.

**Solution**:
1. Check sensor configuration includes per-host entries:
   ```bash
   ls /usr/share/entity-manager/configurations/ | grep -i host
   ```
2. Verify entity-manager detected the host:
   ```bash
   busctl tree xyz.openbmc_project.EntityManager
   ```
3. For IPMB-sourced sensors, confirm the IPMB bridge for that host is operational.

### Debug Commands

```bash
# Check all state manager services
systemctl list-units 'phosphor-*-state-manager@*'

# Check all IPMB bridge services
systemctl list-units 'ipmbd@*'

# View logs for a specific host state manager
journalctl -u phosphor-host-state-manager@1 -f

# View IPMB bridge logs
journalctl -u ipmbd@2 -f

# List all host-related D-Bus objects
busctl tree xyz.openbmc_project.State.Host0
busctl tree xyz.openbmc_project.State.Host1

# Monitor D-Bus signals for host state changes
busctl monitor xyz.openbmc_project.State.Host0

# Test I2C connectivity to a specific host
i2ctransfer -y 1 w1@0x70 0x00
```

---

## References

### Official Resources
- [phosphor-state-manager (GitHub)](https://github.com/openbmc/phosphor-state-manager) - Host and chassis state management
- [ipmb-bridge (GitHub)](https://github.com/openbmc/ipmbbridge) - IPMB message routing daemon
- [phosphor-host-ipmid (GitHub)](https://github.com/openbmc/phosphor-host-ipmid) - Host-side IPMI daemon
- [bmcweb (GitHub)](https://github.com/openbmc/bmcweb) - Redfish/REST API server
- [D-Bus Interface Definitions](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/State) - State interface YAML definitions

### OpenBIC / Satellite Processor Resources
- [OpenBIC (GitHub)](https://github.com/facebook/OpenBIC) - Open-source Bridge IC firmware framework
- [OpenBIC Documentation](https://facebook.github.io/OpenBIC/) - API and MCTP service documentation
- [ASPEED BIC Products](https://www.aspeedtech.com/bic/) - AST1030/AST1035 Bridge IC hardware
- [Yosemite v3.5 QEMU Emulation](https://www.qemu.org/docs/master/system/arm/fby35.html) - BMC + BIC emulation for development

### Related Guides
- [MCTP & PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) - Alternative multi-endpoint management via PLDM
- [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) - Per-host event logging and SEL

### External Documentation
- [IPMI Specification v2.0](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-second-gen-interface-spec-v2-rev1-1.html) - IPMB protocol specification
- [DMTF Redfish Specification](https://www.dmtf.org/standards/redfish) - ComputerSystem and Manager resource definitions
- [systemd Template Units](https://www.freedesktop.org/software/systemd/man/systemd.unit.html) - Template unit documentation (`@.service`)

---

{: .note }
**Tested on**: OpenBMC master branch with AST2600-EVB, dual-host configuration. QEMU can simulate the D-Bus and systemd aspects but does not provide physical IPMB I2C buses. Use QEMU for state manager and Redfish validation; use hardware for end-to-end IPMB testing.
