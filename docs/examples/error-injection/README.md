# RAS Error Injection Examples

Shell scripts for RAS (Reliability, Availability, Serviceability) error injection
and validation testing on OpenBMC platforms.

> **WARNING: These scripts inject hardware errors** -- they can cause system crashes,
> data corruption, and unexpected reboots. Only run on dedicated test systems, never
> on production hardware. Each script requires explicit confirmation before injection.

> **Requires OpenBMC environment** -- these scripts run on a booted OpenBMC system
> (QEMU or hardware) with host power on. The host must have ACPI EINJ support
> enabled in BIOS/UEFI and the BMC must have `peci_cmds` installed for PECI-based
> injection.

## Quick Start (Test Environment)

```bash
# 1. Build OpenBMC image with RAS support
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " peci-pcie crashdump "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts to BMC
scp -P 2222 *.sh root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
cd /tmp
chmod +x *.sh

# 5. Run individual injection (with confirmation prompt)
./einj-inject-error.sh ce          # Correctable memory error
./peci-inject-mca.sh 0 0           # MCA on CPU 0, bank 0

# 6. Run full validation workflow
./ras-validation-workflow.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `einj-inject-error.sh <type>` | Inject errors via ACPI EINJ sysfs interface (memory CE, memory UCE, PCIe fatal) |
| `peci-inject-mca.sh <cpu> <bank>` | Inject MCA bank errors via PECI `peci_cmds` for MCE testing |
| `ras-validation-workflow.sh` | End-to-end RAS validation: inject CE, MCE, PCIe errors and verify BMC-side responses |

## Error Types

### ACPI EINJ Error Types

| Type | Value | Description | Expected BMC Response |
|------|-------|-------------|----------------------|
| `ce` | 0x00000008 | Correctable memory error | SEL entry logged |
| `uce` | 0x00000010 | Uncorrectable memory error (non-fatal) | SEL entry + crash dump triggered |
| `fatal` | 0x00000020 | Uncorrectable memory error (fatal) | Host reset + crash dump |
| `pcie-ce` | 0x00000040 | PCIe correctable error | SEL entry logged |
| `pcie-fatal` | 0x00000100 | PCIe fatal error | SEL entry + event log |

### MCA Bank Error Injection

| Bank | Typical Source | Description |
|------|---------------|-------------|
| 0 | DCU | Data Cache Unit errors |
| 1 | IFU | Instruction Fetch Unit errors |
| 4 | PCU | Power Control Unit errors |
| 5-12 | CBO | Last-Level Cache errors |
| 13-16 | MLC | Mid-Level Cache errors |

## Prerequisites

### Host-Side Requirements
- ACPI EINJ enabled in BIOS/UEFI settings
- EINJ kernel module loaded: `modprobe einj`
- EINJ sysfs available: `/sys/kernel/debug/apei/einj/`

### BMC-Side Requirements
- PECI interface operational: `peci_cmds` tool available
- Crash dump service enabled: `systemctl status crashdump`
- IPMI SEL logging active: `ipmitool sel list`

### QEMU Limitations
- ACPI EINJ is not available in QEMU -- `einj-inject-error.sh` requires real hardware
  or a host VM with EINJ passthrough
- PECI injection in QEMU depends on the PECI emulation support in your AST2600 model

## Verification Checklist

After running error injection, verify the following BMC-side responses:

```bash
# Check IPMI SEL for new entries
ipmitool -I lanplus -H <bmc-ip> -U admin -P password sel list

# Check OpenBMC event logs
busctl tree xyz.openbmc_project.Logging

# Check Redfish event log
curl -sk -u root:0penBmc \
    https://localhost:2443/redfish/v1/Systems/system/LogServices/EventLog/Entries

# Check crash dump files
ls -la /var/lib/crashdump/

# Check host state after fatal injection
obmcutil state
```

## Troubleshooting

```bash
# Verify PECI connectivity
peci_cmds ping -a 0x30

# Check EINJ availability (on host)
ls /sys/kernel/debug/apei/einj/

# Check crash dump daemon
systemctl status crashdump
journalctl -u crashdump -f

# Check SEL status
ipmitool sel info

# Enable PECI debug logging
journalctl -u peci-pcie -f
```

## References

- [ACPI EINJ documentation](https://www.kernel.org/doc/html/latest/firmware-guide/acpi/apei/einj.html)
- [Intel PECI specification](https://www.intel.com/content/www/us/en/developer/articles/technical/platform-environment-control-interface-peci-client-command-specification.html)
- [OpenBMC crashdump](https://github.com/openbmc/crashdump)
- [OpenBMC peci-pcie](https://github.com/openbmc/peci-pcie)
