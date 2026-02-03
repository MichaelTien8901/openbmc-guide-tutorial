---
layout: default
title: ARM Platform Guide
parent: Porting
nav_order: 6
difficulty: advanced
prerequisites:
  - porting-reference
  - environment-setup
  - openbmc-overview
---

# ARM Platform Guide
{: .no_toc }

Port OpenBMC to ARM-based server platforms with NVIDIA OpenBMC as reference.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

This guide covers porting OpenBMC to ARM-based server platforms, using NVIDIA's OpenBMC fork as a reference implementation. While the [Porting Reference]({% link docs/06-porting/01-porting-reference.md %}) focuses on ASPEED-based BMCs managing x86 hosts, this guide addresses ARM-native server platforms where both the host and BMC may use ARM processors.

{: .note }
**Reference Repository**: [NVIDIA OpenBMC](https://github.com/NVIDIA/openbmc) (develop branch)

---

## ARM vs ASPEED Architecture

### Key Differences

```
+------------------------------------------------------------------+
|                    Traditional ASPEED BMC                        |
+------------------------------------------------------------------+
|                                                                  |
|  +------------------+          +----------------------------+    |
|  |   ASPEED BMC     |   LPC    |        x86 Host            |    |
|  |   (AST2500/2600) |<-------->|    (Intel/AMD CPU)         |    |
|  |                  |   eSPI   |                            |    |
|  +------------------+          +----------------------------+    |
|         |                                                        |
|         v                                                        |
|  +--------------+                                                |
|  | BMC manages  |                                                |
|  | x86 platform |                                                |
|  +--------------+                                                |
|                                                                  |
+------------------------------------------------------------------+

+------------------------------------------------------------------+
|                    ARM Server Platform                           |
+------------------------------------------------------------------+
|                                                                  |
|  +------------------+          +----------------------------+    |
|  |   ARM BMC        |   PCIe   |        ARM Host            |    |
|  |   (Various ARM   |<-------->|    (Grace, Ampere, etc.)   |    |
|  |    SoCs)         |   I2C    |                            |    |
|  +------------------+   MCTP   +----------------------------+    |
|         |                                                        |
|         v                                                        |
|  +--------------+                                                |
|  | BMC manages  |                                                |
|  | ARM platform |                                                |
|  +--------------+                                                |
|                                                                  |
+------------------------------------------------------------------+
```

| Aspect | ASPEED BMC | ARM Platform |
|--------|------------|--------------|
| **BMC SoC** | AST2500/AST2600 (ARM core) | Various ARM SoCs |
| **Host CPU** | x86 (Intel/AMD) | ARM (Grace, Ampere, etc.) |
| **Host Interface** | LPC, eSPI | PCIe, I2C, MCTP |
| **Boot Firmware** | ASPEED SDK | TF-A, OP-TEE, U-Boot |
| **Console** | VUART, LPC UART | Physical UART, SSH |
| **POST Codes** | LPC snoop | Platform-specific |

### Platform Communication

ARM platforms typically use different host-BMC communication methods:

| Interface | Description | Use Case |
|-----------|-------------|----------|
| **PCIe** | High-bandwidth link | Firmware updates, data transfer |
| **I2C/SMBus** | Low-speed control bus | Sensor polling, FRU access |
| **MCTP** | Management Component Transport | PLDM, SPDM messaging |
| **GPIO** | Direct signal control | Power control, reset, alerts |
| **Network** | Out-of-band management | Redfish, IPMI-over-LAN |

---

## meta-arm Layer Integration

ARM platforms use the Yocto Project's meta-arm layer stack for base support.

### Layer Stack

```
+------------------------------------------------------------------+
|                     Your Platform Layer                          |
|                    (meta-your-platform)                          |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    Vendor Layer (optional)                       |
|                     (meta-nvidia, etc.)                          |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    meta-arm-bsp                                  |
|              (Reference platform BSPs)                           |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    meta-arm                                      |
|              (ARM architecture recipes)                          |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    meta-arm-toolchain                            |
|              (GCC/Clang for ARM)                                 |
+------------------------------------------------------------------+
                              |
                              v
+------------------------------------------------------------------+
|                    OpenBMC Base Layers                           |
|         (meta-phosphor, meta-openembedded, poky)                 |
+------------------------------------------------------------------+
```

### Adding meta-arm to Your Build

```bash
# Clone meta-arm layers
cd /path/to/openbmc
git clone https://git.yoctoproject.org/meta-arm

# Add to bblayers.conf
cat >> conf/bblayers.conf << 'EOF'
BBLAYERS += "${BSPDIR}/meta-arm/meta-arm"
BBLAYERS += "${BSPDIR}/meta-arm/meta-arm-toolchain"
# Optional: Reference BSPs
# BBLAYERS += "${BSPDIR}/meta-arm/meta-arm-bsp"
EOF
```

### meta-arm Components

| Layer | Purpose | Key Recipes |
|-------|---------|-------------|
| **meta-arm** | Core ARM support | TF-A, OP-TEE, firmware |
| **meta-arm-toolchain** | ARM compilers | arm-gnu-toolchain, GCC |
| **meta-arm-bsp** | Reference platforms | FVP, Juno, N1SDP |

---

## Machine Configuration

### ARM Machine Template

Create your machine configuration based on ARM patterns:

```bitbake
# conf/machine/myarm-bmc.conf

#@TYPE: Machine
#@NAME: My ARM BMC Platform
#@DESCRIPTION: OpenBMC for ARM-based server

# ARM64 architecture
DEFAULTTUNE = "cortexa53"
require conf/machine/include/arm/armv8a/tune-cortexa53.inc

# Kernel configuration
PREFERRED_PROVIDER_virtual/kernel = "linux-aspeed"
KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = "${KMACHINE}.dtb"

# U-Boot configuration
PREFERRED_PROVIDER_virtual/bootloader = "u-boot"
PREFERRED_PROVIDER_u-boot = "u-boot"
UBOOT_MACHINE = "myarm_bmc_defconfig"

# Flash layout (adjust for your platform)
FLASH_SIZE = "65536"  # 64MB
FLASH_UBOOT_OFFSET = "0"
FLASH_KERNEL_OFFSET = "1024"
FLASH_ROFS_OFFSET = "10240"
FLASH_RWFS_OFFSET = "49152"

# Console configuration
SERIAL_CONSOLES = "115200;ttyAMA0"

# Machine features
MACHINE_FEATURES = "efi"

# OpenBMC features - customize for your platform
OBMC_MACHINE_FEATURES += "\
    obmc-bmc-state-mgmt \
    obmc-phosphor-fan-mgmt \
    obmc-phosphor-flash-mgmt \
"

# Entity Manager for inventory
VIRTUAL-RUNTIME_obmc-inventory-manager = "entity-manager"
```

### Key ARM Machine Variables

| Variable           | Description       | Example                           |
|--------------------|-------------------|-----------------------------------|
| `DEFAULTTUNE`      | CPU tuning        | `cortexa53`, `cortexa72`          |
| `KERNEL_IMAGETYPE` | Kernel format     | `Image` (ARM64), `zImage` (ARM32) |
| `SERIAL_CONSOLES`  | Console device    | `115200;ttyAMA0`                  |
| `MACHINE_FEATURES` | Platform features | `efi`, `optee`                    |

---

## NVIDIA OpenBMC Reference

NVIDIA's OpenBMC fork provides a production-quality reference for ARM platforms.

### Repository Structure

```
NVIDIA/openbmc (develop branch)
├── meta-nvidia/
│   ├── conf/
│   │   └── layer.conf                    # Layer configuration
│   ├── meta-common/                      # Shared components
│   ├── meta-prime/                       # Server platform support
│   │   └── meta-graceblackwell/          # Grace Blackwell
│   │       └── meta-gb200nvl/            # GB200 NVL machine
│   │           └── meta-bmc/
│   │               └── conf/machine/
│   │                   ├── gb200nvl-bmc.conf
│   │                   └── gb200nvl-bmc-ut3.conf
│   ├── recipes-phosphor/                 # OpenBMC customizations
│   └── recipes-nvidia/                   # NVIDIA-specific recipes
```

**Reference**: [meta-nvidia/conf/layer.conf](https://github.com/NVIDIA/openbmc/blob/develop/meta-nvidia/conf/layer.conf)

### NVIDIA Layer Configuration

The NVIDIA layer configuration demonstrates vendor layer patterns:

```bitbake
# Reference: meta-nvidia/conf/layer.conf
# https://github.com/NVIDIA/openbmc/blob/develop/meta-nvidia/conf/layer.conf

# Layer name and compatibility
BBFILE_COLLECTIONS += "nvidia-layer"
LAYERSERIES_COMPAT_nvidia-layer = "whinlatter walnascar"

# Recipe patterns
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"
```

**Key patterns (NVIDIA-specific)**:
- Uses nested meta-* layers for platform hierarchy
- Separate layers for BMC, HMC (Hardware Management Controller), PMC (Power Management Controller)
- Repository mirroring for internal GitLab → GitHub

**Generic ARM patterns**:
- Standard layer.conf structure
- Recipe organization by function (recipes-phosphor, recipes-kernel, etc.)

### NVIDIA Machine Configuration Example

From `meta-nvidia/meta-prime/meta-graceblackwell/meta-gb200nvl/meta-bmc/conf/machine/gb200nvl-bmc.conf`:

```bitbake
# Reference: gb200nvl-bmc.conf
# NVIDIA GB200 NVL BMC - uses ASPEED AST2600 as BMC SoC

# Device tree
KERNEL_DEVICETREE = "aspeed-bmc-nvidia-gb200nvl-bmc.dtb"

# U-Boot
UBOOT_MACHINE = "ast2600_openbmc_spl_defconfig"
SPL_BINARY = "spl/u-boot-spl.bin"

# Flash layout (64MB)
FLASH_SIZE = "65536"
FLASH_UBOOT_OFFSET:flash-65536 = "0"
FLASH_KERNEL_OFFSET:flash-65536 = "1024"
FLASH_ROFS_OFFSET:flash-65536 = "10240"

# Console
SERIAL_CONSOLES = "115200;ttyS4"

# Use Entity Manager
VIRTUAL-RUNTIME_obmc-inventory-manager = "entity-manager"

# Feature selection
OBMC_IMAGE_EXTRA_INSTALL:remove = "phosphor-snmp"
```

{: .note }
**Note**: The GB200 NVL uses an ASPEED AST2600 as the BMC SoC managing an ARM Grace Hopper host. This is a hybrid architecture.

---

## ARM Boot Flow

ARM platforms use a standardized boot flow with Trusted Firmware-A (TF-A).

### Boot Sequence

```
+------------------------------------------------------------------+
|                      ARM Boot Flow                               |
+------------------------------------------------------------------+
|                                                                  |
|  +------------+     +------------+     +------------+            |
|  |   BL1      |---->|   BL2      |---->|   BL31     |            |
|  | (ROM/Flash)|     | (Trusted   |     | (Secure    |            |
|  |            |     |  Boot)     |     |  Monitor)  |            |
|  +------------+     +------------+     +------+-----+            |
|                                               |                  |
|                           +-------------------+                  |
|                           |                                      |
|                           v                                      |
|  +------------+     +------------+     +------------+            |
|  |   BL32     |     |   BL33     |---->|   Linux    |            |
|  | (OP-TEE)   |     | (U-Boot)   |     |  Kernel    |            |
|  | (Optional) |     |            |     |            |            |
|  +------------+     +------------+     +------------+            |
|                                                                  |
+------------------------------------------------------------------+

Legend:
  BL1  - Boot Loader Stage 1 (ROM or first-stage flash)
  BL2  - Trusted Boot Firmware
  BL31 - EL3 Runtime Firmware (Secure Monitor)
  BL32 - Secure Payload (OP-TEE, optional)
  BL33 - Non-secure Bootloader (U-Boot)
```

### Boot Components

| Stage | Component | Description |
|-------|-----------|-------------|
| BL1 | ROM/Flash | First boot code, initializes BL2 |
| BL2 | TF-A | Trusted boot, loads BL31/BL32/BL33 |
| BL31 | TF-A Runtime | Secure Monitor, handles SMC calls |
| BL32 | OP-TEE | Trusted execution environment (optional) |
| BL33 | U-Boot | Standard bootloader, loads Linux |

### TF-A Configuration

```bitbake
# recipes-bsp/trusted-firmware-a/trusted-firmware-a_%.bbappend

# Platform-specific TF-A configuration
TFA_PLATFORM = "myarm"
TFA_BUILD_TARGET = "bl31"

# Optional: Enable secure boot
TFA_MBEDTLS_DIR = "${STAGING_DIR_HOST}${libdir}"
TFA_ARM_ARCH = "8.0"
```

### U-Boot for ARM Platforms

```bitbake
# recipes-bsp/u-boot/u-boot_%.bbappend

# ARM-specific U-Boot configuration
UBOOT_MACHINE = "myarm_bmc_defconfig"

# Enable FIT images for secure boot
UBOOT_MKIMAGE_DTCOPTS = "-I dts -O dtb -p 2000"
UBOOT_SIGN_ENABLE = "1"
```

---

## ARM Device Tree

ARM platforms use standard Device Tree conventions with some BMC-specific patterns.

### Device Tree Structure

```dts
// myarm-bmc.dts
/dts-v1/;

#include "arm-soc-base.dtsi"

/ {
    model = "My ARM BMC Platform";
    compatible = "vendor,myarm-bmc", "arm,cortex-a53";

    chosen {
        stdout-path = "serial0:115200n8";
    };

    aliases {
        serial0 = &uart0;
        i2c0 = &i2c0;
    };
};

// I2C bus for sensor/FRU access
&i2c0 {
    status = "okay";
    clock-frequency = <100000>;

    // Temperature sensor
    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
    };

    // FRU EEPROM
    eeprom@50 {
        compatible = "atmel,24c64";
        reg = <0x50>;
    };
};

// GPIO for platform control
&gpio0 {
    status = "okay";

    power-button {
        gpios = <&gpio0 10 GPIO_ACTIVE_LOW>;
        linux,code = <KEY_POWER>;
    };

    reset-button {
        gpios = <&gpio0 11 GPIO_ACTIVE_LOW>;
        linux,code = <KEY_RESTART>;
    };
};
```

### Common ARM Bindings

| Peripheral | Binding | Example |
|------------|---------|---------|
| UART | `arm,pl011` | Console, host UART |
| I2C | `arm,versatile-i2c` | Sensors, EEPROMs |
| SPI | `arm,pl022` | Flash access |
| GPIO | `arm,pl061` | Power control |
| Watchdog | `arm,sp805` | System watchdog |

---

## MCTP/PLDM Integration

ARM platforms often use MCTP/PLDM for host-BMC communication.

See the [MCTP/PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %}) for detailed information.

### Common Configuration

```json
// Entity Manager MCTP endpoint configuration
{
    "Exposes": [
        {
            "Name": "Host MCTP Endpoint",
            "Type": "MCTPEndpoint",
            "Bus": 1,
            "Address": "0x08",
            "MessageTypes": ["PLDM", "SPDM"]
        }
    ]
}
```

---

## Example ARM Machine Layer

Working examples are available in the [examples/porting/meta-arm-example](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/examples/porting/meta-arm-example) directory:

- `conf/machine/` - ARM-specific machine configuration template
- `recipes-kernel/` - Kernel customization for ARM platforms
- `README.md` - ARM platform porting quick start

---

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No console output | Wrong UART device | Check `SERIAL_CONSOLES` in machine.conf |
| Kernel panic on boot | Missing DT bindings | Verify device tree compatible strings |
| I2C devices not found | Bus numbering mismatch | Check DT aliases and bus assignments |
| TF-A build fails | Missing platform files | Implement platform-specific TF-A port |

### Debug Tips

```bash
# Check boot messages
dmesg | grep -i arm

# Verify device tree
cat /proc/device-tree/model

# List I2C buses
i2cdetect -l

# Check MCTP endpoints
busctl tree xyz.openbmc_project.MCTP
```

---

## References

- [NVIDIA OpenBMC Repository](https://github.com/NVIDIA/openbmc)
- [meta-arm Layer](https://git.yoctoproject.org/meta-arm)
- [Trusted Firmware-A Documentation](https://trustedfirmware-a.readthedocs.io/)
- [ARM Architecture Reference](https://developer.arm.com/documentation)
- [OpenBMC Porting Reference]({% link docs/06-porting/01-porting-reference.md %})
- [MCTP/PLDM Guide]({% link docs/05-advanced/01-mctp-pldm-guide.md %})
- [Entity Manager Guide]({% link docs/03-core-services/03-entity-manager-guide.md %})

---

{: .note }
**Tested on**: Reference documentation only - requires platform-specific hardware for validation.
