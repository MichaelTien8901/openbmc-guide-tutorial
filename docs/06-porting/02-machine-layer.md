---
layout: default
title: Machine Layer Guide
parent: Porting
nav_order: 2
difficulty: advanced
prerequisites:
  - porting-reference
---

# Machine Layer Guide
{: .no_toc }

Create a Yocto machine layer for your OpenBMC platform.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

A machine layer defines your specific hardware platform for OpenBMC. It contains machine configuration, recipes, and customizations.

---

## Layer Structure

```
meta-myplatform/
├── conf/
│   ├── layer.conf                    # Layer metadata
│   └── machine/
│       └── myboard.conf              # Machine configuration
├── recipes-bsp/
│   └── u-boot/
│       └── u-boot-aspeed_%.bbappend  # U-Boot customization
├── recipes-kernel/
│   └── linux/
│       ├── linux-aspeed_%.bbappend   # Kernel config
│       └── linux-aspeed/
│           └── myboard.cfg           # Kernel fragments
├── recipes-phosphor/
│   ├── configuration/
│   │   └── entity-manager/           # Hardware configuration
│   ├── leds/                         # LED configuration
│   ├── sensors/                      # Sensor customization
│   └── gpio/                         # GPIO configuration
└── README.md
```

---

## Creating layer.conf

```python
# conf/layer.conf

# Add layer to BBPATH
BBPATH .= ":${LAYERDIR}"

# Recipe locations
BBFILES += " \
    ${LAYERDIR}/recipes-*/*/*.bb \
    ${LAYERDIR}/recipes-*/*/*.bbappend \
"

# Layer identification
BBFILE_COLLECTIONS += "meta-myplatform"
BBFILE_PATTERN_meta-myplatform = "^${LAYERDIR}/"
BBFILE_PRIORITY_meta-myplatform = "10"

# Layer dependencies
LAYERDEPENDS_meta-myplatform = " \
    core \
    meta-phosphor \
    meta-aspeed \
"

# Compatible Yocto versions
LAYERSERIES_COMPAT_meta-myplatform = "kirkstone mickledore scarthgap"
```

---

## Machine Configuration

### Basic machine.conf

```python
# conf/machine/myboard.conf

#@TYPE: Machine
#@NAME: MyBoard BMC
#@DESCRIPTION: Machine configuration for MyBoard

# Kernel device tree
KERNEL_DEVICETREE = "aspeed/aspeed-bmc-myplatform-myboard.dtb"

# U-Boot configuration
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-aspeed"
PREFERRED_PROVIDER_u-boot = "u-boot-aspeed"
PREFERRED_PROVIDER_u-boot-fw-utils = "u-boot-aspeed-fw-utils"

# Flash size (KB)
FLASH_SIZE = "32768"

# Console
SERIAL_CONSOLES = "115200;ttyS4"

# Machine features - enable OpenBMC capabilities
MACHINE_FEATURES += " \
    obmc-phosphor-fan-mgmt \
    obmc-phosphor-chassis-mgmt \
    obmc-host-state-mgmt \
"

# Distro features
DISTRO_FEATURES:append = " obmc-ikvm"
DISTRO_FEATURES:append = " obmc-virtual-media"

# Packages to install
IMAGE_INSTALL:append = " \
    entity-manager \
    dbus-sensors \
    phosphor-pid-control \
    myboard-entity-config \
"

# Include base configuration
require conf/machine/include/aspeed.inc
require conf/machine/include/obmc-bsp-common.inc
```

### Feature Options

| Feature | Description |
|---------|-------------|
| `obmc-phosphor-fan-mgmt` | Fan control and monitoring |
| `obmc-phosphor-chassis-mgmt` | Chassis power control |
| `obmc-host-state-mgmt` | Host state management |
| `obmc-ikvm` | Remote KVM support |
| `obmc-virtual-media` | Virtual media support |

---

## Adding the Layer to Build

### Update bblayers.conf

```bash
# Add layer path
echo 'BBLAYERS += "/path/to/meta-myplatform"' >> build/conf/bblayers.conf
```

### Set Machine

```bash
# In local.conf
echo 'MACHINE = "myboard"' >> build/conf/local.conf
```

---

## Common Customizations

### Add Entity Manager Configuration

```bitbake
# recipes-phosphor/configuration/entity-manager/myboard-config.bb

SUMMARY = "MyBoard Entity Manager Configuration"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit allarch

SRC_URI = "file://myboard.json"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${datadir}/entity-manager/configurations
    install -m 0644 ${S}/myboard.json ${D}${datadir}/entity-manager/configurations/
}

FILES:${PN} = "${datadir}/entity-manager/configurations/*"
```

### Customize LED Configuration

```bitbake
# recipes-phosphor/leds/myboard-led-config.bb

SUMMARY = "MyBoard LED Configuration"
LICENSE = "Apache-2.0"

inherit allarch

SRC_URI = "file://led.yaml"

do_install() {
    install -d ${D}${datadir}/phosphor-led-manager
    install -m 0644 ${S}/led.yaml ${D}${datadir}/phosphor-led-manager/
}
```

---

## Building

```bash
# Initialize environment
. setup myboard

# Build image
bitbake obmc-phosphor-image
```

---

## Example Machine Layer

Working examples are available in the [examples/porting](https://github.com/MichaelTien8901/openbmc-guide-tutorial/tree/master/examples/porting) directory:

- `meta-myplatform/` - Complete template machine layer with Entity Manager configuration
- `README.md` - Quick start guide for customizing the template

---

## Next Steps

- [Device Tree]({% link docs/06-porting/03-device-tree.md %}) - Configure BMC SoC peripherals
- [Entity Manager Advanced]({% link docs/06-porting/07-entity-manager-advanced.md %}) - Dynamic hardware configuration

## References

- [Yocto Machine Configuration](https://docs.yoctoproject.org/ref-manual/variables.html#term-MACHINE)
- [OpenBMC Machine Examples](https://github.com/openbmc/openbmc/tree/master/meta-ibm)
- [meta-phosphor Documentation](https://github.com/openbmc/openbmc/tree/master/meta-phosphor)

---

{: .note }
**Prerequisites**: Yocto/BitBake experience required
