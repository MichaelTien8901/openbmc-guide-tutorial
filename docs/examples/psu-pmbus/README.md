# PSU/PMBus Monitoring Examples

Shell scripts and configuration files for monitoring PMBus-based Power Supply Units
(PSUs) on OpenBMC. Covers reading sensor data from hwmon sysfs, decoding PMBus
STATUS_WORD, and configuring Entity Manager and phosphor-regulators.

> **Requires OpenBMC environment** -- these scripts run on a booted OpenBMC system
> (QEMU or hardware) with PMBus PSU drivers loaded and hwmon sysfs entries present.

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image with PSU monitoring support
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " phosphor-hwmon phosphor-psu-monitor phosphor-regulators "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts and configs to BMC
scp -P 2222 read-psu-status.sh root@localhost:/tmp/
scp -P 2222 entity-manager-psu.json root@localhost:/tmp/
scp -P 2222 regulators-config.json root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
chmod +x /tmp/read-psu-status.sh
/tmp/read-psu-status.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `read-psu-status.sh` | Read PSU voltage, current, power, temperature from hwmon sysfs; decode STATUS_WORD |
| `read-psu-status.sh --status-only` | Decode STATUS_WORD register without reading analog sensors |
| `read-psu-status.sh --json` | Output all sensor readings in JSON format |

## Configuration Files

| File | Install To | Description |
|------|-----------|-------------|
| `entity-manager-psu.json` | `/usr/share/entity-manager/configurations/` | Entity Manager config for dual redundant PMBus PSUs with sensor thresholds |
| `regulators-config.json` | `/usr/share/phosphor-regulators/` | phosphor-regulators JSON with PSU chip definitions and voltage rail monitoring |

## PMBus Sensor Labels (hwmon sysfs)

| hwmon Label | PMBus Command | Description | Unit |
|-------------|---------------|-------------|------|
| `in1_input` | READ_VIN (0x88) | Input voltage | mV |
| `in2_input` | READ_VOUT (0x8B) | Output voltage | mV |
| `curr1_input` | READ_IIN (0x89) | Input current | mA |
| `curr2_input` | READ_IOUT (0x8C) | Output current | mA |
| `power1_input` | READ_PIN (0x97) | Input power | uW |
| `power2_input` | READ_POUT (0x96) | Output power | uW |
| `temp1_input` | READ_TEMPERATURE_1 (0x8D) | Internal temperature | mC |
| `temp2_input` | READ_TEMPERATURE_2 (0x8E) | Secondary temperature | mC |
| `fan1_input` | READ_FAN_SPEED_1 (0x90) | Fan speed | RPM |

## STATUS_WORD Bit Definitions

| Bit | Name | Meaning |
|-----|------|---------|
| 15 | VOUT | Output voltage fault or warning |
| 14 | IOUT/POUT | Output current or power fault or warning |
| 13 | INPUT | Input voltage/current/power fault or warning |
| 12 | MFR_SPECIFIC | Manufacturer-specific fault |
| 11 | POWER_GOOD# | Power good negated |
| 10 | FANS | Fan fault or warning |
| 9 | OTHER | Other fault (OTP, OCP, memory) |
| 8 | UNKNOWN | Reserved / unknown |
| 7 | BUSY | PMBus busy, unable to respond |
| 6 | OFF | Unit not providing power (output off) |
| 5 | VOUT_OV | Output overvoltage fault |
| 4 | IOUT_OC | Output overcurrent fault |
| 3 | VIN_UV | Input undervoltage fault |
| 2 | TEMPERATURE | Temperature fault or warning |
| 1 | CML | Communication, memory, or logic fault |
| 0 | NONE_OF_THE_ABOVE | Other fault not covered by bits 1-7 |

## Yocto Build Configuration

### Enable PSU Monitoring in Image

```bitbake
IMAGE_INSTALL:append = " \
    phosphor-hwmon \
    phosphor-psu-monitor \
    phosphor-regulators \
    phosphor-power \
    i2c-tools \
"
```

### Enable PMBus Kernel Drivers

```kconfig
CONFIG_SENSORS_PMBUS=m
CONFIG_PMBUS=m
CONFIG_SENSORS_LM25066=m
CONFIG_SENSORS_UCD9000=m
CONFIG_SENSORS_ADM1275=m
CONFIG_SENSORS_IBM_CFFPS=m
CONFIG_SENSORS_INSPUR_IPSPS=m
CONFIG_SENSORS_MAX20730=m
CONFIG_SENSORS_TPS53679=m
```

## Troubleshooting

```bash
# List detected hwmon devices
ls /sys/class/hwmon/

# Identify which hwmon belongs to your PSU
cat /sys/class/hwmon/hwmon*/name

# Check if PMBus driver is bound
ls /sys/bus/i2c/drivers/pmbus/

# Manually bind a PMBus device (bus 3, address 0x58)
echo "pmbus 0x58" > /sys/bus/i2c/devices/i2c-3/new_device

# Check PSU monitor daemon
systemctl status phosphor-psu-monitor@0.service
journalctl -u phosphor-psu-monitor@0.service -f

# Read STATUS_WORD directly via i2cget (bus 3, addr 0x58)
i2cget -f -y 3 0x58 0x79 w

# List PSU D-Bus objects
busctl tree xyz.openbmc_project.PSUSensor
```

## References

- [PMBus Specification](https://pmbus.org/specifications) -- PMBus command set and data formats
- [phosphor-psu-monitor](https://github.com/openbmc/phosphor-power/tree/master/phosphor-psu-monitor) -- PSU presence and input fault monitoring
- [phosphor-regulators](https://github.com/openbmc/phosphor-power/tree/master/phosphor-regulators) -- Voltage regulator configuration and monitoring
- [Entity Manager](https://github.com/openbmc/entity-manager) -- Hardware configuration and sensor discovery
- [Linux PMBus driver](https://www.kernel.org/doc/html/latest/hwmon/pmbus.html) -- Kernel hwmon PMBus subsystem
