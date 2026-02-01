---
layout: default
title: Porting Reference
parent: Porting
nav_order: 1
difficulty: advanced
prerequisites:
  - environment-setup
  - openbmc-overview
---

# Porting Reference
{: .no_toc }

Complete guide for porting OpenBMC to a new platform.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

Porting OpenBMC to a new platform involves creating a machine layer, configuring hardware-specific components, and integrating with the build system.

{: .note }
**ARM Server Platforms**: For ARM-based servers (NVIDIA Grace, Ampere, etc.), see the [ARM Platform Guide]({% link docs/06-porting/06-arm-platform-guide.md %}) which covers ARM-specific boot flow, meta-arm integration, and NVIDIA OpenBMC as a reference.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Porting Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Your Machine Layer                       ││
│  │                   (meta-myplatform)                         ││
│  │                                                             ││
│  │   ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐  ││
│  │   │conf/machine/ │ │ recipes-*    │ │ conf/layer.conf    │  ││
│  │   │ myboard.conf │ │ (customization)│ │ (layer metadata) │  ││
│  │   └──────────────┘ └──────────────┘ └────────────────────┘  ││
│  └─────────────────────────────────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                   OpenBMC Base Layers                       ││
│  │                                                             ││
│  │   ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐    ││
│  │   │meta-phosphor │ │meta-aspeed   │ │meta-openembedded │    ││
│  │   │(services)    │ │(BMC SoC)     │ │(base packages)   │    ││
│  │   └──────────────┘ └──────────────┘ └──────────────────┘    ││
│  └─────────────────────────────────────────────────────────────┘│
│                             │                                   │
│  ┌──────────────────────────┴──────────────────────────────────┐│
│  │                   BitBake Build System                      ││
│  │              (openbmc-env, bitbake)                         ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Before porting, ensure you have:

- [ ] BMC SoC datasheet and documentation
- [ ] Host system specifications
- [ ] Hardware schematic
- [ ] Working OpenBMC development environment
- [ ] QEMU or hardware for testing

---

## Porting Checklist

### 1. Layer Setup

- [ ] Create meta-myplatform layer
- [ ] Create conf/layer.conf
- [ ] Create conf/machine/myboard.conf
- [ ] Add to bblayers.conf

### 2. Machine Configuration

- [ ] Set MACHINE architecture (armv7/armv8)
- [ ] Configure BMC SoC (ASPEED/Nuvoton)
- [ ] Set kernel and U-Boot preferences
- [ ] Configure flash layout

### 3. Device Tree

- [ ] Create or modify device tree
- [ ] Configure GPIO mappings
- [ ] Configure I2C buses
- [ ] Configure SPI/UART/etc.

### 4. U-Boot

- [ ] Configure U-Boot for platform
- [ ] Set boot arguments
- [ ] Configure flash partitions

### 5. Kernel

- [ ] Enable required drivers
- [ ] Configure hwmon sensors
- [ ] Configure GPIO subsystem

### 6. OpenBMC Services

- [ ] Configure Entity Manager
- [ ] Configure sensor mappings
- [ ] Configure LED groups
- [ ] Configure power control

### 7. Verification

- [ ] Boot test on hardware/QEMU
- [ ] Sensor readings
- [ ] Power control
- [ ] Network connectivity
- [ ] Redfish/IPMI access

---

## Creating the Machine Layer

### Layer Structure

```
meta-myplatform/
├── conf/
│   ├── layer.conf
│   └── machine/
│       └── myboard.conf
├── recipes-bsp/
│   └── u-boot/
│       └── u-boot-aspeed_%.bbappend
├── recipes-kernel/
│   └── linux/
│       └── linux-aspeed_%.bbappend
├── recipes-phosphor/
│   ├── configuration/
│   │   └── entity-manager/
│   │       └── myboard-entity-config.bb
│   ├── sensors/
│   ├── leds/
│   └── power/
└── README.md
```

### layer.conf

