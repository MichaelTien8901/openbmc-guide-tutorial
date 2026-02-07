---
layout: default
title: POST Code Monitoring
parent: Advanced Topics
nav_order: 18
difficulty: intermediate
prerequisites:
  - environment-setup
  - redfish-guide
last_modified_date: 2026-02-06
---

# POST Code Monitoring
{: .no_toc }

Capture, store, and expose host POST codes through the OpenBMC stack, from LPC snoop hardware to Redfish APIs.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**POST codes** (Power-On Self-Test codes) are single-byte or multi-byte values that the host firmware writes to I/O port 0x80 during boot. Each code indicates which initialization stage the BIOS or UEFI firmware has reached. When a system hangs during boot, the last POST code captured by the BMC tells you exactly where the host stalled.

OpenBMC provides a complete POST code pipeline. The LPC snoop hardware on the ASPEED BMC captures every write to port 0x80, the `postd` daemon reads those values from the kernel driver, `phosphor-post-code-manager` stores them organized by boot cycle, and `bmcweb` exposes the data through standard Redfish LogService endpoints. This pipeline gives operators full visibility into host boot progress without requiring physical seven-segment displays or serial console access.

You use POST code monitoring whenever you need to diagnose host boot failures, track boot progress remotely, or integrate boot telemetry into data center management workflows. Combined with the BootProgress D-Bus property, POST codes provide both fine-grained numeric codes and human-readable boot stage descriptions.

**Key concepts covered:**
- LPC snoop capture and the kernel aspeed-lpc-snoop driver
- The `postd` and `phosphor-post-code-manager` daemons
- Redfish POST code exposure via PostCodes LogService
- Boot progress state mapping through D-Bus properties
- Multi-host POST code collection

---

## Architecture

### POST Code Capture Pipeline

The POST code pipeline flows from hardware capture to Redfish exposure through four stages.

```
+------------------------------------------------------------------+
|                  POST Code Capture Pipeline                      |
+------------------------------------------------------------------+
|                                                                  |
|  +-------------------+                                           |
|  | Host CPU / BIOS   |  Writes POST codes to I/O port 0x80       |
|  +--------+----------+                                           |
|           |  LPC bus                                             |
|           v                                                      |
|  +-------------------+                                           |
|  | ASPEED LPC Snoop  |  Hardware captures port 0x80 writes       |
|  | (aspeed-lpc-snoop)|  Kernel driver: /dev/aspeed-lpc-snoop0    |
|  +--------+----------+                                           |
|           |  Character device read                               |
|           v                                                      |
|  +-------------------+                                           |
|  | postd             |  Reads raw bytes from snoop device        |
|  | (snoop daemon)    |  Publishes to D-Bus: State.Boot.Raw       |
|  +--------+----------+                                           |
|           |  D-Bus PropertiesChanged signal                      |
|           v                                                      |
|  +-------------------+                                           |
|  | phosphor-post-    |  Stores codes indexed by boot cycle       |
|  | code-manager      |  Persists history across BMC reboots      |
|  +--------+----------+                                           |
|           |  D-Bus object tree                                   |
|           v                                                      |
|  +-------------------+                                           |
|  | bmcweb            |  Exposes via Redfish:                     |
|  | (Redfish server)  |  /redfish/v1/.../LogServices/PostCodes    |
|  +-------------------+                                           |
|                                                                  |
+------------------------------------------------------------------+
```

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.State.Boot.Raw` | `/xyz/openbmc_project/state/boot/raw0` | Current POST code value |
| `xyz.openbmc_project.State.Boot.PostCode` | `/xyz/openbmc_project/State/Boot/PostCode0` | POST code history by boot cycle |
| `xyz.openbmc_project.State.Boot.Progress` | `/xyz/openbmc_project/state/host0` | High-level boot progress state |

### Key Dependencies

- **aspeed-lpc-snoop kernel driver**: Captures LPC port 0x80 writes in hardware
- **phosphor-host-postd**: Reads the snoop device and publishes to D-Bus
- **phosphor-post-code-manager**: Aggregates and persists POST code history
- **bmcweb**: Translates D-Bus POST code objects into Redfish responses

---

## Setup and Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include POST code packages
IMAGE_INSTALL:append = " \
    phosphor-host-postd \
    phosphor-post-code-manager \
"

# The LPC snoop driver is typically built into the kernel
# for ASPEED platforms. Verify it is enabled:
KERNEL_FEATURES:append = " features/aspeed/lpc-snoop.scc"
```

