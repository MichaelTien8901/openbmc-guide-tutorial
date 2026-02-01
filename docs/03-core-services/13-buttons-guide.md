---
layout: default
title: Buttons Guide
parent: Core Services
nav_order: 13
difficulty: intermediate
prerequisites:
  - dbus-guide
  - state-manager-guide
---

# Buttons Guide
{: .no_toc }

Configure power, reset, and ID buttons on OpenBMC.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**phosphor-buttons** handles physical button inputs (power, reset, ID) and translates them to system actions.

```
+-------------------------------------------------------------------+
|                     Buttons Architecture                          |
+-------------------------------------------------------------------+
|                                                                   |
|  +------------------+  +------------------+  +------------------+ |
|  |   Power Button   |  |   Reset Button   |  |    ID Button     | |
|  |      (GPIO)      |  |      (GPIO)      |  |      (GPIO)      | |
|  +--------+---------+  +--------+---------+  +--------+---------+ |
|           |                     |                     |           |
|           v                     v                     v           |
|  +------------------------------------------------------------+   |
|  |                    phosphor-buttons                        |   |
|  |                                                            |   |
|  |   +---------------+  +---------------+  +---------------+  |   |
|  |   | Power Handler |  | Reset Handler |  |  ID Handler   |  |   |
|  |   | (short/long)  |  |               |  |               |  |   |
|  |   +---------------+  +---------------+  +---------------+  |   |
|  |                                                            |   |
|  +----------------------------+-------------------------------+   |
|                               |                                   |
|                               v                                   |
|  +------------------------------------------------------------+   |
|  |                         D-Bus                              |   |
|  +----------------------------+-------------------------------+   |
|                               |                                   |
|           +-------------------+-------------------+               |
|           |                                       |               |
|           v                                       v               |
|  +------------------+                   +------------------+      |
|  |  State Manager   |                   |   LED Manager    |      |
|  | (power control)  |                   | (identify LED)   |      |
|  +------------------+                   +------------------+      |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Setup & Configuration

### Build-Time Configuration

```bitbake
# Include buttons handler
IMAGE_INSTALL:append = " phosphor-buttons"
```

### Button Types

| Button | Function | Default Action |
|--------|----------|----------------|
| Power | Short press | Toggle power |
| Power | Long press (4s) | Force power off |
| Reset | Press | Hard reset |
| ID | Press | Toggle identify LED |

---

## GPIO Configuration

### Device Tree

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

    id-button {
        label = "id-button";
        gpios = <&gpio ASPEED_GPIO(B, 2) GPIO_ACTIVE_LOW>;
        linux,code = <0x199>;
    };
};
```

### JSON Configuration

```json
{
    "gpio_definitions": [
        {
            "name": "POWER_BUTTON",
            "pin": "GPIOB0",
            "direction": "input"
        },
        {
            "name": "RESET_BUTTON",
            "pin": "GPIOB1",
            "direction": "input"
        },
        {
            "name": "ID_BUTTON",
            "pin": "GPIOB2",
            "direction": "input"
        }
    ]
}
```

---

## Button Behavior

### Power Button

```bash
# Short press (< 4 seconds)
# Action: Request power state toggle

# Long press (≥ 4 seconds)
# Action: Force power off
```

### Reset Button

```bash
# Press triggers hard reset
# Equivalent to: obmcutil hostreboot
```

### ID Button

```bash
# Press toggles identify LED
# Can be configured for latching or momentary
```

---

## D-Bus Interface

```bash
# Check button status
busctl tree xyz.openbmc_project.Chassis.Buttons

# Monitor button events
busctl monitor xyz.openbmc_project.Chassis.Buttons
```

---

## Disabling Buttons

### Mask Power Button

```bash
# Via D-Bus
busctl set-property xyz.openbmc_project.Chassis.Buttons \
    /xyz/openbmc_project/Chassis/Buttons/Power0 \
    xyz.openbmc_project.Chassis.Buttons \
    Enabled b false
```

---

## Troubleshooting

```bash
# Check GPIO input
cat /sys/class/gpio/gpio*/value

# Check button service
systemctl status phosphor-button-handler

# Monitor key events
evtest /dev/input/event0
```

---

## References

- [phosphor-buttons](https://github.com/openbmc/phosphor-buttons)
- [Linux gpio-keys](https://www.kernel.org/doc/html/latest/input/gpio-keys.html)

---

{: .note }
**Tested on**: OpenBMC master, requires hardware GPIO support