```python
# conf/layer.conf

BBPATH .= ":${LAYERDIR}"

BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "meta-myplatform"
BBFILE_PATTERN_meta-myplatform = "^${LAYERDIR}/"
LAYERDEPENDS_meta-myplatform = " \
    core \
    meta-phosphor \
    meta-aspeed \
"
LAYERSERIES_COMPAT_meta-myplatform = "kirkstone mickledore scarthgap"
```

### machine.conf

```python
# conf/machine/myboard.conf

KERNEL_DEVICETREE = "aspeed/aspeed-bmc-myplatform-myboard.dtb"
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-aspeed"
PREFERRED_PROVIDER_u-boot = "u-boot-aspeed"
PREFERRED_PROVIDER_u-boot-fw-utils = "u-boot-aspeed-fw-utils"

# Distro features
DISTRO_FEATURES:append = " obmc-phosphor-fan-mgmt"
DISTRO_FEATURES:append = " obmc-phosphor-chassis-mgmt"
DISTRO_FEATURES:append = " obmc-host-state-mgmt"

# Image features
IMAGE_INSTALL:append = " \
    entity-manager-myboard \
    phosphor-led-manager \
    phosphor-fan-control \
"

# Flash layout
FLASH_SIZE = "32768"  # 32MB
require conf/machine/include/aspeed.inc
require conf/machine/include/obmc-bsp-common.inc

# Console settings
SERIAL_CONSOLES = "115200;ttyS4"

# Machine-specific features
MACHINE_FEATURES += "obmc-phosphor-fan-mgmt"
MACHINE_FEATURES += "obmc-phosphor-chassis-mgmt"
MACHINE_FEATURES += "obmc-host-state-mgmt"
```

---

## Device Tree Configuration

### Example Device Tree

```dts
// aspeed-bmc-myplatform-myboard.dts

/dts-v1/;

#include "aspeed-g5.dtsi"
#include <dt-bindings/gpio/aspeed-gpio.h>

/ {
    model = "MyPlatform MyBoard BMC";
    compatible = "myplatform,myboard-bmc", "aspeed,ast2500";

    chosen {
        stdout-path = &uart5;
        bootargs = "console=ttyS4,115200 earlyprintk";
    };

    memory@80000000 {
        reg = <0x80000000 0x20000000>;  /* 512MB */
    };

    reserved-memory {
        #address-cells = <1>;
        #size-cells = <1>;
        ranges;

        video_memory: video {
            size = <0x04000000>;  /* 64MB for video */
            alignment = <0x01000000>;
            compatible = "shared-dma-pool";
            reusable;
        };
    };

    leds {
        compatible = "gpio-leds";

        identify {
            label = "identify";
            gpios = <&gpio ASPEED_GPIO(A, 0) GPIO_ACTIVE_HIGH>;
            default-state = "off";
        };

        power {
            label = "power";
            gpios = <&gpio ASPEED_GPIO(A, 1) GPIO_ACTIVE_HIGH>;
            default-state = "on";
        };

        fault {
            label = "fault";
            gpios = <&gpio ASPEED_GPIO(A, 2) GPIO_ACTIVE_HIGH>;
            default-state = "off";
        };
    };

    gpio-keys {
        compatible = "gpio-keys";

        power-button {
            label = "power-button";
            gpios = <&gpio ASPEED_GPIO(B, 0) GPIO_ACTIVE_LOW>;
            linux,code = <116>;  /* KEY_POWER */
        };

        reset-button {
            label = "reset-button";
            gpios = <&gpio ASPEED_GPIO(B, 1) GPIO_ACTIVE_LOW>;
            linux,code = <0x198>;  /* KEY_RESTART */
        };
    };
};

&fmc {
    status = "okay";
    flash@0 {
        status = "okay";
        m25p,fast-read;
        label = "bmc";
        spi-max-frequency = <50000000>;
        #include "openbmc-flash-layout.dtsi"
    };
};

&spi1 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_spi1_default>;
    flash@0 {
        status = "okay";
        m25p,fast-read;
        label = "pnor";
        spi-max-frequency = <100000000>;
    };
};

&uart5 {
    status = "okay";
};

&mac0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_rmii1_default>;
    use-ncsi;
};

&i2c0 {
    status = "okay";

    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
        label = "cpu_temp";
    };
};

&i2c1 {
    status = "okay";

    eeprom@50 {
        compatible = "atmel,24c256";
        reg = <0x50>;
        label = "fru";
    };
};

&i2c2 {
    status = "okay";

    psu@58 {
        compatible = "pmbus";
        reg = <0x58>;
    };
};

&pwm_tacho {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_pwm0_default &pinctrl_pwm1_default>;

    fan@0 {
        reg = <0x00>;
        aspeed,fan-tach-ch = /bits/ 8 <0x00>;
    };

    fan@1 {
        reg = <0x01>;
        aspeed,fan-tach-ch = /bits/ 8 <0x01>;
    };
};

&video {
    status = "okay";
    memory-region = <&video_memory>;
};

&vuart {
    status = "okay";
};
```