### Kernel and Device Tree Configuration

Ensure the ASPEED LPC snoop driver is enabled in your kernel (`CONFIG_ASPEED_LPC_SNOOP=y`) and the snoop node is enabled in your platform device tree:

```dts
&lpc_snoop {
    status = "okay";
    snoop-ports = <0x80>;
};
```

{: .note }
Most ASPEED reference platforms (ast2500-evb, ast2600-evb) already have the LPC snoop node enabled. Check your platform DTS before adding a duplicate entry.

### Runtime Verification

```bash
# Verify the snoop device exists
ls -l /dev/aspeed-lpc-snoop0

# Check postd service
systemctl status phosphor-host-postd

# Check post-code-manager service
systemctl status phosphor-post-code-manager

# View service logs
journalctl -u phosphor-host-postd -f
journalctl -u phosphor-post-code-manager -f
```

---

## Capturing POST Codes

### How LPC Snoop Works

The ASPEED BMC includes dedicated hardware that monitors the LPC bus for writes to specific I/O port addresses. When the host writes a byte to port 0x80, the snoop hardware latches the value into a FIFO buffer. The kernel driver exposes this FIFO as a character device at `/dev/aspeed-lpc-snoop0`.

The `postd` daemon performs a blocking read on this device. Each time a new POST code arrives, `postd` updates the `Value` property on the `xyz.openbmc_project.State.Boot.Raw` D-Bus interface. The `phosphor-post-code-manager` daemon monitors this property via D-Bus signal matching and appends each new code to the current boot cycle's history.

### Reading POST Codes via D-Bus

```bash
# Get the current (most recent) POST code
busctl get-property xyz.openbmc_project.State.Boot.Raw \
    /xyz/openbmc_project/state/boot/raw0 \
    xyz.openbmc_project.State.Boot.Raw \
    Value

# Watch POST codes arrive in real time
busctl monitor xyz.openbmc_project.State.Boot.Raw
```

### Querying POST Code History

The post-code-manager stores codes organized by boot cycle number. Boot cycle 1 is the most recent complete boot, cycle 2 is the one before that, and so on.

```bash
# Get POST codes from the current boot cycle
busctl call xyz.openbmc_project.State.Boot.PostCode0 \
    /xyz/openbmc_project/State/Boot/PostCode0 \
    xyz.openbmc_project.State.Boot.PostCode \
    GetPostCodesWithTimeStamp q 1

# Get the number of stored boot cycles
busctl get-property xyz.openbmc_project.State.Boot.PostCode0 \
    /xyz/openbmc_project/State/Boot/PostCode0 \
    xyz.openbmc_project.State.Boot.PostCode \
    CurrentBootCycleCount
```

{: .tip }
The `GetPostCodesWithTimeStamp` method returns an array of `(timestamp, code)` pairs. The timestamp is a microsecond-precision value that lets you calculate the time between boot stages.

---

## Redfish POST Code Exposure

### PostCodes LogService

OpenBMC exposes POST codes through the Redfish LogService at the standard path. This is the primary interface for remote management tools.

```bash
# Get the PostCodes LogService
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/PostCodes

# List POST code entries
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/PostCodes/Entries

# Get a specific entry
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system/LogServices/PostCodes/Entries/B1-1
```

### Entry Format

Each Redfish POST code entry includes:

| Field | Description | Example |
|-------|-------------|---------|
| `Id` | Boot cycle and sequence index | `B1-1` (Boot 1, code 1) |
| `MessageId` | Redfish message identifier | `OpenBMC.0.2.BIOSPOSTCode` |
| `Created` | Timestamp of the POST code | `2026-02-06T10:15:30+00:00` |
| `MessageArgs` | Array containing the POST code value | `["0x19"]` |
| `Severity` | Always `OK` for POST codes | `OK` |

### Example Redfish Response

```json
{
    "@odata.id": "/redfish/v1/Systems/system/LogServices/PostCodes/Entries/B1-3",
    "@odata.type": "#LogEntry.v1_9_0.LogEntry",
    "Id": "B1-3",
    "Name": "POST Code Log Entry",
    "EntryType": "Event",
    "Severity": "OK",
    "Created": "2026-02-06T10:15:32.451+00:00",
    "MessageId": "OpenBMC.0.2.BIOSPOSTCode",
    "MessageArgs": [
        "0xA2"
    ],
    "Message": "BIOS POST Code: 0xA2"
}
```

