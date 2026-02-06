# ARM Platform Example Layer

Example Yocto layer for porting OpenBMC to ARM-based server platforms.

## Overview

This example demonstrates:
- Layer configuration for ARM platforms
- Machine configuration with ARM-specific settings
- Device Tree patterns for BMC peripherals
- Integration with meta-arm layer stack

**Reference**: [NVIDIA OpenBMC](https://github.com/NVIDIA/openbmc) meta-nvidia layer

## Directory Structure

```
meta-arm-example/
├── conf/
│   ├── layer.conf              # Layer configuration
│   └── machine/
│       └── arm-example-bmc.conf  # Machine configuration
├── recipes-kernel/
│   └── linux/
│       └── arm-example-bmc.dts   # Device tree example
└── README.md
```

## Prerequisites

1. OpenBMC development environment set up
2. meta-arm layers cloned:
   ```bash
   cd /path/to/openbmc
   git clone https://git.yoctoproject.org/meta-arm
   ```

## Integration Steps

### 1. Add Layers to Build

Edit `conf/bblayers.conf`:

```bash
BBLAYERS += "${BSPDIR}/meta-arm/meta-arm"
BBLAYERS += "${BSPDIR}/meta-arm/meta-arm-toolchain"
BBLAYERS += "${BSPDIR}/meta-arm-example"
```

### 2. Set Machine

Edit `conf/local.conf`:

```bash
MACHINE = "arm-example-bmc"
```

### 3. Build

```bash
. setup arm-example-bmc
bitbake obmc-phosphor-image
```

## Key Configuration Points

### layer.conf

```bitbake
# Layer dependencies
LAYERDEPENDS_meta-arm-example = "meta-arm"

# Compatible releases
LAYERSERIES_COMPAT_meta-arm-example = "whinlatter walnascar"
```

### machine.conf

```bitbake
# ARM64 architecture
DEFAULTTUNE = "cortexa53"
require conf/machine/include/arm/armv8a/tune-cortexa53.inc

# Console device
SERIAL_CONSOLES = "115200;ttyAMA0"

# Flash layout
FLASH_SIZE = "65536"  # 64MB
```

### Device Tree

Key sections to customize:
- `chosen` - Boot parameters
- `i2c` - Sensor and FRU bus configuration
- `gpio` - Power control and buttons
- `spi` - Flash partitions

## Customization Checklist

- [ ] Update `DEFAULTTUNE` for your ARM CPU
- [ ] Configure `KERNEL_DEVICETREE` with your DT blob name
- [ ] Set `SERIAL_CONSOLES` for your UART device
- [ ] Adjust flash partition layout in machine.conf and DTS
- [ ] Add I2C devices for your sensors and FRUs
- [ ] Configure GPIO for power/reset control
- [ ] Update LED GPIO assignments

## References

- [ARM Platform Guide](../../../06-porting/06-arm-platform-guide.md)
- [Porting Reference](../../../06-porting/01-porting-reference.md)
- [meta-arm Layer](https://git.yoctoproject.org/meta-arm)
- [NVIDIA OpenBMC](https://github.com/NVIDIA/openbmc)

## License

This example is provided under the MIT license for educational purposes.
