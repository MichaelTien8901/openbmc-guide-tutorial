# BIOS Configuration Management Examples

Example scripts and configuration files for managing host BIOS settings through
OpenBMC's Redfish interface.

> **Requires a running OpenBMC system** -- these scripts use curl to communicate
> with bmcweb's Redfish endpoints. Run them from a remote host (or from the BMC
> itself using `localhost`). The BMC must have `bios-settings-manager` enabled.

## Quick Start (QEMU)

```bash
# 1. Boot OpenBMC in QEMU
./scripts/run-qemu.sh ast2600-evb

# 2. Read current BIOS settings
./read-bios-settings.sh localhost:2443

# 3. Apply a setting change
./update-bios-settings.sh localhost:2443 BootMode UEFI
```

## Files

| File | Description |
|------|-------------|
| `bios-settings.json` | Sample BIOS settings JSON showing string, integer, and enumeration attribute types |
| `read-bios-settings.sh` | Read current BIOS settings and individual attributes via Redfish |
| `update-bios-settings.sh` | Apply BIOS setting changes via Redfish (single or batch) |

## BIOS Attribute Types

OpenBMC's BIOS configuration manager supports three attribute types, all
demonstrated in `bios-settings.json`:

| Type | Example Attribute | Description |
|------|-------------------|-------------|
| **Enumeration** | `BootMode` | Fixed set of allowed values (e.g., `UEFI`, `Legacy`) |
| **String** | `AssetTag` | Free-form text with min/max length constraints |
| **Integer** | `NumCoresPerSocket` | Numeric value with lower/upper bounds |

## Redfish Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/redfish/v1/Systems/system/Bios` | GET | Current BIOS attributes and metadata |
| `/redfish/v1/Systems/system/Bios/Settings` | GET | Pending BIOS settings (applied on next boot) |
| `/redfish/v1/Systems/system/Bios/Settings` | PATCH | Apply new BIOS attribute values |
| `/redfish/v1/Systems/system/Bios/Actions/Bios.ResetBios` | POST | Reset BIOS settings to defaults |

## Architecture

BIOS configuration on OpenBMC follows this flow:

```
Host BIOS                 BMC (phosphor-bios-settings-mgr)        Redfish Client
    |                              |                                     |
    |-- PLDM SetBIOSTable -------->|                                     |
    |                              |-- Stores in D-Bus/Persist --------->|
    |                              |                                     |
    |                              |<--------- GET /Bios ----------------|
    |                              |---------- Current settings -------->|
    |                              |                                     |
    |                              |<--------- PATCH /Bios/Settings ----|
    |                              |---------- 200 OK ------------------>|
    |                              |                                     |
    |<-- PLDM GetBIOSTable --------|   (on next host boot)              |
    |-- Applies settings           |                                     |
```

The BMC acts as a proxy: it stores the BIOS attribute table received from the
host via PLDM, exposes it through Redfish, and forwards pending changes back to
the host BIOS on the next boot cycle.

## D-Bus Interface

The BIOS configuration manager exposes settings on D-Bus:

```bash
# List BIOS attributes via D-Bus (on the BMC)
busctl tree xyz.openbmc_project.BIOSConfigManager

# Get a specific attribute
busctl call xyz.openbmc_project.BIOSConfigManager \
    /xyz/openbmc_project/bios_config/manager \
    xyz.openbmc_project.BIOSConfig.Manager \
    GetAttribute s "BootMode"
```

## Troubleshooting

```bash
# Check if bios-settings-manager is running
ssh -p 2222 root@localhost systemctl status bios-settings-manager

# View BIOS config manager logs
ssh -p 2222 root@localhost journalctl -u bios-settings-manager -f

# Verify Redfish endpoint is reachable
curl -k -s -u root:0penBmc https://localhost:2443/redfish/v1/Systems/system/Bios | jq '.Id'

# Check pending settings
curl -k -s -u root:0penBmc \
    https://localhost:2443/redfish/v1/Systems/system/Bios/Settings | jq '.Attributes'
```

## Related Documentation

- [Redfish Guide](../../04-interfaces/02-redfish-guide.md) -- bmcweb architecture and patterns
- [MCTP/PLDM Guide](../../05-advanced/01-mctp-pldm-guide.md) -- PLDM BIOS type (Type 3) details
- [DMTF Redfish BIOS Schema](https://redfish.dmtf.org/schemas/v1/Bios.json)
- [OpenBMC bios-settings-mgr](https://github.com/openbmc/bios-settings-mgr)
