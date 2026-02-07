---
layout: default
title: Debug Dump Collection
parent: Advanced Topics
nav_order: 17
difficulty: intermediate
prerequisites:
  - environment-setup
  - redfish-guide
last_modified_date: 2026-02-06
---

# Debug Dump Collection
{: .no_toc }

Collect, manage, and extend BMC diagnostic dumps using phosphor-debug-collector and the dreport framework.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

When a BMC daemon crashes, a host fails to boot, or sensors report unexpected values, you need a way to capture the full system state for offline analysis. OpenBMC provides **phosphor-debug-collector**, a dump management service that orchestrates diagnostic data collection through the **dreport** framework.

phosphor-debug-collector exposes dump operations on D-Bus and Redfish, while dreport executes a pipeline of plugin scripts that gather journal logs, core files, D-Bus object trees, hardware register snapshots, and any platform-specific data you define. The resulting tarball can be downloaded via Redfish, SCP, or the BMC command line.

This guide walks you through the dump collection architecture, shows you how to trigger and retrieve dumps through Redfish and D-Bus, explains how to write custom dreport plugins for vendor-specific diagnostics, and covers storage management to keep dump files from exhausting flash space.

**Key concepts covered:**
- phosphor-debug-collector architecture and dump types
- BMC dump collection via Redfish DumpService and D-Bus
- dreport framework and plugin pipeline
- Writing and installing custom dreport plugins
- Dump storage limits, retention policies, and cleanup

