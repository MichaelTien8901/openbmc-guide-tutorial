---
layout: default
title: Intel ASD/ACD Guide
parent: Advanced Topics
nav_order: 4
difficulty: advanced
prerequisites:
  - mctp-pldm-guide
  - ipmi-guide
---

# Intel ASD/ACD Guide
{: .no_toc }

Configure Intel At-Scale Debug and Autonomous Crash Dump on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**ASD (At-Scale Debug)** and **ACD (Autonomous Crash Dump)** are Intel technologies for remote CPU debugging and crash analysis on Intel Xeon server platforms.

```
+------------------------------------------------------------------------+
|                    Intel Debug Architecture                            |
+------------------------------------------------------------------------+
|                                                                        |
|  +-------------------------------------------------------------------+ |
|  |                      Debug Client (Host)                          | |
|  |                                                                   | |
|  |   +------------------+  +------------------+  +----------------+  | |
|  |   | Intel System     |  | ITP-XDP          |  | Crash Analyzer |  | |
|  |   | Debugger (ISD)   |  | (In-Target Probe)|  | Tool           |  | |
|  |   +--------+---------+  +--------+---------+  +-------+--------+  | |
|  +------------|---------------------|--------------------|-----------+ |
|               |                     |                    |             |
|               v                     v                    v             |
|  +-------------------------------------------------------------------+ |
|  |                         Network (TCP/IP)                          | |
|  |                    Port 5123 (ASD) / HTTPS (Redfish)              | |
|  +----------------------------+--------------------------------------+ |
|                               |                                        |
|  +----------------------------v--------------------------------------+ |
|  |                            BMC                                    | |
|  |                                                                   | |
|  |   +------------------+     +------------------+                   | |
|  |   |       ASD        |     |    Crashdump     |                   | |
|  |   |     Daemon       |     |     Service      |                   | |
|  |   +--------+---------+     +--------+---------+                   | |
|  |            |                        |                             | |
|  |   +--------v------------------------v---------+                   | |
|  |   |              JTAG Handler                 |                   | |
|  |   |         (jtag_handler.c)                  |                   | |
|  |   +--------+----------------------------------+                   | |
|  |            |                                                      | |
|  |   +--------v----------------------------------+                   | |
|  |   |           PECI Interface                  |                   | |
|  |   |    (Platform Environment Control I/F)     |                   | |
|  |   +--------+----------------------------------+                   | |
|  +------------|----------------------------------------------------- + |
|               |                                                        |
|  +------------v------------------------------------------------------+ |
|  |                     Intel Xeon CPU(s)                             | |
|  |                                                                   | |
|  |   +------------------+  +------------------+  +----------------+  | |
|  |   |   XDP Port       |  |  JTAG TAP        |  |  MCA Banks     |  | |
|  |   | (Debug Port)     |  |  Controller      |  |  (Error Regs)  |  | |
|  |   +------------------+  +------------------+  +----------------+  | |
|  +-------------------------------------------------------------------+ |
+------------------------------------------------------------------------+
```

---

## ASD (At-Scale Debug)

### What is ASD?

At-Scale Debug provides remote JTAG-like access to Intel CPUs through the BMC, enabling:

- **Remote debugging** without physical access to the server
- **JTAG chain access** to CPU cores, uncore, and PCH
- **Run control** (halt, step, breakpoints)
- **Register access** (MSRs, GPRs, control registers)
- **Memory access** through the CPU debug interface

### ASD Architecture

```
+-------------------------------------------------------------------+
|                        ASD Components                             |
+-------------------------------------------------------------------+
|                                                                   |
|  Debug Host                           BMC                         |
|  +----------------+                   +------------------------+  |
|  | OpenIPC/ISD    |                   |        ASD Daemon      |  |
|  |                |    TCP:5123       |                        |  |
|  | +------------+ |  +------------>   | +--------------------+ |  |
|  | | ASD Client | |                   | | Message Handler    | |  |
|  | +------------+ |                   | +--------------------+ |  |
|  |                |                   |          |             |  |
|  +----------------+                   | +--------v-----------+ |  |
|                                       | | JTAG Handler       | |  |
|                                       | | - Chain discovery  | |  |
|                                       | | - TAP state machine| |  |
|                                       | | - IR/DR shifting   | |  |
|                                       | +--------------------+ |  |
|                                       |          |             |  |
|                                       | +--------v-----------+ |  |
|                                       | | Target Handler     | |  |
|                                       | | - XDP interface    | |  |
|                                       | | - GPIO control     | |  |
|                                       | +--------------------+ |  |
|                                       +------------------------+  |
+-------------------------------------------------------------------+
```

