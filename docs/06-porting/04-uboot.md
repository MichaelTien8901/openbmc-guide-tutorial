---
layout: default
title: U-Boot Guide
parent: Porting
nav_order: 4
difficulty: advanced
prerequisites:
  - device-tree
---

# U-Boot Guide
{: .no_toc }

Configure the U-Boot bootloader for your BMC platform.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

U-Boot is the bootloader for OpenBMC. It initializes hardware, loads the Linux kernel, and supports dual-image boot for failsafe recovery.

---

## U-Boot Configuration

### Default Configuration

```make
# configs/ast2500_openbmc_defconfig

CONFIG_ARM=y
CONFIG_ARCH_ASPEED=y
CONFIG_SYS_TEXT_BASE=0x00000000
CONFIG_ASPEED_AST2500=y
CONFIG_TARGET_MYBOARD=y
CONFIG_DEFAULT_DEVICE_TREE="aspeed-bmc-myplatform-myboard"
CONFIG_FIT=y
CONFIG_FIT_SIGNATURE=y
CONFIG_SPL=y
```

### Board Configuration

```c
// include/configs/myboard.h

#ifndef __CONFIG_MYBOARD_H
#define __CONFIG_MYBOARD_H

#include <configs/aspeed-common.h>

#define CONFIG_MACH_TYPE    MACH_TYPE_ASPEED

/* Memory */
#define CONFIG_SYS_SDRAM_SIZE   0x20000000  /* 512MB */

/* Flash */
#define CONFIG_SYS_MAX_FLASH_BANKS  1
#define CONFIG_SYS_MAX_FLASH_SECT   512

/* Console */
#define CONFIG_CONS_INDEX   5  /* UART5 */
#define CONFIG_BAUDRATE     115200

/* Boot */
#define CONFIG_BOOTCOMMAND  "run bootcmd_obmc"
#define CONFIG_BOOTARGS     "console=ttyS4,115200 earlyprintk"

#endif
```

---

## Environment Variables

### Key Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `bootcmd` | Boot command | `run bootcmd_obmc` |
| `bootargs` | Kernel arguments | `console=ttyS4,115200` |
| `bootside` | Active boot partition | `a` or `b` |
| `bootcount` | Boot attempt counter | `0` |
| `bootlimit` | Max boot attempts | `3` |

### Boot Commands

```bash
# Default boot command
bootcmd_obmc=run set_bootargs; bootm ${kerneladdr}

# Set boot arguments
set_bootargs=setenv bootargs console=ttyS4,115200 root=/dev/ram rw

# Load kernel
loadkernel=sf probe 0; sf read ${kerneladdr} ${kerneloff} ${kernelsize}
```

---

## Dual Boot Support

### Partition Layout

```
┌──────────────────────────────────────┐
│           U-Boot SPL                 │ 0x000000
├──────────────────────────────────────┤
│           U-Boot                     │ 0x080000
├──────────────────────────────────────┤
│        U-Boot Environment            │ 0x100000
├──────────────────────────────────────┤
│        Image A (Active)              │ 0x200000
│   ┌──────────────────────────────┐   │
│   │         FIT Image            │   │
│   │   (kernel + initramfs + dtb) │   │
│   └──────────────────────────────┘   │
├──────────────────────────────────────┤
│        Image B (Standby)             │ 0x1000000
│   ┌──────────────────────────────┐   │
│   │         FIT Image            │   │
│   └──────────────────────────────┘   │
├──────────────────────────────────────┤
│           RW Partition               │ 0x1E00000
└──────────────────────────────────────┘
```

### Boot Selection Logic

```bash
# Check boot side
if test "${bootside}" = "a"; then
    kerneladdr=0x20200000
else
    kerneladdr=0x21000000
fi

# Increment boot counter
setexpr bootcount ${bootcount} + 1

# Check boot limit
if test ${bootcount} -ge ${bootlimit}; then
    # Switch to other side
    if test "${bootside}" = "a"; then
        setenv bootside b
    else
        setenv bootside a
    fi
    setenv bootcount 0
fi
```

---

## Adding U-Boot to Build

### Recipe Append

```bitbake
# recipes-bsp/u-boot/u-boot-aspeed_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/u-boot-aspeed:"

SRC_URI += " \
    file://myboard_defconfig \
    file://myboard.h \
"

do_configure:prepend() {
    install -m 0644 ${WORKDIR}/myboard_defconfig \
        ${S}/configs/
    install -m 0644 ${WORKDIR}/myboard.h \
        ${S}/include/configs/
}
```

---

## U-Boot Commands

### Common Operations

```bash
# Print environment
printenv

# Set variable
setenv bootargs console=ttyS4,115200

# Save environment
saveenv

# Boot kernel
bootm ${kerneladdr}

# Reset
reset
```

### Flash Operations

```bash
# Probe SPI flash
sf probe 0

# Read flash
sf read 0x83000000 0x200000 0x800000

# Erase flash
sf erase 0x200000 0x800000

# Write flash
sf write 0x83000000 0x200000 0x800000
```

### Debug

```bash
# Memory dump
md 0x80000000 100

# I2C scan
i2c bus
i2c dev 0
i2c probe

# GPIO
gpio status
```

---

## Verified Boot

### Enable Secure Boot

```make
# In defconfig
CONFIG_FIT_SIGNATURE=y
CONFIG_RSA=y
CONFIG_FIT_SIGNATURE_ENFORCE=y
```

### Sign Images

```bash
# Sign FIT image with key
mkimage -F -k keys/ -K u-boot.dtb -r image.fit
```

---

## Troubleshooting

### Boot Fails

```bash
# Check boot counter
printenv bootcount

# Force boot side
setenv bootside a
saveenv
reset
```

### Environment Corrupt

```bash
# Reset to defaults
env default -a
saveenv
```

---

## References

- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [ASPEED U-Boot](https://github.com/AspeedTech-BMC/u-boot)
- [OpenBMC U-Boot Integration](https://github.com/openbmc/u-boot)

---

{: .note }
**Prerequisites**: Bootloader and embedded systems experience required
