---
layout: default
title: AMD Debug & Management Guide
parent: Advanced Topics
nav_order: 5
difficulty: advanced
prerequisites:
  - mctp-pldm-guide
  - openbmc-overview
---

# AMD Debug & Management Guide
{: .no_toc }

Configure AMD EPYC system management and debug capabilities on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

AMD EPYC platforms provide system management and debug capabilities through **APML (Advanced Platform Management Link)** and **HDT (Hardware Debug Tool)**. This guide covers the BMC integration for AMD server platforms.

```
+----------------------------------------------------------------------+
|                  AMD Platform Management Architecture                |
+----------------------------------------------------------------------+
|                                                                      |
|  +-----------------------------------------------------------------+ |
|  |                       BMC Applications                          | |
|  |                                                                 | |
|  |   +-------------+  +-------------+  +-------------+             | |
|  |   | Telemetry   |  | RAS/Error   |  | Power Mgmt  |             | |
|  |   | Monitoring  |  | Handling    |  | Control     |             | |
|  |   +------+------+  +------+------+  +------+------+             | |
|  +---------+-----------------+----------------+--------------------+ |
|            |                 |                |                      |
|  +---------+-----------------+----------------+--------------------+ |
|  |                      APML Library                               | |
|  |            (apml_sbrmi / apml_sbtsi drivers)                    | |
|  +---------+-----------------+----------------+--------------------+ |
|            |                 |                |                      |
|  +---------+-----------------+----------------+--------------------+ |
|  |                    I2C / I3C Bus                                | |
|  +-----------------------------------------------------------------+ |
|            |                                                         |
|  +---------+-------------------------------------------------------+ |
|  |                    AMD EPYC Processor                           | |
|  |                                                                 | |
|  |   +-------------+  +-------------+  +-------------+             | |
|  |   | SB-RMI      |  | SB-TSI      |  | HDT Port    |             | |
|  |   | (Remote     |  | (Thermal    |  | (Hardware   |             | |
|  |   |  Mgmt I/F)  |  |  Sensor)    |  |  Debug)     |             | |
|  |   +-------------+  +-------------+  +-------------+             | |
|  +-----------------------------------------------------------------+ |
+----------------------------------------------------------------------+
```

---

## AMD Management Interfaces

### SB-RMI (Sideband Remote Management Interface)

Provides system management commands:

| Function | Description |
|----------|-------------|
| Power Management | RAPL power limits, throttling |
| RAS | Machine check, error reporting |
| Mailbox Commands | CPU configuration, CPUID |
| Performance | Core boost, C-states |

### SB-TSI (Sideband Thermal Sensor Interface)

Provides thermal monitoring:

| Function | Description |
|----------|-------------|
| CPU Temperature | Die temperature reading |
| Thermal Alerts | High/low temperature thresholds |
| Thermal Throttling | PROCHOT status |

### HDT (Hardware Debug Tool)

Low-level debug access (requires special hardware/NDA):

| Function | Description |
|----------|-------------|
| JTAG Access | CPU debug via JTAG chain |
| Run Control | Halt, step, breakpoints |
| Register Access | MSR, GPR access |
| Trace | Instruction trace |

---

## APML Setup

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include APML support
IMAGE_INSTALL:append = " \
    apml-modules \
    apml-library \
    esmi-oob-library \
"

# Kernel configuration
KERNEL_MODULE_AUTOLOAD:append = " apml_sbrmi apml_sbtsi"
```

### Kernel Modules

```bash
# Load APML modules
modprobe apml_sbrmi
modprobe apml_sbtsi

# Verify modules loaded
lsmod | grep apml

# Check I2C devices
i2cdetect -l
i2cdetect -y <bus>  # Find SB-RMI/SB-TSI addresses
```

### Device Tree Configuration

```dts
&i2c3 {
    status = "okay";

    /* SB-TSI - Thermal sensor */
    sbtsi@4c {
        compatible = "amd,sbtsi";
        reg = <0x4c>;
    };

    /* SB-RMI - Remote management */
    sbrmi@3c {
        compatible = "amd,sbrmi";
        reg = <0x3c>;
    };
};
```

---

## APML Library Usage

### Installation

```bash
# Check APML library
ls /usr/lib/libapml*

# Check APML tools
which esmi_oob_tool
```

### Reading CPU Temperature

```bash
# Via hwmon (SB-TSI driver)
cat /sys/class/hwmon/hwmon*/temp1_input

# Via APML library tool
esmi_oob_tool -s 0 --showtemprange
```

### Power Management

```bash
# Read current power
esmi_oob_tool -s 0 --showpower

# Read power limit
esmi_oob_tool -s 0 --showpowerlimit

# Set power limit (in milliwatts)
esmi_oob_tool -s 0 --setpowerlimit 200000

# Read TDP
esmi_oob_tool -s 0 --showtdp
```

### RAS (Reliability, Availability, Serviceability)

```bash
# Read MCA (Machine Check Architecture) status
esmi_oob_tool -s 0 --showmcastatus

# Read DIMM temperature
esmi_oob_tool -s 0 --showdimmtemp

# Read DIMM power
esmi_oob_tool -s 0 --showdimmpower

# Read DIMM thermal sensor
esmi_oob_tool -s 0 --showdimmthermal
```

### Mailbox Commands

```bash
# Read CPUID
esmi_oob_tool -s 0 --showcpuid

# Read processor info
esmi_oob_tool -s 0 --showprocinfo

# Read boost limit
esmi_oob_tool -s 0 --showboostlimit

# Set boost limit per core
esmi_oob_tool -s 0 --setboostlimit <core> <limit>
```

---

## D-Bus Integration

### Sensor Integration

APML sensors integrate with OpenBMC's sensor framework:

```bash
# Temperature sensors from SB-TSI appear in D-Bus
busctl tree xyz.openbmc_project.HwmonTempSensor