### Build Configuration

```bitbake
# recipes-phosphor/debug/asd.bb or local.conf

# Include ASD daemon
IMAGE_INSTALL:append = " asd"

# ASD build options
EXTRA_OEMESON:pn-asd = " \
    -Djtag-legacy-driver=disabled \
    -Dsafe-mode=enabled \
"
```

### Meson Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `jtag-legacy-driver` | disabled | Use legacy JTAG driver |
| `safe-mode` | enabled | Enable safe mode protections |
| `i2c-debug` | disabled | Enable I2C debug messages |
| `i3c-debug` | disabled | Enable I3C debug messages |

### GPIO Configuration

ASD requires specific GPIO pins for JTAG and control signals:

```json
// /usr/share/asd/pin_config.json
{
    "Name": "MyPlatform",
    "Platform": {
        "jtag": {
            "tck": {"pin": "GPIOA0", "type": "gpio"},
            "tdi": {"pin": "GPIOA1", "type": "gpio"},
            "tdo": {"pin": "GPIOA2", "type": "gpio"},
            "tms": {"pin": "GPIOA3", "type": "gpio"}
        },
        "target": {
            "xdp_present": {"pin": "GPIOB0", "type": "gpio"},
            "debug_enable": {"pin": "GPIOB1", "type": "gpio"},
            "preq": {"pin": "GPIOB2", "type": "gpio"},
            "prdy": {"pin": "GPIOB3", "type": "gpio"},
            "reset": {"pin": "GPIOB4", "type": "gpio"}
        }
    }
}
```

### JTAG Chain Configuration

```json
// /usr/share/asd/jtag_config.json
{
    "JTAGChain": {
        "devices": [
            {
                "name": "CPU0",
                "idcode": "0x0A046101",
                "ir_length": 11,
                "type": "processor"
            },
            {
                "name": "PCH",
                "idcode": "0x1B0A0101",
                "ir_length": 8,
                "type": "pch"
            }
        ]
    }
}
```

### Service Management

```bash
# Check ASD service status
systemctl status asd

# Start ASD daemon
systemctl start asd

# Enable at boot
systemctl enable asd

# View logs
journalctl -u asd -f

# Check listening port
ss -tlnp | grep 5123
```

### ASD Protocol Messages

| Message Type | Description |
|--------------|-------------|
| `AGENT_CONTROL` | Control commands (reset, init) |
| `JTAG_CHAIN` | JTAG chain operations |
| `I2C_MSG` | I2C master transactions |
| `GPIO_MSG` | GPIO read/write |
| `REMOTE_DEBUG` | Remote debug enable/disable |

### Connecting with Debug Tools

```bash
# On debug host, using OpenIPC/ISD:
# 1. Configure target connection
#    - IP: <BMC_IP>
#    - Port: 5123
#    - Auth: BMC credentials

# 2. Connect and discover JTAG chain
# 3. Select target device (CPU core)
# 4. Begin debugging session
```

### XDP (eXtended Debug Port) Interface

XDP provides enhanced debug access:

```
XDP Signals:
+----------+----------------------------------+
| Signal   | Description                      |
+----------+----------------------------------+
| PREQ#    | Probe Request (BMC -> CPU)       |
| PRDY#    | Probe Ready (CPU -> BMC)         |
| RESET#   | Platform Reset control           |
| TCK      | JTAG Test Clock                  |
| TMS      | JTAG Test Mode Select            |
| TDI      | JTAG Test Data In                |
| TDO      | JTAG Test Data Out               |
| TRST#    | JTAG Test Reset                  |
+----------+----------------------------------+
```

### ASD D-Bus Interface

```bash
# ASD exposes configuration via D-Bus
busctl tree xyz.openbmc_project.ASD

# Get ASD status
busctl get-property xyz.openbmc_project.ASD \
    /xyz/openbmc_project/asd \
    xyz.openbmc_project.ASD.Server \
    Status

# Enable/disable remote debug
busctl set-property xyz.openbmc_project.ASD \
    /xyz/openbmc_project/asd \
    xyz.openbmc_project.ASD.Server \
    RemoteDebugEnabled b true
```

---

## ACD (Autonomous Crash Dump)

### What is ACD?

Autonomous Crash Dump automatically collects CPU diagnostic data when critical errors occur:

- **Machine Check Exceptions (MCE)** capture
- **CPU register state** preservation
- **Memory controller errors** logging
- **PCIe errors** collection
- **Uncore state** dump

### Crash Dump Architecture

```
+-------------------------------------------------------------------+
|                   Crash Dump Collection Flow                      |
+-------------------------------------------------------------------+
|                                                                   |
|  1. Error Occurs                                                  |
|     +------------------+                                          |
|     | CPU Asserts      |                                          |
|     | CATERR# / IERR#  |                                          |
|     +--------+---------+                                          |
|              |                                                    |
|  2. BMC Detects Error                                             |
|     +--------v---------+                                          |
|     | GPIO Interrupt   |                                          |
|     | Handler          |                                          |
|     +--------+---------+                                          |
|              |                                                    |
|  3. Trigger Collection                                            |
|     +--------v---------+                                          |
|     | Crashdump        |                                          |
|     | Service          |                                          |
|     +--------+---------+                                          |
|              |                                                    |
|  4. Collect Data via PECI                                         |
|     +--------v---------+     +------------------+                 |
|     | PECI Commands    |---->| CPU MCA Banks    |                 |
|     | - RdPkgConfig    |     | - MC0-MCn        |                 |
|     | - RdIAMSR        |     | - Uncore MSRs    |                 |
|     | - CrashDump      |     | - Core State     |                 |
|     +--------+---------+     +------------------+                 |
|              |                                                    |
|  5. Store & Expose                                                |
|     +--------v---------+                                          |
|     | JSON Storage     |                                          |
|     | /var/lib/        |                                          |
|     | crashdump/       |                                          |
|     +--------+---------+                                          |
|              |                                                    |
|     +--------v---------+                                          |
|     | Redfish API      |                                          |
|     | LogService       |                                          |
|     +------------------+                                          |
+-------------------------------------------------------------------+
```

### Build Configuration

```bitbake
# Include crashdump service
IMAGE_INSTALL:append = " crashdump"

# Crashdump build options
EXTRA_OEMESON:pn-crashdump = " \
    -Dtests=disabled \
    -Dcrashdump-x86=enabled \
"
```

### Crash Dump Triggers

| Trigger | Signal | Description |
|---------|--------|-------------|
| CATERR# | GPIO | Catastrophic Error |
| IERR# | GPIO | Internal Error |
| MCERR# | GPIO | Machine Check Error |
| ERR2# | GPIO | Error Signal 2 |
| Manual | Redfish/IPMI | User-initiated collection |

### GPIO Configuration for Error Detection

```json
// Entity Manager configuration
{
    "Name": "CrashDump Triggers",
    "Type": "GPIO",
    "Exposes": [
        {
            "Name": "CATERR",
            "Type": "gpio",
            "Index": 45,
            "Polarity": "Low",
            "Direction": "Input"
        },
        {
            "Name": "ERR2",
            "Type": "gpio",
            "Index": 46,
            "Polarity": "Low",
            "Direction": "Input"
        }
    ]
}
```

### PECI Interface

PECI (Platform Environment Control Interface) is used to collect crash data:

```bash
# PECI commands used by crashdump:

# Read Package Config
peci_cmds RdPkgConfig <address> <index> <parameter>

# Read IA MSR
peci_cmds RdIAMSR <address> <thread> <msr_address>

# Crashdump command
peci_cmds Crashdump <address> <command> <param>
```

### Crash Dump Data Sections

| Section | Content |
|---------|---------|
| `metadata` | Timestamp, trigger, platform info |
| `MCA` | Machine Check Architecture banks |
| `uncore` | Uncore MSRs and registers |
| `TOR` | Transaction Outstanding Registers |
| `PM_Info` | Power management state |
| `address_map` | Memory address mapping |
| `big_core` | CPU core registers |
| `crashlog` | Hardware crash log |

### Manual Crash Dump Collection

#### Via Redfish

```bash
# Trigger crash dump collection
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"DiagnosticDataType": "OEM", "OEMDiagnosticDataType": "OnDemand"}' \
    https://localhost/redfish/v1/Systems/system/LogServices/Crashdump/Actions/LogService.CollectDiagnosticData

# List collected dumps
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/Crashdump/Entries

# Get specific dump
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/Crashdump/Entries/1

# Download raw dump data
curl -k -u root:0penBmc -o crashdump.json \
    "https://localhost/redfish/v1/Systems/system/LogServices/Crashdump/Entries/1/attachment"
```