{: .note }
> **Source Reference**: [phosphor-debug-collector](https://github.com/openbmc/phosphor-debug-collector)
> contains the dump manager, dreport scripts, and default plugins.

---

## Architecture

### Dump Collection Architecture

```
+-----------------------------------------------------------------+
|                  Debug Dump Architecture                        |
+-----------------------------------------------------------------+
|                                                                 |
|  +------------------------------------------------------------+ |
|  |                   Access Interfaces                        | |
|  |                                                            | |
|  |  +------------+  +------------+  +------------+            | |
|  |  | Redfish    |  | D-Bus      |  | CLI        |            | |
|  |  | DumpService|  | busctl     |  | dreport    |            | |
|  |  +------+-----+  +------+-----+  +------+-----+            | |
|  +---------|--------------|--------------|--------------------+ |
|            +-------+------+------+-------+                      |
|                    |                                            |
|  +-----------------v------------------------------------------+ |
|  |          phosphor-debug-collector                          | |
|  |          xyz.openbmc_project.Dump.Manager                  | |
|  |                                                            | |
|  |  +---------------+  +--------------+  +----------------+   | |
|  |  | Dump Manager  |  | Dump Entry   |  | Dump Offloader |   | |
|  |  | (create/list) |  | (D-Bus obj)  |  | (download)     |   | |
|  |  +-------+-------+  +--------------+  +----------------+   | |
|  +----------|-------------------------------------------------+ |
|             |                                                   |
|  +----------v---------------------------------------------+     |
|  |                    dreport                             |     |
|  |            (Plugin Execution Engine)                   |     |
|  |                                                        |     |
|  |  +----------+  +----------+  +----------+  +--------+  |     |
|  |  | Journal  |  | D-Bus    |  | Core     |  | Custom |  |     |
|  |  | Logs     |  | State    |  | Files    |  | Plugins|  |     |
|  |  +----------+  +----------+  +----------+  +--------+  |     |
|  +--------------------------------------------------------+     |
|             |                                                   |
|  +----------v---------------------------------------------+     |
|  |                  Dump Storage                          |     |
|  |    /var/lib/phosphor-debug-collector/dumps/            |     |
|  |    +-- bmc/                                            |     |
|  |    +-- system/                                         |     |
|  |    +-- resource/                                       |     |
|  +--------------------------------------------------------+     |
|                                                                 |
+-----------------------------------------------------------------+
```

### Dump Types

phosphor-debug-collector supports several dump types, each designed for a different failure scenario:

| Dump Type | D-Bus Path | Contents | Trigger |
|-----------|-----------|----------|---------|
| BMC Dump | `/xyz/openbmc_project/dump/bmc` | Journal logs, D-Bus state, core files, config | User request, daemon crash |
| System Dump | `/xyz/openbmc_project/dump/system` | Host memory, SBE state, hardware registers | Host failure, checkstop |
| Resource Dump | `/xyz/openbmc_project/dump/resource` | Specific hardware resource data | Targeted diagnostics |

{: .tip }
> **BMC dumps** are the most commonly used type. They capture everything running on the BMC itself and do not require host cooperation. Start here for most debugging scenarios.

### D-Bus Interfaces

| Interface | Object Path | Description |
|-----------|-------------|-------------|
| `xyz.openbmc_project.Dump.Create` | `/xyz/openbmc_project/dump/bmc` | Create a new dump |
| `xyz.openbmc_project.Dump.Entry` | `/xyz/openbmc_project/dump/bmc/entry/<id>` | Individual dump metadata |
| `xyz.openbmc_project.Dump.Manager` | `/xyz/openbmc_project/dump/bmc` | List and manage dumps |
| `xyz.openbmc_project.Object.Delete` | `/xyz/openbmc_project/dump/bmc/entry/<id>` | Delete a dump entry |

### Key Dependencies

- **phosphor-logging**: Event logs that may trigger automatic dump collection
- **bmcweb**: Serves Redfish DumpService endpoints for remote dump operations
- **dreport**: Shell script framework that executes plugin scripts to gather data
- **systemd-coredump**: Captures core dumps from crashing daemons

---

## Setup & Configuration

### Build-Time Configuration (Yocto)

```bitbake
# In your machine .conf or local.conf

# Include dump collection packages
IMAGE_INSTALL:append = " \
    phosphor-debug-collector \
"

# Configure dump options via meson overrides
EXTRA_OEMESON:pn-phosphor-debug-collector = " \
    -Dbmc_dump_total_size=67108864 \
    -Dbmc_dump_max_num=10 \
"
```

### Meson Build Options

| Option | Default | Description |
|--------|---------|-------------|
| `bmc_dump_total_size` | 67108864 (64 MB) | Maximum total size of all BMC dumps in bytes |
| `bmc_dump_max_num` | 10 | Maximum number of BMC dump entries |
| `bmc_dump_path` | `/var/lib/phosphor-debug-collector/dumps/` | Storage path for dump files |

### Runtime Verification

```bash
# Check dump manager service
systemctl status phosphor-dump-manager

# View service logs
journalctl -u phosphor-dump-manager -f

# Verify D-Bus service is registered
busctl status xyz.openbmc_project.Dump.Manager

# Check dump storage directory
ls -la /var/lib/phosphor-debug-collector/dumps/
```

---

## BMC Dump Collection

### Via Redfish DumpService

The Redfish DumpService provides the standard interface for creating, listing, and downloading dumps from remote management tools.

#### Create a BMC Dump

```bash
# Trigger a new BMC dump
curl -k -u root:0penBmc -X POST \
    -H "Content-Type: application/json" \
    -d '{"DiagnosticDataType": "Manager"}' \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Actions/LogService.CollectDiagnosticData
```

The response includes a task URI you can poll for completion:

```json
{
    "@odata.id": "/redfish/v1/TaskService/Tasks/0",
    "@odata.type": "#Task.v1_4_3.Task",
    "Id": "0",
    "TaskState": "Running"
}
```

#### Poll for Completion

```bash
# Check task status
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/TaskService/Tasks/0
```

{: .note }
> Dump generation can take 30 seconds to several minutes depending on the number of dreport plugins and the amount of data collected. Poll the task endpoint until `TaskState` shows `Completed`.

#### List Available Dumps

```bash
# List all BMC dump entries
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Entries
```

#### Download a Dump

```bash
# Download dump tarball by entry ID
curl -k -u root:0penBmc -o bmc_dump_1.tar.xz \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Entries/1/attachment
```

#### Delete a Dump

```bash
# Delete a specific dump entry
curl -k -u root:0penBmc -X DELETE \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Entries/1

# Clear all dumps
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Actions/LogService.ClearLog
```

### Via D-Bus

Use D-Bus calls for programmatic dump collection from scripts or services running on the BMC itself.

#### Create a BMC Dump

```bash
# Create a user-initiated BMC dump
busctl call xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc \
    xyz.openbmc_project.Dump.Create \
    CreateDump "a{sv}" 0
```

The call returns the object path of the new dump entry:

```
o "/xyz/openbmc_project/dump/bmc/entry/1"
```

#### Monitor Dump Progress

```bash
# Watch for dump completion signal
busctl monitor xyz.openbmc_project.Dump.Manager \
    --match "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path_namespace='/xyz/openbmc_project/dump/bmc/entry'"
```

#### List Dump Entries

```bash
# List all dump entries in the D-Bus tree
busctl tree xyz.openbmc_project.Dump.Manager

# Get properties of a specific dump entry
busctl introspect xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc/entry/1

# Get the dump size
busctl get-property xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc/entry/1 \
    xyz.openbmc_project.Dump.Entry \
    Size
```

#### Delete a Dump Entry

```bash
# Delete a specific dump
busctl call xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc/entry/1 \
    xyz.openbmc_project.Object.Delete \
    Delete
```

### Via Command Line (dreport)

For direct on-BMC debugging, you can invoke dreport manually:

```bash
# Generate a user-initiated dump
dreport -d /tmp/dumps -n manual_dump -t user -v

# Report type options:
#   user     - User-initiated BMC dump (default)
#   core     - Triggered by a core dump
#   elog     - Triggered by an error log event

# Examine the generated dump
ls -la /tmp/dumps/
tar -tvf /tmp/dumps/manual_dump_*.tar.xz
```

### Dump Contents

A typical BMC dump tarball contains:

| Directory/File | Description |
|----------------|-------------|
| `dreport.log` | dreport execution log and plugin output |
| `journal/` | Full journald logs from the BMC |
| `dbus/` | D-Bus object tree snapshots |
| `core/` | Core dump files (if triggered by a crash) |
| `config/` | System configuration files |
| `proc/` | Process information (`/proc` snapshots) |
| `platform/` | Platform-specific data from custom plugins |

```bash
# Extract and examine a dump
mkdir /tmp/dump_analysis
tar -xf bmc_dump_1.tar.xz -C /tmp/dump_analysis
ls /tmp/dump_analysis/

# Review journal logs from the dump
less /tmp/dump_analysis/journal/journal.log

# Check D-Bus state at dump time
less /tmp/dump_analysis/dbus/dbus_tree.txt
```

---

## Custom dreport Plugins

The dreport framework executes plugin scripts during dump generation. Each plugin collects a specific category of data. You can write custom plugins to capture platform-specific diagnostics such as FPGA register dumps, vendor ASIC state, or custom hardware telemetry.

### Plugin API

dreport plugins are executable shell scripts that follow a naming convention and write their output to a designated directory. dreport discovers and runs them automatically based on the dump type being generated.

#### Plugin Naming Convention

```
pl_<type><priority>_<description>
```

| Field | Description | Values |
|-------|-------------|--------|
| `pl_` | Prefix (required) | Always `pl_` |
| `type` | Dump type code | `u` = user, `c` = core, `e` = elog |
| `priority` | Execution order (2 digits) | `00` (highest) to `99` (lowest) |
| `description` | Brief identifier | Lowercase, underscores |

**Examples:**
- `pl_u01_journal` -- User dump, high priority, collects journal logs
- `pl_u50_dbus_state` -- User dump, medium priority, collects D-Bus tree
- `pl_c10_core_files` -- Core dump, high priority, collects core files
- `pl_u80_fpga_regs` -- User dump, low priority, collects FPGA registers

{: .warning }
> Plugin names must be unique. If two plugins share the same name, only one will execute. Always verify your plugin name does not conflict with existing plugins.

#### Plugin Script Structure

Every dreport plugin receives these environment variables:

| Variable | Description |
|----------|-------------|
| `DREPORT_INCLUDE` | Path to dreport utility functions (source this) |
| `EPOCH_TIME` | Timestamp of the dump request |
| `name` | Name of the dump |
| `dump_dir` | Output directory for this dump |
| `dump_id` | Numeric ID of this dump |

```bash
#!/bin/bash
# pl_u80_fpga_regs - Collect FPGA register dump

# Source dreport utility functions
. "$DREPORT_INCLUDE"/functions

# Define the output file
desc="FPGA Register Dump"
file_name="fpga_registers"

# Use add_cmd_output to run a command and capture output
add_cmd_output "devmem2 0x1e6e2000 w" "${file_name}_ctrl.log" "${desc} - Control"
add_cmd_output "devmem2 0x1e6e2004 w" "${file_name}_status.log" "${desc} - Status"

# Or use add_copy_file to include an existing file
add_copy_file "/sys/kernel/debug/fpga/registers" "fpga_debug_regs.txt" "${desc}"
```

### dreport Utility Functions

When you source `$DREPORT_INCLUDE/functions`, you get access to these helper functions:

| Function | Arguments | Description |
|----------|-----------|-------------|
| `add_cmd_output` | `"command" "filename" "description"` | Run a command and save its stdout to the dump |
| `add_copy_file` | `"source_path" "dest_name" "description"` | Copy a file into the dump tarball |
| `log_summary` | `"message"` | Write a message to the dreport summary log |

### Writing a Custom Plugin

Here is a complete example that collects I2C device state for a platform with custom power regulators:

```bash
#!/bin/bash
# pl_u70_i2c_regulators - Dump I2C regulator state
#
# Collects register dumps from VR controllers on I2C bus 3
# for post-mortem voltage regulator analysis.

. "$DREPORT_INCLUDE"/functions

desc="I2C Voltage Regulator State"

# Dump I2C bus scan results
add_cmd_output "i2cdetect -y 3" "i2c_bus3_scan.log" "${desc} - Bus Scan"

# Read specific regulator registers
for addr in 0x20 0x21 0x22; do
    name="vr_${addr}"
    add_cmd_output "i2cdump -y 3 ${addr}" "${name}_regs.log" "${desc} - ${addr}"
done

# Include any relevant kernel messages
add_cmd_output "dmesg | grep -i regulator" "regulator_dmesg.log" "${desc} - Kernel"

log_summary "I2C regulator state collected for bus 3"
```

### Installing Custom Plugins via Yocto

To deploy your custom plugin in the BMC image, create a bbappend for phosphor-debug-collector:

```bitbake
# meta-myplatform/recipes-phosphor/dump/phosphor-debug-collector_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://pl_u70_i2c_regulators \
    file://pl_u80_fpga_regs \
"

do_install:append() {
    # Install custom dreport plugins
    install -d ${D}${dreport_plugin_dir}
    install -m 0755 ${WORKDIR}/pl_u70_i2c_regulators \
        ${D}${dreport_plugin_dir}/
    install -m 0755 ${WORKDIR}/pl_u80_fpga_regs \
        ${D}${dreport_plugin_dir}/
}
```

{: .tip }
> The `dreport_plugin_dir` variable is defined by phosphor-debug-collector and points to the correct plugin installation path. Use it instead of hardcoding the directory.

### Testing Plugins

You can test a plugin directly on the BMC without generating a full dump:

```bash
# Set up the environment that dreport provides
export DREPORT_INCLUDE=/usr/share/dreport.d/include.d
export dump_dir=/tmp/test_plugin_output
export dump_id=999
export name="test"
export EPOCH_TIME=$(date +%s)

mkdir -p "$dump_dir"

# Run the plugin directly
bash /usr/share/dreport.d/plugins.d/pl_u70_i2c_regulators

# Check the output
ls -la "$dump_dir"
```

---

## Dump Storage Management

BMC flash storage is limited. Without proper management, dump files can consume all available space and cause service failures. phosphor-debug-collector enforces both count and size limits.

### Storage Limits

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum dump count | 10 | Oldest dump deleted when limit reached |
| Maximum total size | 64 MB | New dumps rejected when space exhausted |
| Storage path | `/var/lib/phosphor-debug-collector/dumps/` | On persistent filesystem |

### Retention Behavior

When a new dump is requested and the count or size limit would be exceeded:

1. The dump manager checks total dump count against `bmc_dump_max_num`
2. If the count limit is reached, the **oldest** dump entry is automatically deleted
3. If the total size limit (`bmc_dump_total_size`) would be exceeded even after count-based cleanup, the dump request fails with an error
4. Deleted dump entries are removed from both D-Bus and the filesystem

### Monitoring Storage Usage

```bash
# Check current dump count and sizes
busctl tree xyz.openbmc_project.Dump.Manager

# Get size of each dump entry
for entry in $(busctl tree xyz.openbmc_project.Dump.Manager \
    | grep "/xyz/openbmc_project/dump/bmc/entry/"); do
    size=$(busctl get-property xyz.openbmc_project.Dump.Manager \
        "$entry" xyz.openbmc_project.Dump.Entry Size 2>/dev/null)
    echo "$entry: $size"
done

# Check filesystem usage
df -h /var/lib/phosphor-debug-collector/
du -sh /var/lib/phosphor-debug-collector/dumps/*
```

### Customizing Limits

Override the defaults in your platform layer:

```bitbake
# meta-myplatform/recipes-phosphor/dump/phosphor-debug-collector_%.bbappend

# Allow more dumps with larger total budget (128 MB)
EXTRA_OEMESON:append = " \
    -Dbmc_dump_max_num=20 \
    -Dbmc_dump_total_size=134217728 \
"
```

{: .warning }
> Increasing dump limits consumes flash storage. On platforms with limited flash (e.g., 32 MB SPI NOR), keep the total dump size well below the available free space on the data partition. Monitor `/var/lib/phosphor-debug-collector/` usage after changing these values.

### Manual Cleanup

```bash
# Delete all dumps via Redfish
curl -k -u root:0penBmc -X POST \
    https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Actions/LogService.ClearLog

# Delete all dumps via D-Bus
for entry in $(busctl tree xyz.openbmc_project.Dump.Manager \
    | grep "/xyz/openbmc_project/dump/bmc/entry/"); do
    busctl call xyz.openbmc_project.Dump.Manager \
        "$entry" xyz.openbmc_project.Object.Delete Delete
done

# Direct filesystem cleanup (last resort)
rm -rf /var/lib/phosphor-debug-collector/dumps/bmc/*
systemctl restart phosphor-dump-manager
```

---

## Troubleshooting

### Issue: Dump Creation Fails with "No Space"

**Symptom**: Redfish returns an error or D-Bus call fails when creating a new dump.

**Cause**: The total dump size limit has been reached, or the filesystem is full.

**Solution**:
1. Check current dump storage usage:
   ```bash
   du -sh /var/lib/phosphor-debug-collector/dumps/
   df -h /var/lib/phosphor-debug-collector/
   ```
2. Delete old dumps to free space:
   ```bash
   curl -k -u root:0penBmc -X DELETE \
       https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Entries/1
   ```
3. If the filesystem is full from non-dump files, investigate with:
   ```bash
   du -sh /var/lib/* | sort -rh | head -10
   ```

### Issue: Dump Manager Service Not Running

**Symptom**: D-Bus calls to `xyz.openbmc_project.Dump.Manager` fail with "service not found."

**Cause**: The phosphor-dump-manager service failed to start or crashed.

**Solution**:
1. Check the service status:
   ```bash
   systemctl status phosphor-dump-manager
   ```
2. Review journal logs for errors:
   ```bash
   journalctl -u phosphor-dump-manager --no-pager -n 50
   ```
3. Verify the package is installed:
   ```bash
   opkg list-installed | grep phosphor-debug-collector
   ```

### Issue: Custom Plugin Not Executing

**Symptom**: Your custom dreport plugin output is missing from the dump tarball.

**Cause**: Plugin naming, permissions, or dump type mismatch.

**Solution**:
1. Verify the plugin name follows the convention (`pl_<type><priority>_<name>`):
   ```bash
   ls -la /usr/share/dreport.d/plugins.d/pl_u*
   ```
2. Confirm the plugin is executable:
   ```bash
   chmod +x /usr/share/dreport.d/plugins.d/pl_u80_fpga_regs
   ```
3. Check the dump type letter matches -- `u` for user dumps, `c` for core dumps
4. Test the plugin manually as described in [Testing Plugins](#testing-plugins)

### Issue: Dump Download Returns Empty or Corrupt File

**Symptom**: The downloaded tarball is 0 bytes or fails to extract.

**Cause**: The dump generation is still in progress, or the dump file was corrupted on disk.

**Solution**:
1. Verify the dump is complete before downloading:
   ```bash
   curl -k -u root:0penBmc \
       https://localhost/redfish/v1/Managers/bmc/LogServices/Dump/Entries/1 \
       | python3 -m json.tool | grep -i status
   ```
2. Check that the file exists and has nonzero size:
   ```bash
   ls -la /var/lib/phosphor-debug-collector/dumps/bmc/
   ```

### Debug Commands

```bash
# Check dump manager service
systemctl status phosphor-dump-manager

# View dump manager logs
journalctl -u phosphor-dump-manager -f

# List all D-Bus dump objects
busctl tree xyz.openbmc_project.Dump.Manager

# List installed dreport plugins
ls -la /usr/share/dreport.d/plugins.d/

# Run dreport in verbose mode
dreport -d /tmp/debug_test -n test -t user -v
```

---

## Examples

Working examples are available in the [examples/debug-dump](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/docs/examples/debug-dump) directory:

- `pl_u80_fpga_regs` -- Custom dreport plugin for FPGA register collection
- `pl_u70_i2c_regulators` -- Custom dreport plugin for I2C voltage regulator state
- `collect-dump-redfish.sh` -- Script to create, poll, and download a BMC dump via Redfish
- `list-dumps.sh` -- Script to list all dump entries with sizes

---

## References

### Official Resources
- [phosphor-debug-collector](https://github.com/openbmc/phosphor-debug-collector) -- Dump manager and dreport framework
- [D-Bus Dump Interfaces](https://github.com/openbmc/phosphor-dbus-interfaces/tree/master/yaml/xyz/openbmc_project/Dump) -- Dump D-Bus interface definitions
- [OpenBMC Documentation](https://github.com/openbmc/docs) -- General OpenBMC documentation

### Related Guides
- [Logging Guide]({% link docs/05-advanced/06-logging-guide.md %}) -- Event logging, SEL, and error management
- [Linux Debug Tools]({% link docs/05-advanced/08-linux-debug-tools-guide.md %}) -- ASan, Valgrind, and kernel debugging

### External Documentation
- [Redfish DumpService Schema](https://redfish.dmtf.org/schemas/LogService.v1_3_0.json) -- DMTF Redfish log service specification
- [DMTF Redfish Specification](https://www.dmtf.org/standards/redfish) -- Full Redfish standard

---

{: .note }
**Tested on**: QEMU ast2600-evb, OpenBMC master branch
Last updated: 2026-02-06
