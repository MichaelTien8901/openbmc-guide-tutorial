---
layout: default
title: Device Tree Guide
parent: Porting
nav_order: 3
difficulty: advanced
prerequisites:
  - machine-layer
---

# Device Tree Guide
{: .no_toc }

Configure the Linux device tree for your BMC platform.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

The device tree describes your hardware to the Linux kernel, including GPIO pins, I2C buses, SPI flash, and peripherals.

---

## Device Tree Structure

{: .note }
> **Source Reference**: OpenBMC Device Tree examples
> - ASPEED DTS: [linux/arch/arm/boot/dts/aspeed/](https://github.com/openbmc/linux/tree/dev-6.6/arch/arm/boot/dts/aspeed)
> - Reference: [aspeed-bmc-opp-romulus.dts](https://github.com/openbmc/linux/blob/dev-6.6/arch/arm/boot/dts/aspeed/aspeed-bmc-opp-romulus.dts)

```dts
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
};
```

---

## GPIO Configuration

### LED GPIOs

```dts
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
```

### Button GPIOs

```dts
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
```

---

## I2C Bus Configuration

```dts
&i2c0 {
    status = "okay";

    /* Temperature sensor */
    tmp75@48 {
        compatible = "ti,tmp75";
        reg = <0x48>;
    };
};

&i2c1 {
    status = "okay";

    /* FRU EEPROM */
    eeprom@50 {
        compatible = "atmel,24c256";
        reg = <0x50>;
    };
};

&i2c2 {
    status = "okay";

    /* Power supply */
    psu@58 {
        compatible = "pmbus";
        reg = <0x58>;
    };
};
```

---

## SPI Flash Configuration

```dts
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
    flash@0 {
        status = "okay";
        label = "pnor";
        spi-max-frequency = <100000000>;
    };
};
```

---

## Network Configuration

### NCSI (Sideband)

```dts
&mac0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_rmii1_default>;
    use-ncsi;
};
```

### Dedicated Ethernet

```dts
&mac1 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_rgmii2_default>;
    phy-mode = "rgmii";
    phy-handle = <&phy1>;
};
```

---

## PWM/Fan Configuration

```dts
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
```

---

## Console/UART Configuration

```dts
&uart5 {
    status = "okay";
};

&vuart {
    status = "okay";
};
```

---

## Video Capture (KVM)

```dts
reserved-memory {
    video_memory: video {
        size = <0x04000000>;  /* 64MB */
        alignment = <0x01000000>;
        compatible = "shared-dma-pool";
        reusable;
    };
};

&video {
    status = "okay";
    memory-region = <&video_memory>;
};
```

---

## Adding Device Tree to Build

```bitbake
# recipes-kernel/linux/linux-aspeed_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/linux-aspeed:"

SRC_URI += "file://aspeed-bmc-myplatform-myboard.dts"

do_configure:append() {
    cp ${WORKDIR}/aspeed-bmc-myplatform-myboard.dts \
        ${S}/arch/arm/boot/dts/aspeed/
}
```

---

## Debugging Device Tree

```bash
# View compiled device tree
dtc -I dtb -O dts /sys/firmware/fdt

# Check GPIO assignments
cat /sys/kernel/debug/gpio

# Check I2C buses
i2cdetect -l
i2cdetect -y 0
```

---

## References

- [Linux Device Tree Documentation](https://www.kernel.org/doc/Documentation/devicetree/)
- [ASPEED Device Tree Bindings](https://github.com/torvalds/linux/tree/master/Documentation/devicetree/bindings/arm/aspeed)
- [Device Tree Specification](https://devicetree-specification.readthedocs.io/)

---

{: .note }
**Prerequisites**: Linux kernel and device tree knowledge required