#### Via IPMI

```bash
# Trigger crash dump (Intel OEM command)
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc \
    raw 0x30 0x74  # Intel OEM crashdump trigger

# Get crash dump status
ipmitool -I lanplus -H <bmc-ip> -U root -P 0penBmc \
    raw 0x30 0x75  # Intel OEM crashdump status
```

### Crash Dump JSON Format

```json
{
    "crash_data": {
        "METADATA": {
            "timestamp": "2024-01-15T10:30:45Z",
            "trigger_type": "CATERR",
            "platform": "Intel Xeon 4th Gen",
            "cpu_count": 2
        },
        "CPU0": {
            "MCA": {
                "MC0_CTL": "0x0000000000000001",
                "MC0_STATUS": "0xBE00000000800400",
                "MC0_ADDR": "0x000000007F400000",
                "MC0_MISC": "0x0000000000000000",
                "MC0_CTL2": "0x0000000000000001"
            },
            "uncore": {
                "UNCORE_MC0_STATUS": "0x0000000000000000",
                "UNCORE_CHA0_STATUS": "0x0000000000000000"
            },
            "TOR": {
                "TOR_0_SAD": "0x0000000000000000",
                "TOR_0_TAD": "0x0000000000000000"
            }
        },
        "CPU1": {
            "MCA": {
                "...": "..."
            }
        }
    }
}
```

### Analyzing Crash Dumps

```bash
# Use Intel Crash Analyzer Tool (proprietary)
# Or parse JSON manually:

# Extract MCA status
cat crashdump.json | jq '.crash_data.CPU0.MCA.MC0_STATUS'

# Check for valid error
# Bit 63 (VAL) = 1 indicates valid error
# Bit 61 (UC) = 1 indicates uncorrected error
# Bit 60 (EN) = 1 indicates error reporting enabled

# Decode MCACOD (bits 15:0) for error type
cat crashdump.json | jq -r '.crash_data.CPU0.MCA | to_entries[] |
    select(.key | endswith("_STATUS")) |
    "\(.key): \(.value)"'
```

### Storage Location

```bash
# Crash dumps stored at:
ls /var/lib/crashdump/

# Format: crashdump_<timestamp>.json
# Example: crashdump_20240115_103045.json

# Check available space
df -h /var/lib/crashdump/

# Cleanup old dumps
# Managed by crashdump service based on retention policy
```

### D-Bus Interface

```bash
# Crashdump D-Bus service
busctl tree xyz.openbmc_project.CrashDump

# Get last crash dump status
busctl get-property xyz.openbmc_project.CrashDump \
    /xyz/openbmc_project/crashdump \
    xyz.openbmc_project.CrashDump.Manager \
    LastCrashDumpTime

# Trigger collection via D-Bus
busctl call xyz.openbmc_project.CrashDump \
    /xyz/openbmc_project/crashdump \
    xyz.openbmc_project.CrashDump.Manager \
    GenerateCrashDump s "OnDemand"
```

---

## Integration with Intel Tools

### Intel System Debugger (ISD)

```
Prerequisites:
- Intel System Studio or standalone ISD
- Network connectivity to BMC
- BMC credentials with debug privileges

Connection Steps:
1. Launch Intel System Debugger
2. Create new target connection:
   - Type: At-Scale Debug
   - Host: <BMC_IP>
   - Port: 5123
3. Authenticate with BMC credentials
4. Discover JTAG chain
5. Connect to CPU target
```

### OpenIPC Configuration

```
# OpenIPC is part of Intel System Studio
# Configuration file: openipc.cfg

[connection]
type = asd
host = 192.168.1.100
port = 5123
username = root
password = 0penBmc

[target]
cpu_type = SPR  # Sapphire Rapids
num_cpus = 2

[debug]
log_level = info
```

---

## Security Considerations

{: .warning }
ASD provides deep system access equivalent to physical JTAG. Implement strict security controls.

### Access Control

```bash
# Restrict ASD access to specific users
# Configure via Redfish AccountService

# Create debug-only user
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "UserName": "debuguser",
        "Password": "SecureDebugPass123!",
        "RoleId": "Administrator"
    }' \
    https://localhost/redfish/v1/AccountService/Accounts
```

### Network Security

```bash
# Restrict ASD port access via firewall
iptables -A INPUT -p tcp --dport 5123 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 5123 -j DROP

# Use VPN or isolated management network for debug access
```

### Audit Logging