---

## GPIO Configuration

### GPIO Pin Mapping

Create a GPIO mapping document:

```
# GPIO Pin Mapping for MyBoard

## Power Control
| Signal          | GPIO        | Direction | Active |
|-----------------|-------------|-----------|--------|
| POWER_BTN_IN    | GPIOB0      | Input     | Low    |
| POWER_OUT       | GPIOB2      | Output    | High   |
| RESET_BTN_IN    | GPIOB1      | Input     | Low    |
| RESET_OUT       | GPIOB3      | Output    | High   |

## Status Signals
| Signal          | GPIO        | Direction | Active |
|-----------------|-------------|-----------|--------|
| POST_COMPLETE   | GPIOC0      | Input     | High   |
| S0_SLP_S3       | GPIOC1      | Input     | Low    |
| S0_SLP_S5       | GPIOC2      | Input     | Low    |

## LEDs
| Signal          | GPIO        | Direction | Active |
|-----------------|-------------|-----------|--------|
| LED_IDENTIFY    | GPIOA0      | Output    | High   |
| LED_POWER       | GPIOA1      | Output    | High   |
| LED_FAULT       | GPIOA2      | Output    | High   |
```

### Power Control Configuration

```json
// recipes-phosphor/configuration/power-config/power-config.json
{
    "gpio_configs": [
        {
            "name": "power_button",
            "line_name": "POWER_BTN_IN",
            "direction": "input",
            "active_low": true
        },
        {
            "name": "power_out",
            "line_name": "POWER_OUT",
            "direction": "output",
            "active_low": false
        },
        {
            "name": "reset_button",
            "line_name": "RESET_BTN_IN",
            "direction": "input",
            "active_low": true
        },
        {
            "name": "reset_out",
            "line_name": "RESET_OUT",
            "direction": "output",
            "active_low": false
        }
    ]
}
```

---

## Entity Manager Configuration

### Board Configuration

```json
// recipes-phosphor/configuration/entity-manager/myboard.json
{
    "Exposes": [
        {
            "Name": "CPU_Temp",
            "Type": "TMP75",
            "Bus": 0,
            "Address": "0x48",
            "Thresholds": [
                {"Direction": "greater than", "Name": "upper critical", "Severity": 1, "Value": 95},
                {"Direction": "greater than", "Name": "upper non critical", "Severity": 0, "Value": 85},
                {"Direction": "less than", "Name": "lower critical", "Severity": 1, "Value": 0},
                {"Direction": "less than", "Name": "lower non critical", "Severity": 0, "Value": 5}
            ]
        },
        {
            "Name": "PSU1",
            "Type": "pmbus",
            "Bus": 2,
            "Address": "0x58"
        },
        {
            "Name": "FRU",
            "Type": "EEPROM",
            "Bus": 1,
            "Address": "0x50"
        }
    ],
    "Name": "MyBoard Baseboard",
    "Probe": "TRUE"
}
```

### Recipe for Configuration

```bitbake
# recipes-phosphor/configuration/entity-manager/myboard-entity-config.bb
SUMMARY = "MyBoard Entity Manager Configuration"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit allarch

SRC_URI = " \
    file://myboard.json \
"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0644 ${S}/myboard.json \
        ${D}${datadir}/entity-manager/configurations/
}

FILES:${PN} = "${datadir}/entity-manager/configurations/*"
```