# Example: CPU temperature
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU0_Temp \
    xyz.openbmc_project.Sensor.Value Value
```

### Power Monitoring

```bash
# Power sensors via APML
busctl tree xyz.openbmc_project.Sensor

# Socket power reading
busctl get-property xyz.openbmc_project.Sensor \
    /xyz/openbmc_project/sensors/power/CPU0_Power \
    xyz.openbmc_project.Sensor.Value Value
```

---

## AMD OpenBMC Platform

### AMDESE OpenBMC

AMD maintains an OpenBMC distribution for EPYC platforms:

```bash
# Clone AMD's OpenBMC
git clone https://github.com/AMDESE/OpenBMC.git

# Build for Genoa platform
cd OpenBMC
. setup onyx  # or other platform
bitbake obmc-phosphor-image
```

### Supported Platforms

| Platform | Codename | Socket |
|----------|----------|--------|
| Onyx | Genoa | SP5 |
| Quartz | Genoa | SP5 |
| Ruby | Turin | SP5 |
| Chalupa | Genoa | SP5 |

---

## HDT Debug Access

{: .warning }
HDT provides deep hardware access. Full documentation requires AMD NDA. Use only in controlled debug environments.

### HDT Overview

HDT (Hardware Debug Tool) is AMD's JTAG-based debug interface:

- Accessed via dedicated debug header or BMC mux
- Requires specialized debug tools (AMD HDT software or third-party)
- Provides run-control (halt, step, breakpoints)
- Full register and memory access

### BMC JTAG Mux

Some platforms support JTAG muxing through BMC:

```bash
# Check for JTAG mux support
cat /sys/kernel/debug/gpio | grep -i jtag

# JTAG mux control (platform-specific)
gpioset gpiochip0 <jtag_mux_gpio>=1  # Route JTAG to BMC
```

### Commercial Solutions

For at-scale debug, commercial tools provide BMC-embedded debug:

- ASSET InterTech ScanWorks Embedded Diagnostics (SED)
- Lauterbach TRACE32 with remote access
- AMD HDT software (under NDA)

---

## Crash Dump Collection

### RAS Error Logging

```bash
# Machine Check errors are logged to SEL
ipmitool sel list | grep -i "Machine Check"

# View via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/EventLog/Entries
```

### BERT (Boot Error Record Table)

```bash
# BERT records are available via ACPI
cat /sys/firmware/acpi/tables/BERT

# Decoded in system logs
dmesg | grep -i "BERT"
journalctl | grep -i "hardware error"
```

### Collecting Debug Data

```bash
# Collect system state dump
dreport -d /tmp/debug -n amd_debug -t user

# Include APML data
esmi_oob_tool -s 0 --showallinfo > /tmp/apml_state.txt

# Read MCA banks
esmi_oob_tool -s 0 --showmcastatus > /tmp/mca_status.txt
```

---

## Troubleshooting

### APML Not Working

```bash
# Check I2C bus connectivity
i2cdetect -y 3  # Replace with correct bus

# Verify kernel modules
lsmod | grep apml

# Check dmesg for errors
dmesg | grep -i "sbrmi\|sbtsi\|apml"

# Verify device nodes
ls -la /dev/sbrmi* /dev/sbtsi*
```

### Temperature Reading Fails

```bash
# Check hwmon path
ls /sys/class/hwmon/

# Find correct hwmon device
for h in /sys/class/hwmon/hwmon*; do
    name=$(cat $h/name 2>/dev/null)
    echo "$h: $name"
done

# Read directly
cat /sys/class/hwmon/hwmon<N>/temp1_input
```

### Command Timeouts

```bash
# APML commands may timeout under heavy load
# Increase timeout in library calls

# Check SMBus errors
dmesg | grep -i "i2c\|smbus"

# Retry with delay
sleep 1 && esmi_oob_tool -s 0 --showpower
```

### Permission Issues

```bash
# APML requires root or proper group membership
ls -la /dev/sbrmi0 /dev/sbtsi0

# Add user to appropriate group
usermod -aG i2c <username>
```

---

## Security Considerations

### Access Control

```bash
# Restrict APML access to administrators only
chmod 600 /dev/sbrmi* /dev/sbtsi*

# Use D-Bus policy for access control
# /etc/dbus-1/system.d/apml.conf
```

### Audit Logging

```bash
# Log APML access
# Integrate with phosphor-logging for audit trail
```

### Production Recommendations

- Disable HDT access in production (via fuses or GPIO)
- Restrict APML to essential operations
- Monitor for anomalous power/thermal changes
- Log all RAS events

---

## References

- [AMD APML Modules (GitHub)](https://github.com/amd/apml_modules) - Kernel drivers for SB-RMI/SB-TSI
- [AMD E-SMI In-Band Library (GitHub)](https://github.com/amd/esmi_ib_library) - In-band system management
- [AMD E-SMS APML Library](https://www.amd.com/en/developer/e-sms/apml-library.html) - Out-of-band APML library
- [AMDESE OpenBMC (GitHub)](https://github.com/AMDESE/OpenBMC) - AMD's OpenBMC distribution for EPYC
- [AMD E-SMS Developer Resources](https://www.amd.com/en/developer/e-sms.html) - EPYC System Management Software
- [AMD Technical Documentation Portal](https://www.amd.com/en/search/documentation/hub.html) - Official AMD documentation

---

{: .note }
**Platform**: AMD EPYC 7002 (Rome), 7003 (Milan), 9004 (Genoa), and newer platforms. APML requires Family 17h (Zen) or later processors.