```bash
# Enable debug access logging
# All ASD connections logged to journal

# View ASD access logs
journalctl -u asd | grep -i "connection\|auth"

# Integrate with SEL
# ASD events appear in System Event Log
ipmitool sel list | grep -i debug
```

### Production Recommendations

| Setting | Development | Production |
|---------|-------------|------------|
| ASD Enabled | Yes | No (disable) |
| Debug Port | Open | Blocked |
| Crashdump | Enabled | Enabled |
| Auto-collection | Enabled | Enabled |
| Retention | 30 days | 7 days |

### Disabling ASD in Production

```bash
# Stop and disable ASD service
systemctl stop asd
systemctl disable asd

# Or remove from build
# IMAGE_INSTALL:remove = "asd"

# Verify disabled
systemctl status asd
ss -tlnp | grep 5123  # Should show nothing
```

---

## Troubleshooting

### ASD Connection Issues

```bash
# Check ASD daemon is running
systemctl status asd

# Verify port is listening
ss -tlnp | grep 5123

# Check authentication
journalctl -u asd | grep -i "auth\|fail"

# Verify GPIO configuration
cat /sys/kernel/debug/gpio | grep -i jtag

# Test JTAG chain manually
jtag_test --scan
```

### JTAG Chain Not Detected

```bash
# Check XDP present signal
gpioget gpiochip0 <xdp_present_pin>

# Verify CPU is powered
obmcutil state

# Check JTAG signals
cat /sys/kernel/debug/pinctrl/*/pins | grep -i jtag

# Reset JTAG state machine
jtag_test --reset
```

### Crash Dump Collection Fails

```bash
# Check crashdump service
systemctl status crashdump

# View crash dump logs
journalctl -u crashdump -f

# Verify PECI connectivity
peci_cmds Ping 0x30  # CPU0 address

# Check GPIO error signals
gpioget gpiochip0 <caterr_pin>
gpioget gpiochip0 <err2_pin>

# Manual PECI test
peci_cmds RdPkgConfig 0x30 0 0
```

### Incomplete Crash Dump

```bash
# Check storage space
df -h /var/lib/crashdump/

# Verify PECI timeout
journalctl -u crashdump | grep -i "timeout\|peci"

# Check CPU accessibility
peci_cmds Ping 0x30
peci_cmds Ping 0x31  # CPU1 if present

# Retry collection
curl -k -u root:0penBmc -X POST \
    -d '{"DiagnosticDataType": "OEM", "OEMDiagnosticDataType": "OnDemand"}' \
    https://localhost/redfish/v1/Systems/system/LogServices/Crashdump/Actions/LogService.CollectDiagnosticData
```

### Performance Issues

```bash
# ASD operations are slow - check JTAG clock
# Default TCK is often conservative

# Crashdump takes too long
# Large dumps may take several minutes
# Monitor progress in journal
journalctl -u crashdump -f
```

---

## Platform-Specific Notes

### Intel Xeon Scalable (Ice Lake, Sapphire Rapids)

```
- Supports enhanced crashdump features
- Multiple MCA banks per CPU
- Extended TOR dump capability
- Hardware crashlog support
```

### Intel Xeon D

```
- Reduced feature set
- Single-socket configuration typical
- Integrated PCH
```

### Supported Platforms

| Platform | ASD | ACD | Notes |
|----------|-----|-----|-------|
| Ice Lake-SP | Yes | Yes | Full support |
| Sapphire Rapids | Yes | Yes | Enhanced crashlog |
| Xeon D | Yes | Limited | Reduced MCA banks |
| Older Xeon | Limited | Limited | Legacy JTAG only |

---

## References

- [Intel At-Scale Debug (ASD)](https://github.com/Intel-BMC/asd) - Intel BMC debug access solution
- [Intel-BMC OpenBMC](https://github.com/Intel-BMC/openbmc) - Intel OpenBMC fork with crashdump support
- [bmcweb Crashdump Endpoints](https://github.com/openbmc/bmcweb/blob/master/redfish-core/lib/log_services.hpp) - Redfish crashdump implementation
- [Intel IPMI OEM](https://github.com/openbmc/intel-ipmi-oem) - Intel-specific IPMI commands
- [PECI Specification](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-power-thermal-technologies.html) - Platform Environment Control Interface

{: .note }
OpenIPC (Open In-band Processor Communication) is part of Intel System Studio and is not publicly available on GitHub. Contact Intel for access.

---

{: .note }
**Platform**: Intel Xeon platforms only. Features vary by CPU generation.
