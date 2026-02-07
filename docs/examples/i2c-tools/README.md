# I2C Tools Examples

Shell scripts and device tree overlay for debugging and configuring I2C devices on OpenBMC.

> **Requires OpenBMC environment** -- these scripts run on a booted OpenBMC system
> (QEMU or hardware) with `i2c-tools` installed.

## Quick Start (QEMU)

```bash
# 1. Build OpenBMC image with i2c-tools
#    In your machine .conf or local.conf:
IMAGE_INSTALL:append = " i2c-tools "

# 2. Build and boot
bitbake obmc-phosphor-image
./scripts/run-qemu.sh ast2600-evb

# 3. Copy scripts to BMC
scp -P 2222 *.sh root@localhost:/tmp/

# 4. SSH in and run
ssh -p 2222 root@localhost
cd /tmp
chmod +x *.sh
./scan-all-buses.sh
./read-eeprom.sh 0 0x50
```

## Scripts

| Script | Description |
|--------|-------------|
| `scan-all-buses.sh [-b BUS]` | Scan all I2C buses (or a specific bus) with `i2cdetect` and format a summary |
| `read-eeprom.sh <bus> <address> [-r BYTES] [-o FILE]` | Read an EEPROM via `i2cdump` and format the output as a hex dump |

## Device Tree Overlay

| File | Description |
|------|-------------|
| `i2c-device-overlay.dts` | Sample device tree overlay adding a TMP75 temperature sensor at 0x48 on I2C bus 0 |

## Common I2C Addresses on OpenBMC Platforms

| Address | Typical Device | Description |
|---------|---------------|-------------|
| 0x48-0x4F | TMP75 / TMP175 | Temperature sensors |
| 0x50-0x57 | AT24C256 | FRU EEPROMs |
| 0x58-0x5F | PMBus PSU | Power supply controllers |
| 0x10-0x1F | ADM1275 | Hot-swap / current monitors |
| 0x20-0x27 | PCA9555 | GPIO expanders |
| 0x40-0x47 | INA219 / INA230 | Power monitors |

## Useful i2c-tools Commands

```bash
# List all I2C buses
i2cdetect -l

# Scan a specific bus for devices
i2cdetect -y 0

# Read a single register from a device
i2cget -y <bus> <addr> <register>

# Write a single register to a device
i2cset -y <bus> <addr> <register> <value>

# Dump all registers from a device
i2cdump -y <bus> <addr>

# Dump in byte mode (safest)
i2cdump -y -r 0x00-0xff <bus> <addr> b
```

## Applying the Device Tree Overlay

### Build-time (Yocto)

Add the overlay to your machine layer:

```bash
# In meta-myplatform/recipes-kernel/linux/linux-aspeed_%.bbappend:
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://i2c-device-overlay.dts"

# In your machine .conf:
KERNEL_DEVICETREE:append = " i2c-device-overlay.dtbo"
```

### Runtime (for testing)

```bash
# Compile the overlay
dtc -O dtb -o /tmp/i2c-device-overlay.dtbo i2c-device-overlay.dts

# Apply (if configfs overlay support is enabled)
mkdir -p /sys/kernel/config/device-tree/overlays/i2c-sensor
cat /tmp/i2c-device-overlay.dtbo > /sys/kernel/config/device-tree/overlays/i2c-sensor/dtbo

# Verify the device appeared
i2cdetect -y 0
ls /sys/bus/i2c/devices/
```

## Troubleshooting

```bash
# Check if i2c-tools is installed
which i2cdetect || echo "Install: IMAGE_INSTALL:append = \" i2c-tools \""

# List available I2C buses
ls /dev/i2c-*

# Check I2C bus driver loaded
dmesg | grep i2c

# Verify device tree nodes
ls /sys/bus/i2c/devices/

# Check hwmon sensor created from device tree
ls /sys/class/hwmon/
cat /sys/class/hwmon/hwmon*/name
cat /sys/class/hwmon/hwmon*/temp1_input

# I2C bus stuck? Check for SCL/SDA held low
cat /sys/kernel/debug/i2c/<bus>/state 2>/dev/null || echo "Debug FS not available"
```

## References

- [Linux I2C documentation](https://www.kernel.org/doc/html/latest/i2c/)
- [i2c-tools project](https://i2c.wiki.kernel.org/index.php/I2C_Tools)
- [OpenBMC device tree guide](https://github.com/openbmc/docs/blob/master/development/dev-environment.md)
- [TI TMP75 datasheet](https://www.ti.com/product/TMP75)