### Clearing POST Code Logs

```bash
# Clear all POST code entries
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/Systems/system/LogServices/PostCodes/Actions/LogService.ClearLog
```

{: .warning }
Clearing POST code logs deletes all stored boot cycle history. This action cannot be undone. Consider exporting log data before clearing if you need it for later analysis.

---

## Boot Progress State Mapping

### BootProgress D-Bus Property

In addition to raw numeric POST codes, OpenBMC maps host boot stages to human-readable progress states. The `phosphor-state-manager` exposes a `BootProgress` property that higher-level tools can use without needing to interpret vendor-specific POST code tables.

```bash
# Get current boot progress
busctl get-property xyz.openbmc_project.State.Host \
    /xyz/openbmc_project/state/host0 \
    xyz.openbmc_project.State.Boot.Progress \
    BootProgress
```

### Standard Boot Progress States

| D-Bus Enumeration | Description | Typical POST Code Range |
|-------------------|-------------|------------------------|
| `Unspecified` | Boot state unknown or not yet started | -- |
| `PrimaryProcInit` | Primary processor initialization | 0x01 - 0x0F |
| `BusInit` | System bus (PCI, USB) initialization | 0x10 - 0x2F |
| `MemoryInit` | Memory detection and training | 0x30 - 0x4F |
| `SecondaryProcInit` | Secondary processor initialization | 0x50 - 0x5F |
| `PCIInit` | PCI resource enumeration and configuration | 0x60 - 0x7F |
| `OSStart` | Operating system handoff beginning | 0x80 - 0x8F |
| `OSRunning` | Operating system is running | 0x90+ |
| `SystemInitComplete` | All firmware initialization complete | 0xA0 - 0xAF |
| `SystemSetup` | BIOS setup / configuration menu active | 0xB0 - 0xBF |

{: .note }
POST code-to-progress-state mappings are vendor-specific. The ranges listed above are common conventions, but your BIOS vendor may use different assignments. Consult your BIOS documentation for exact mappings.

### Boot Progress via Redfish

The boot progress state is also available through the Redfish Systems resource:

```bash
# Query boot progress through Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Systems/system | \
    python3 -m json.tool | grep -A 5 BootProgress
```

Example response fragment:

```json
{
    "BootProgress": {
        "LastState": "SystemHardwareInitializationComplete",
        "LastStateTime": "2026-02-06T10:16:45+00:00"
    }
}
```

### Customizing Boot Progress Mapping

To map your platform's POST codes to standard boot progress states, create a platform-specific configuration in your machine layer:

```json
{
    "CodeMap": {
        "0x13": "PrimaryProcInit",
        "0x34": "MemoryInit",
        "0x62": "PCIInit",
        "0x85": "OSStart",
        "0xA0": "SystemInitComplete"
    }
}
```

---

## Multi-Host POST Code Collection

### Multi-Host Architecture

In multi-host (multi-node) platforms, each host has an independent POST code pipeline. The BMC manages separate snoop devices, `postd` instances, and post-code-manager instances for each host. Each pipeline follows the same four-stage flow described in the Architecture section, with instance-numbered D-Bus paths and Redfish endpoints.

### Yocto Configuration for Multi-Host

```bitbake
# Enable multi-host POST code support
# In your machine .conf
OBMC_HOST_INSTANCES = "0 1 2 3"

# Each instance gets its own systemd service
# phosphor-host-postd@0.service
# phosphor-host-postd@1.service
# etc.
```

### Multi-Host D-Bus Paths

Each host instance uses a numbered suffix on D-Bus paths. Replace `N` with the host index (0, 1, 2, ...):

| Resource | D-Bus Path |
|----------|------------|
| Current POST code | `/xyz/openbmc_project/state/boot/rawN` |
| POST code history | `/xyz/openbmc_project/State/Boot/PostCodeN` |
| Boot progress | `/xyz/openbmc_project/state/hostN` |

