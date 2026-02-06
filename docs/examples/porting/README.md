# Porting Examples

This directory contains a template machine layer for porting OpenBMC to a new platform.

## Directory Structure

```
meta-myplatform/
├── conf/
│   ├── layer.conf              # Layer configuration
│   └── machine/
│       └── myboard.conf        # Machine configuration
├── recipes-bsp/
│   └── u-boot/
│       └── u-boot-aspeed_%.bbappend    # U-Boot customization
├── recipes-kernel/
│   └── linux/
│       └── linux-aspeed_%.bbappend     # Kernel customization
└── recipes-phosphor/
    └── configuration/
        └── entity-manager/
            ├── myboard-entity-config.bb  # Recipe for EM config
            └── files/
                └── myboard.json          # Board configuration
```

## Quick Start

### 1. Copy the Template

```bash
cp -r meta-myplatform /path/to/openbmc/
```

### 2. Customize for Your Platform

Edit the following files:

- `conf/machine/myboard.conf` - Machine settings, features, flash size
- `recipes-phosphor/configuration/entity-manager/files/myboard.json` - Sensors, FRU, hardware

### 3. Create Device Tree

Create or modify device tree in `recipes-kernel/linux/`:
- Add GPIO mappings
- Configure I2C devices
- Set up SPI flash
- Configure UART console

### 4. Add to Build

```bash
# Add layer to bblayers.conf
echo 'BBLAYERS += "/path/to/openbmc/meta-myplatform"' >> build/conf/bblayers.conf

# Set machine
echo 'MACHINE = "myboard"' >> build/conf/local.conf

# Build
bitbake obmc-phosphor-image
```

## Customization Points

### Power Control GPIOs

Edit `myboard.json` to set power button, power output, reset button, and status signals.

### Sensors

Configure I2C sensors, hwmon sensors, and ADC channels in `myboard.json`.

### LEDs

Define LED GPIO pins in device tree and configure groups in LED configuration.

### Network

Configure Ethernet MAC, NCSI, or dedicated port in device tree.

## Verification

After building and booting:

```bash
# Check state
obmcutil state

# Check sensors
busctl tree xyz.openbmc_project.Sensor

# Test power control
obmcutil poweron
obmcutil poweroff

# Test network
ip addr show eth0
curl -k -u root:0penBmc https://localhost/redfish/v1/
```

## References

- [Add New System Guide](https://github.com/openbmc/docs/blob/master/development/add-new-system.md)
- [Yocto Machine Configuration](https://docs.yoctoproject.org/ref-manual/variables.html#term-MACHINE)
- [Entity Manager Configuration](https://github.com/openbmc/entity-manager)
