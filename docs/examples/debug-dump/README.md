# Debug Dump Collection Examples

Shell scripts for collecting, listing, and downloading BMC debug dumps on OpenBMC
using the Redfish DumpService API and the dreport plugin framework.

> **Requires OpenBMC environment** -- these scripts run against a booted OpenBMC
> system (QEMU or hardware) with `phosphor-debug-collector` and `dreport` installed.
> The curl-based scripts can run from any remote host with network access to the BMC.

## Quick Start (QEMU)

```bash
# 1. Boot OpenBMC in QEMU
./scripts/run-qemu.sh ast2600-evb

# 2. List existing dumps from your host
./list-dumps.sh localhost:2443

# 3. Trigger a new BMC dump and download it
./collect-dump.sh localhost:2443

# 4. (Optional) Install custom dreport plugin on BMC
scp -P 2222 custom-dreport-plugin.sh root@localhost:/usr/share/dreport.d/plugins.d/
ssh -p 2222 root@localhost chmod +x /usr/share/dreport.d/plugins.d/pl_User99_platformdata
```

## Scripts

| Script | Runs On | Description |
|--------|---------|-------------|
| `collect-dump.sh <bmc-ip> [user] [pass]` | Remote host | Trigger a BMC dump via Redfish, poll for completion, and download the tar.xz archive |
| `list-dumps.sh <bmc-ip> [user] [pass]` | Remote host | List all existing BMC dumps with ID, timestamp, size, and state |
| `custom-dreport-plugin.sh` | OpenBMC | Sample dreport plugin that collects custom platform data (install to `/usr/share/dreport.d/plugins.d/`) |

## How BMC Dumps Work

OpenBMC uses `phosphor-debug-collector` to manage dump collection. When you
request a dump (via Redfish, D-Bus, or `dreport` CLI), the system:

1. **Invokes dreport** -- the dump collection orchestrator
2. **Runs plugins** -- shell scripts in `/usr/share/dreport.d/plugins.d/` that
   each collect a specific category of data (journals, core files, hardware
   registers, inventory, etc.)
3. **Packages the output** -- all collected data is bundled into a `.tar.xz`
   archive stored in `/var/lib/phosphor-debug-collector/dumps/`
4. **Exposes via Redfish** -- the dump appears at
   `/redfish/v1/Managers/bmc/LogServices/Dump/Entries/<id>`

### dreport Plugin Naming Convention

Plugins follow the naming pattern: `pl_<Type><Priority>_<description>`

| Field | Values | Meaning |
|-------|--------|---------|
| `pl_` | Fixed prefix | Identifies the file as a plugin |
| Type | `User`, `Core`, `Elog`, `Ramoops`, `Checkstop` | Which dump type triggers this plugin |
| Priority | `00`-`99` | Execution order (lower runs first) |
| Description | Free text | Human-readable name for the plugin |

**Examples from upstream:**

| Plugin Name | What It Collects |
|-------------|-----------------|
| `pl_User01_BMCjournal` | BMC systemd journal logs |
| `pl_User02_corefile` | Application core dump files |
| `pl_User03_dmesg` | Kernel ring buffer messages |
| `pl_User05_bmcstate` | Current BMC state and uptime |
| `pl_User10_hwregister` | Hardware register dumps |

## Redfish DumpService Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/Managers/bmc/LogServices/Dump/Entries` | GET | List all BMC dump entries |
| `/redfish/v1/Managers/bmc/LogServices/Dump/Actions/LogService.CollectDiagnosticData` | POST | Trigger a new BMC dump |
| `/redfish/v1/Managers/bmc/LogServices/Dump/Entries/<id>` | GET | Get metadata for a specific dump |
| `/redfish/v1/Managers/bmc/LogServices/Dump/Entries/<id>/attachment` | GET | Download the dump archive |
| `/redfish/v1/Managers/bmc/LogServices/Dump/Entries/<id>` | DELETE | Delete a specific dump |
| `/redfish/v1/Managers/bmc/LogServices/Dump/Actions/LogService.ClearLog` | POST | Delete all dumps |

## D-Bus Interface (On-BMC)

You can also manage dumps directly via D-Bus from the BMC shell:

```bash
# Trigger a new BMC dump
busctl call xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc \
    xyz.openbmc_project.Dump.Create CreateDump "a{sv}" 0

# List dump entries
busctl tree xyz.openbmc_project.Dump.Manager

# Get dump size (in bytes)
busctl get-property xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc/entry/1 \
    xyz.openbmc_project.Dump.Entry Size

# Delete a specific dump
busctl call xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc/entry/1 \
    xyz.openbmc_project.Object.Delete Delete

# Delete all dumps
busctl call xyz.openbmc_project.Dump.Manager \
    /xyz/openbmc_project/dump/bmc \
    xyz.openbmc_project.Collection.DeleteAll DeleteAll

# Run dreport directly from the command line
dreport -d /tmp/my-dump -v
```

## Troubleshooting

```bash
# Check if phosphor-debug-collector is running
systemctl status phosphor-debug-collector

# View dump manager logs
journalctl -u phosphor-debug-collector -f

# List installed dreport plugins
ls -la /usr/share/dreport.d/plugins.d/

# Check available disk space for dumps
df -h /var/lib/phosphor-debug-collector/

# Verify Redfish DumpService is available
curl -k -s -u root:0penBmc \
    https://localhost:2443/redfish/v1/Managers/bmc/LogServices/Dump \
    | python3 -m json.tool

# Check dump directory on BMC
ls -la /var/lib/phosphor-debug-collector/dumps/
```

## References

- [Logging Guide](../../05-advanced/06-logging-guide.md) -- event log management and debug tools
- [Linux Debug Tools Guide](../../05-advanced/08-linux-debug-tools-guide.md) -- coredump analysis and debugging
- [phosphor-debug-collector](https://github.com/openbmc/phosphor-debug-collector) -- dump manager source
- [dreport](https://github.com/openbmc/phosphor-debug-collector/tree/master/tools/dreport) -- dump report tool and plugins
- [Redfish DumpService schema](https://redfish.dmtf.org/schemas/v1/LogService.json)
