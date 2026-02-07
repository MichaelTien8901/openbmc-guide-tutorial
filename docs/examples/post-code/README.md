# POST Code Monitoring Examples

Shell scripts for reading and monitoring BIOS/UEFI POST codes on OpenBMC. POST
codes are single-byte status values written by host firmware during boot to
indicate progress through initialization stages.

> **Requires OpenBMC environment** -- these scripts run on a booted OpenBMC
> system (QEMU or hardware) with `phosphor-post-code-manager` and `bmcweb`
> services running.

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image (post-code-manager is included by default
#    on most platforms)
bitbake obmc-phosphor-image

# 2. Boot QEMU
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts to BMC
scp -P 2222 *.sh root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
cd /tmp
chmod +x *.sh
./read-current-postcode.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `read-current-postcode.sh` | Query current POST code via Redfish and busctl |
| `dump-boot-sequence.sh` | Retrieve and display the full POST code sequence from the last boot |
| `monitor-boot-progress.sh` | Poll BootProgress D-Bus property in real-time during host boot |

## D-Bus Services Used

| Service | Object Path | Interface |
|---------|-------------|-----------|
| `xyz.openbmc_project.State.Boot.PostCode0` | `/xyz/openbmc_project/State/Boot/PostCode0` | `xyz.openbmc_project.State.Boot.PostCode` |
| `xyz.openbmc_project.State.Host` | `/xyz/openbmc_project/state/host0` | `xyz.openbmc_project.State.Boot.Progress` |

## Redfish Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /redfish/v1/Systems/system` | `BootProgress` and `LastState` in system resource |
| `GET /redfish/v1/Systems/system/LogServices/PostCodes/Entries` | Full POST code log entries |

## Common POST Codes

| Code (hex) | Typical Meaning |
|------------|-----------------|
| `0x00` | Power on / reset |
| `0x19` | Pre-memory initialization |
| `0x33` | Memory initialization started |
| `0x50` | Memory initialization complete |
| `0x60` | Pre-DXE / PCI enumeration |
| `0xA0` | IDE / SATA initialization |
| `0xAD` | Ready to boot OS |
| `0xE0`-`0xFF` | Error codes (platform-specific) |

> POST code meanings vary by BIOS/UEFI vendor. Consult your platform firmware
> documentation for exact definitions.

## Troubleshooting

```bash
# Check post-code-manager daemon
systemctl status xyz.openbmc_project.State.Boot.PostCode0

# View post-code-manager logs
journalctl -u xyz.openbmc_project.State.Boot.PostCode0 -f

# Verify D-Bus service is registered
busctl list | grep PostCode

# Check if host is powered on (POST codes only appear during boot)
obmcutil state

# Verify snoop device exists (LPC POST code snoop)
ls -la /dev/aspeed-lpc-snoop0
```

## References

- [OpenBMC phosphor-post-code-manager](https://github.com/openbmc/phosphor-post-code-manager)
- [Redfish Systems schema](https://redfish.dmtf.org/schemas/v1/ComputerSystem.json) -- BootProgress property
- [AST2600 LPC POST code snoop driver](https://github.com/openbmc/linux/blob/dev-6.1/drivers/misc/aspeed-lpc-snoop.c)
