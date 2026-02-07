# PECI Examples

Shell scripts and configuration files for working with PECI (Platform Environment
Control Interface) CPU temperature monitoring on OpenBMC.

> **Requires OpenBMC environment** -- these scripts run on a booted OpenBMC system
> (QEMU or hardware) with PECI support enabled in the kernel and `peci_cmds`
> utility installed.

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image with PECI support
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " peci-pcie "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts to BMC
scp -P 2222 *.sh root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
cd /tmp
chmod +x *.sh
./peci-probe.sh
./read-cpu-temps.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `peci-probe.sh` | Probe PECI bus: ping CPU, read package config, verify connectivity |
| `read-cpu-temps.sh` | Read CPU and DIMM temperatures from hwmon sysfs and format output |

## Configuration Files

| File | Install To | Description |
|------|-----------|-------------|
| `entity-manager-peci.json` | `/usr/share/entity-manager/configurations/` | Entity Manager config for PECI CPU temperature sensor discovery |

## PECI Overview

PECI is a single-wire interface between the BMC and Intel CPUs. It provides access
to CPU thermal data, power metrics, and configuration registers without requiring
in-band software on the host.

```
BMC (AST2600)                    Intel CPU
     |                                |
     |--- PECI bus (single wire) ---->|
     |                                |
     |    Ping                        |
     |    RdPkgConfig (CPU temp)      |
     |    RdIAMSR (model-specific)    |
     |    WrPkgConfig                 |
     |    GetDIB (device info)        |
```

### Common PECI Client Addresses

| Address | Typical Device |
|---------|---------------|
| 0x30 | CPU 0 |
| 0x31 | CPU 1 |
| 0x32 | CPU 2 |
| 0x33 | CPU 3 |

## Yocto Build Configuration

### Enable PECI in Image

```bitbake
# local.conf or machine .conf
IMAGE_INSTALL:append = " \
    peci-pcie \
"
```

### Kernel Configuration

```kconfig
# Enable PECI subsystem
CONFIG_PECI=y
CONFIG_PECI_ASPEED=y

# Enable PECI hwmon driver for CPU temperatures
CONFIG_SENSORS_PECI_CPUTEMP=y
CONFIG_SENSORS_PECI_DIMMTEMP=y
```

### Device Tree (AST2600)

```dts
&peci0 {
    status = "okay";
    /* PECI bus speed: 1 MHz typical */
    clock-frequency = <1000000>;
};
```

## Troubleshooting

```bash
# Check PECI bus is detected
ls /sys/bus/peci/devices/

# Check hwmon sensors created by PECI driver
ls /sys/class/hwmon/

# Find which hwmon device is the PECI CPU temp sensor
for d in /sys/class/hwmon/hwmon*; do
    name=$(cat "$d/name" 2>/dev/null)
    echo "$d: $name"
done

# Ping CPU 0 directly
peci_cmds Ping 0x30

# Read package configuration (CPU temp)
peci_cmds RdPkgConfig 0x30 0 0

# Check kernel logs for PECI errors
dmesg | grep -i peci

# Check Entity Manager detected PECI sensors
busctl tree xyz.openbmc_project.EntityManager | grep -i peci
```

## References

- [Intel PECI specification](https://www.intel.com/content/www/us/en/developer/articles/technical/platform-environment-control-interface-peci.html)
- [OpenBMC dbus-sensors (peci)](https://github.com/openbmc/dbus-sensors)
- [Entity Manager](https://github.com/openbmc/entity-manager)
- [Linux PECI subsystem](https://docs.kernel.org/admin-guide/peci/index.html)