```bash
# Read Host 1 current POST code
busctl get-property xyz.openbmc_project.State.Boot.Raw \
    /xyz/openbmc_project/state/boot/raw1 \
    xyz.openbmc_project.State.Boot.Raw Value

# Read Host 1 boot cycle history
busctl call xyz.openbmc_project.State.Boot.PostCode1 \
    /xyz/openbmc_project/State/Boot/PostCode1 \
    xyz.openbmc_project.State.Boot.PostCode \
    GetPostCodesWithTimeStamp q 1
```

### Device Tree for Multi-Host

```dts
&lpc_snoop {
    status = "okay";
    snoop-ports = <0x80 0x81>;
    /* Port 0x80 -> /dev/aspeed-lpc-snoop0 (Host 0) */
    /* Port 0x81 -> /dev/aspeed-lpc-snoop1 (Host 1) */
};
```

{: .tip }
Some multi-host platforms use separate LPC buses rather than separate I/O ports. In that case, each LPC bus has its own snoop node in the device tree. Check your platform's hardware design to determine the correct configuration.

---

## Troubleshooting

### No POST Codes Appearing

**Symptom**: The `Value` property on `State.Boot.Raw` never changes, even when the host is booting.

**Solution**:

```bash
# 1. Verify the snoop device exists
ls -l /dev/aspeed-lpc-snoop*

# 2. Check the kernel driver is loaded
dmesg | grep -i snoop

# 3. Verify postd is running and connected
systemctl status phosphor-host-postd
journalctl -u phosphor-host-postd --no-pager -n 20

# 4. Read the snoop device directly (bypasses postd)
# This blocks until a POST code arrives
xxd /dev/aspeed-lpc-snoop0

# 5. Check the device tree has snoop enabled
cat /sys/firmware/devicetree/base/ahb/apb/lpc/lpc-snoop/status
```

{: .note }
If `xxd /dev/aspeed-lpc-snoop0` produces no output even during host boot, the issue is at the hardware or kernel driver level. Verify that the LPC bus is physically connected and the host is actually writing to port 0x80.

### POST Code History Missing

**Symptom**: Real-time POST codes appear in D-Bus but `GetPostCodesWithTimeStamp` returns empty results.

**Solution**:

```bash
# 1. Check post-code-manager service
systemctl status phosphor-post-code-manager
journalctl -u phosphor-post-code-manager --no-pager -n 20

# 2. Check persistent storage
ls -la /var/lib/phosphor-post-code-manager/
```

### Redfish PostCodes Endpoint Returns 404

**Symptom**: Querying `/redfish/v1/Systems/system/LogServices/PostCodes` returns a 404 error.

**Solution**:

```bash
# 1. Verify bmcweb is running
systemctl status bmcweb

# 2. Check that post-code-manager D-Bus objects exist
busctl tree xyz.openbmc_project.State.Boot.PostCode0

# 3. Confirm bmcweb was built with POST code support
# The PostCodes LogService requires BMCWEB_ENABLE_REDFISH_POSTCODE
```

### POST Codes Stop After Boot

This is usually normal behavior. Most BIOS implementations stop writing to port 0x80 once they hand off to the OS bootloader.

---

## Examples

Working examples are available in the [examples/post-code](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/post-code) directory:

- `read-postcode.sh` - Read current and historical POST codes via D-Bus
- `monitor-boot.sh` - Monitor POST codes and boot progress in real time
- `redfish-postcode.sh` - Query POST code history through Redfish API

---

## References

### OpenBMC Repositories

- [phosphor-host-postd](https://github.com/openbmc/phosphor-host-postd) - LPC snoop reader daemon
- [phosphor-post-code-manager](https://github.com/openbmc/phosphor-post-code-manager) - POST code history storage
- [phosphor-dbus-interfaces (State.Boot.Raw)](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/State/Boot) - D-Bus interface definitions
- [bmcweb](https://github.com/openbmc/bmcweb) - Redfish server with PostCodes LogService

### Specifications

- [DMTF Redfish LogService Schema](https://redfish.dmtf.org/schemas/LogService.v1_3_0.json) - Redfish log service specification
- [DMTF Redfish ComputerSystem Schema](https://redfish.dmtf.org/schemas/ComputerSystem.v1_20_0.json) - BootProgress property definition

### Related Guides

- [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) - Event logs, SEL, and debug dumps
- [eSPI Guide]({% link docs/05-advanced/09-espi-guide.md %}) - LPC/eSPI host communication

---

{: .note }
**Tested on**: OpenBMC master, QEMU ast2600-evb. Multi-host features require platform-specific hardware support.
