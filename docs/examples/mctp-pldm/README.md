# MCTP/PLDM Examples

Shell scripts and configuration files for working with MCTP (Management Component
Transport Protocol) and PLDM (Platform Level Data Model) on OpenBMC.

> **Requires OpenBMC environment** — these scripts run on a booted OpenBMC system
> (QEMU or hardware) with `mctpd`, `pldmd`, and `pldmtool` installed.

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image with MCTP/PLDM support
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " mctp mctpd libpldm pldm "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts to BMC
scp -P 2222 *.sh root@localhost:/tmp/
scp -P 2222 -r config/ root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
cd /tmp
chmod +x *.sh
./mctp_health_check.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `mctp_health_check.sh` | Verify MCTP/PLDM stack: daemons, links, endpoints, D-Bus services |
| `pldm_discovery.sh <eid>` | Discover PLDM endpoint: TID, supported types, available commands |
| `pldm_sensors.sh <eid>` | Read numeric and state sensors from PDR repository |
| `pldm_pdr_dump.sh <eid>` | Dump Platform Descriptor Records (sensors, effecters, entities) |
| `pldm_bios.sh <eid>` | Read BIOS tables and attributes (PLDM Type 3) |
| `pldm_fwupdate.sh <eid>` | Query firmware update capabilities (PLDM Type 5) |

## Configuration Files

| File | Install To | Description |
|------|-----------|-------------|
| `config/static-endpoints.json` | `/etc/mctp/static-endpoints.json` | Static MCTP endpoint definitions (I2C addresses, EIDs) |
| `config/pdr.json` | `/usr/share/pldm/pdr/pdr.json` | PDR repository: terminus locator, sensors, entity associations |
| `config/pldm-dbus.conf` | `/etc/dbus-1/system.d/pldm.conf` | D-Bus access policy for PLDM service |

## Common MCTP Endpoint IDs

| EID | Typical Device | PLDM Types |
|-----|---------------|------------|
| 8 | BMC (local) | 0, 2 |
| 9 | Host CPU/BIOS | 0, 2, 3 (BIOS), 5 (FW Update) |
| 10 | GPU | 0, 2, 5 |
| 11 | NVMe / PSU | 0, 2 |

## Yocto Build Configuration

### Enable MCTP/PLDM in Image

```bitbake
# local.conf or machine .conf
IMAGE_INSTALL:append = " \
    mctp \
    mctpd \
    libpldm \
    pldm \
"
```

### Configure MCTP Transport

```bitbake
EXTRA_OEMESON:pn-mctpd = " \
    -Di2c=enabled \
    -Dastlpc=enabled \
    -Dserial=disabled \
"
```

### Configure PLDM Options

```bitbake
EXTRA_OEMESON:pn-pldm = " \
    -Dtransport-implementation=af-mctp \
    -Doem-ibm=disabled \
    -Dsoftoff=enabled \
    -Dhost-eid=9 \
    -Dlibpldmresponder=enabled \
"
```

### Kernel Configuration

```kconfig
CONFIG_MCTP=y
CONFIG_MCTP_FLOWS=y
CONFIG_I2C_MCTP=m
CONFIG_MCTP_SERIAL=m
```

## Troubleshooting

```bash
# Check daemon status
systemctl status mctpd pldmd

# View logs
journalctl -u mctpd -f
journalctl -u pldmd -f

# List MCTP links and endpoints
mctp link
mctp endpoint

# Enable debug logging
systemctl edit pldmd
# Add: Environment="PLDM_VERBOSITY=debug"
systemctl restart pldmd

# Raw PLDM command (GetTID)
pldmtool raw -m 9 -d 0x80 0x00 0x02

# Increase timeout for slow endpoints
pldmtool --timeout 30000 base getTID -m 9
```

## References

- [MCTP/PLDM Guide](../../05-advanced/01-mctp-pldm-guide.md) — full protocol details and architecture
- [OpenBMC PLDM repo](https://github.com/openbmc/pldm)
- [OpenBMC MCTP repo](https://github.com/openbmc/mctp)
- [DMTF PLDM specifications](https://www.dmtf.org/standards/pldm)
- [DMTF MCTP specifications](https://www.dmtf.org/standards/mctp)