---

## Verification Testing

### Boot Test

```bash
# Check boot messages
dmesg | less

# Verify services are running
systemctl status phosphor-*

# Check D-Bus objects
busctl tree xyz.openbmc_project.ObjectMapper
```

### Sensor Test

```bash
# Check sensors
busctl tree xyz.openbmc_project.Sensor

# Read temperature sensor
busctl get-property xyz.openbmc_project.HwmonTempSensor \
    /xyz/openbmc_project/sensors/temperature/CPU_Temp \
    xyz.openbmc_project.Sensor.Value Value

# Via Redfish
curl -k -u root:0penBmc \
    https://localhost/redfish/v1/Chassis/chassis/Sensors
```

### Power Control Test

```bash
# Check state
obmcutil state

# Power on
obmcutil poweron

# Power off
obmcutil poweroff
```

### Network Test

```bash
# Check interface
ip addr show eth0

# Test connectivity
ping -c 3 192.168.1.1
```

---

## Common Pitfalls

### Device Tree Issues

```bash
# Symptom: Device not found
# Check: Device tree binding
# Solution: Verify compatible string matches driver

# Symptom: Wrong GPIO polarity
# Check: GPIO flags in device tree
# Solution: Set GPIO_ACTIVE_LOW/HIGH correctly
```

### I2C Issues

```bash
# Symptom: Device not responding
# Check: I2C bus and address
i2cdetect -y 0

# Solution: Verify address and bus in device tree
```

### Service Failures

```bash
# Check service status
systemctl status phosphor-pid-control

# Check logs
journalctl -u phosphor-pid-control
```

---

## Debugging During Porting

When bringing up a new platform, kernel and service debugging is essential.

### Early Boot Debugging

For kernel bring-up, enable early console output:

```bash
# In device tree chosen node
chosen {
    bootargs = "console=ttyS4,115200 earlyprintk";
};

# Or via U-Boot
fw_setenv bootargs "console=ttyS4,115200 earlyprintk earlycon=uart8250,mmio32,0x1e784000"
```

### Kernel Debug Configuration

Add kernel debug options for porting:

```kconfig
# Recommended for porting
CONFIG_DEBUG_INFO=y
CONFIG_KASAN=y              # Kernel Address Sanitizer
CONFIG_PROVE_LOCKING=y      # Lock debugging
CONFIG_DEBUG_ATOMIC_SLEEP=y
CONFIG_STACKTRACE=y
```

### Memory and Runtime Debugging

For debugging services and applications on your new platform:

```bash
# Enable ASan for a specific recipe
CFLAGS:append:pn-<recipe> = " -fsanitize=address -fno-omit-frame-pointer"
LDFLAGS:append:pn-<recipe> = " -fsanitize=address"

# Run service under Valgrind
valgrind --leak-check=full /usr/bin/<service>
```

For comprehensive debugging tools including ASan, UBSan, TSan, Valgrind, and kernel debug options (KASAN, KCSAN, lockdep), see the **[Linux Debug Tools Guide]({% link docs/05-advanced/08-linux-debug-tools-guide.md %})**.

---

## eSPI Configuration

For Intel and AMD platforms using eSPI (Enhanced Serial Peripheral Interface) instead of LPC, additional configuration is required:

- **Virtual Wires**: Map host power state signals (SLP_S3, SLP_S5, PLTRST)
- **Flash Channel**: Configure eDAF if host BIOS is on BMC-attached flash
- **Console**: Set up eSPI UART for host console redirection

See the **[eSPI Guide]({% link docs/05-advanced/09-espi-guide.md %})** for complete eSPI configuration including device tree examples, kernel drivers, and troubleshooting.

---

## References

- [OpenBMC Machine Layer Examples](https://github.com/openbmc/openbmc/tree/master/meta-ibm)
- [ASPEED SDK Documentation](https://github.com/AspeedTech-BMC/openbmc)
- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [Add New System Guide](https://github.com/openbmc/docs/blob/master/development/add-new-system.md)

---

{: .note }
**Prerequisites**: Strong Yocto/BitBake knowledge, hardware access or accurate specifications
